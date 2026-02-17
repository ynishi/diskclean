## diskclean/cleaner — Project cleaning engine
##
## Cleans development artifacts using a two-tier strategy:
##
## 1. **Tool-first**: Runs the project's native clean command
##    (e.g. ``cargo clean``, ``flutter clean``)
## 2. **Fallback rm** *(experimental)*: Removes target directories directly.
##    Gated behind ``-d:experimentalRm`` at compile time due to the
##    inherent risk of recursive directory removal (symlink traversal, etc).
##
## Compile Flags
## =============
##
## ``-d:experimentalRm``
##   Enable fallback directory removal for projects without a native
##   clean tool. Without this flag, only tool-based cleaning is available.
##   Projects whose tool is unavailable or missing will be reported as
##   ``crkSkipped``.
##
## Even with ``experimentalRm`` enabled, symlink targets are refused
## as an additional safety measure.

{.push raises: [].}

import std/[options, os, osproc, strutils]
import types, walker, worktree

when defined(experimentalRm):
  proc containsSymlinks(dir: string): seq[string] =
    ## Walk a directory tree and return paths of any symlinks found inside.
    var stack = @[dir]
    while stack.len > 0:
      let current = stack.pop()
      try:
        for kind, path in walkDir(current):
          if kind in {pcLinkToDir, pcLinkToFile}:
            result.add(path)
          elif kind == pcDir:
            stack.add(path)
      except OSError:
        discard

proc targetSize(project: Project): int64 =
  ## Calculate total size of target dirs. Uses cached size if available.
  if project.size.isSome: return project.size.get
  for dir in project.targets:
    result += dirSize(dir)

proc cleanProject*(project: Project, dryRun = false): CleanResult =
  ## Clean a single project.
  ##
  ## Strategy:
  ##   1. Try the rule's native tool (e.g. ``cargo clean``)
  ##   2. If ``-d:experimentalRm``: fallback to ``removeDir``
  ##   3. Otherwise: return ``crkSkipped``
  ##
  ## When ``dryRun`` is true, reports what *would* happen without
  ## modifying the filesystem.

  if project.targets.len == 0:
    return CleanResult(kind: crkSkipped, project: project,
                       skipReason: "no targets")

  # 1) Try native tool
  if project.rule.tool.len > 0:
    var bin: string
    try:
      bin = findExe(project.rule.toolBin)
    except OSError:
      bin = ""
    if bin.len > 0:
      let sz = targetSize(project)
      if dryRun:
        return CleanResult(kind: crkSuccess, project: project,
                           cleanMethod: ToolClean, freed: sz)
      let parts = project.rule.tool.splitWhitespace()
      let args = if parts.len > 1: parts[1..^1] else: @[]
      try:
        let process = startProcess(bin, workingDir = project.root,
                                   args = args)
        defer: process.close()
        let code = waitForExit(process)
        if code == 0:
          return CleanResult(kind: crkSuccess, project: project,
                             cleanMethod: ToolClean, freed: sz)
      except CatchableError as e:
        return CleanResult(kind: crkError, project: project,
                           error: "failed to run " & project.rule.tool &
                                  ": " & e.msg)

  # 2) Fallback: remove directories (compile-time gated)
  when defined(experimentalRm):
    if dryRun:
      return CleanResult(kind: crkSuccess, project: project,
                         cleanMethod: FallbackRm,
                         freed: targetSize(project))

    var totalFreed: int64 = 0
    for dir in project.targets:
      try:
        if not dirExists(dir): continue
        if symlinkExists(dir):
          return CleanResult(kind: crkError, project: project,
                             error: "refusing to remove symlink: " & dir)
        let internalLinks = containsSymlinks(dir)
        if internalLinks.len > 0:
          return CleanResult(kind: crkError, project: project,
                             error: "refusing to remove: contains symlink(s): " &
                                    internalLinks[0])
        let sz = dirSize(dir)
        removeDir(dir)
        totalFreed += sz
      except OSError as e:
        return CleanResult(kind: crkError, project: project,
                           error: e.msg)
    CleanResult(kind: crkSuccess, project: project,
                cleanMethod: FallbackRm, freed: totalFreed)
  else:
    CleanResult(kind: crkSkipped, project: project,
                skipReason: "no clean tool available (build with -d:experimentalRm to enable rm fallback)")

proc cleanWorktree(wt: WorktreeInfo,
                   dryRun = false): CleanResult =
  ## Remove a merged worktree using ``git worktree remove``.
  ## Runs from the main repository directory.
  if not dirExists(wt.path):
    return CleanResult(kind: crkSkipped, project: Project(),
                       worktree: some(wt),
                       skipReason: "worktree path does not exist: " & wt.path)

  let sz = if wt.size.isSome: wt.size.get
           else: dirSize(wt.path)

  if dryRun:
    return CleanResult(kind: crkSuccess, project: Project(),
                       worktree: some(wt),
                       cleanMethod: WorktreeRemove, freed: sz)

  let (output, code) = gitExec(["-C", wt.mainRepo, "worktree", "remove", wt.path])

  if code == 0:
    CleanResult(kind: crkSuccess, project: Project(),
                worktree: some(wt),
                cleanMethod: WorktreeRemove, freed: sz)
  else:
    let detail = output.strip
    let msg = if detail.len > 0: "git worktree remove: " & detail
              else: "git worktree remove failed (exit " & $code & ")"
    CleanResult(kind: crkError, project: Project(),
                worktree: some(wt), error: msg)

proc cleanAll*(projects: seq[Project], dryRun = false): seq[CleanResult] =
  ## Clean all projects in sequence.
  for p in projects:
    result.add cleanProject(p, dryRun)

proc cleanWorktrees*(worktrees: seq[WorktreeInfo],
                     dryRun = false): seq[CleanResult] =
  ## Clean all merged worktrees in sequence.
  if resolveGitBin().len == 0:
    for wt in worktrees:
      result.add CleanResult(kind: crkError, project: Project(),
                             worktree: some(wt),
                             error: "git not found")
    return
  for wt in worktrees:
    result.add cleanWorktree(wt, dryRun)
