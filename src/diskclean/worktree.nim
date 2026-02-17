## diskclean/worktree — Detect merged git worktrees
##
## Scans for git repositories under a search root, then identifies
## worktrees whose branch has been merged into main (or master).
## These worktrees are safe to remove with ``git worktree remove``.
##
## Detection flow:
##   1. Walk directories to find ``.git`` directories (main repos)
##   2. For each repo, run ``git worktree list --porcelain``
##   3. Parse output to extract worktree paths and branches
##   4. Run ``git branch --merged <main-branch>`` to get merged branches
##   5. Cross-reference: worktrees on merged branches → candidates

{.push raises: [].}

import std/[os, options, osproc, sets, streams, strutils]
import types, walker

const
  ## Display-only rule for reporter icon/label. Not used in walker.scan
  ## (worktrees are detected via git commands, not marker files).
  worktreeRule* = Rule(
    name: "worktree", icon: "🌳",
    markers: @[], tool: "git worktree remove", toolBin: "git",
    targets: @[])

  prefixWorktree = "worktree "
  prefixBranch   = "branch refs/heads/"

  ## Directories to skip when searching for git repos.
  ## Superset of walker.permanentSkip — includes common artifact dirs
  ## that would never contain a top-level .git directory.
  repoSearchSkip = ["node_modules", "target", ".build", "build",
                     "vendor", ".venv", "venv"]

type
  ParsedWorktree* = object
    path*: string
    branch*: string   # empty for detached HEAD or bare
    isBare*: bool

var cachedGitBin: string
var gitBinResolved = false

proc resolveGitBin*(): string =
  ## Resolve git binary path once per process.
  if not gitBinResolved:
    try:
      cachedGitBin = findExe("git")
    except OSError:
      cachedGitBin = ""
    gitBinResolved = true
  cachedGitBin

proc gitExec*(args: openArray[string]): tuple[output: string, code: int] =
  ## Run a git command via startProcess with explicit args (no shell).
  ## Returns ("", -1) if git binary is unavailable or process fails.
  let gitBin = resolveGitBin()
  if gitBin.len == 0:
    return ("", -1)
  try:
    let process = startProcess(gitBin, args = @args,
                               options = {poUsePath, poStdErrToStdOut})
    defer: process.close()
    let output = process.outputStream.readAll()
    let code = process.waitForExit()
    (output, code)
  except CatchableError:
    ("", -1)

proc detectMainBranch(repoPath: string): string =
  ## Detect the default branch name (main or master).
  for candidate in ["main", "master"]:
    let (_, code) = gitExec(["-C", repoPath, "rev-parse",
                             "--verify", "--quiet", candidate])
    if code == 0:
      return candidate
  return ""

proc parseWorktreeList*(output: string): seq[ParsedWorktree] =
  ## Parse ``git worktree list --porcelain`` output.
  ##
  ## Format::
  ##   worktree /path/to/wt
  ##   HEAD abc123
  ##   branch refs/heads/feature/xxx
  ##   <blank line>
  var current: ParsedWorktree
  var inEntry = false
  for line in output.splitLines:
    if line.startsWith(prefixWorktree):
      if inEntry:
        result.add(current)
      current = ParsedWorktree()
      current.path = line[prefixWorktree.len..^1]  # porcelain: no trailing space
      inEntry = true
    elif line.startsWith(prefixBranch):
      current.branch = line[prefixBranch.len..^1]  # porcelain: no trailing space
    elif line.strip == "bare":
      current.isBare = true
    elif line.strip == "" and inEntry:
      result.add(current)
      current = ParsedWorktree()
      inEntry = false
  if inEntry:
    result.add(current)

proc getMergedBranches(repoPath: string, mainBranch: string): HashSet[string] =
  ## Get branches that have been merged into the main branch.
  ## Branch prefixes: ``*`` = current, ``+`` = checked out in another worktree.
  let (output, code) = gitExec(["-C", repoPath, "branch", "--merged", mainBranch])
  if code != 0:
    return
  for line in output.splitLines:
    # git branch output: "  name" / "* name" / "+ name" — fixed 2-char prefix
    if line.len < 3: continue
    let name = line[2..^1].strip
    if name.len > 0 and name != mainBranch:
      result.incl(name)

proc isDirty(worktreePath: string): bool =
  ## Check if a worktree has uncommitted changes (staged or unstaged).
  let (output, code) = gitExec(["-C", worktreePath, "status", "--porcelain"])
  code != 0 or output.strip.len > 0

proc findGitRepos*(searchRoot: string): seq[string] =
  ## Find **main** git repositories under searchRoot by locating ``.git``
  ## **directories**. Worktree checkouts (where ``.git`` is a file pointing
  ## to the main repo) are intentionally excluded — worktree info is
  ## obtained from the main repo via ``git worktree list``.
  ## Reuses ``walker.permanentSkip`` plus common artifact dirs.
  if not dirExists(searchRoot): return @[]
  var skip: HashSet[string]
  for d in permanentSkip: skip.incl(d)
  for d in repoSearchSkip: skip.incl(d)

  var stack = @[searchRoot]
  while stack.len > 0:
    let dir = stack.pop()
    try:
      var hasGitDir = false
      for kind, path in walkDir(dir):
        let name = extractFilename(path)
        case kind
        of pcDir:
          if name == ".git":
            hasGitDir = true
          elif name notin skip:
            stack.add(path)
        of pcLinkToDir:
          discard  # skip symlinks to avoid cycles
        else:
          discard
      if hasGitDir:
        result.add(dir)
    except OSError:
      discard

proc scanWorktrees*(searchRoot: string, withSize = false): seq[WorktreeInfo] =
  ## Scan for merged, clean worktrees under searchRoot.
  ## Dirty worktrees (uncommitted changes) are excluded.
  if resolveGitBin().len == 0:
    return @[]

  let repos = findGitRepos(searchRoot)
  for repo in repos:
    let mainBranch = detectMainBranch(repo)
    if mainBranch.len == 0:
      continue

    let (wtOutput, wtCode) = gitExec(["-C", repo, "worktree", "list", "--porcelain"])
    if wtCode != 0:
      continue

    let worktrees = parseWorktreeList(wtOutput)
    if worktrees.len <= 1:
      continue

    let merged = getMergedBranches(repo, mainBranch)
    if merged.len == 0:
      continue

    for wt in worktrees:
      if wt.isBare: continue
      if wt.branch.len == 0: continue
      if wt.path == repo: continue
      if wt.branch notin merged: continue
      let exists = dirExists(wt.path)
      if exists and isDirty(wt.path): continue

      var info = WorktreeInfo(
        path: wt.path,
        branch: wt.branch,
        mainRepo: repo)

      if withSize and exists:
        info.size = some(dirSize(wt.path))

      result.add(info)
