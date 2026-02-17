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
##   ``Skipped``.
##
## Even with ``experimentalRm`` enabled, symlink targets are refused
## as an additional safety measure.

import std/[options, os, osproc, strutils]
import types, walker

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
  ##   3. Otherwise: return ``Skipped``
  ##
  ## When ``dryRun`` is true, reports what *would* happen without
  ## modifying the filesystem.
  result.project = project

  if project.targets.len == 0:
    result.usedMethod = Skipped
    return

  # 1) Try native tool
  if project.rule.tool.len > 0:
    let bin = findExe(project.rule.toolBin)
    if bin.len > 0:
      let sz = targetSize(project)
      if dryRun:
        result.usedMethod = ToolClean
        result.freed = sz
        return
      let parts = project.rule.tool.splitWhitespace()
      let args = if parts.len > 1: parts[1..^1] else: @[]
      let process = startProcess(bin, workingDir = project.root,
                                 args = args)
      defer: process.close()
      let code = waitForExit(process)
      if code == 0:
        result.usedMethod = ToolClean
        result.freed = sz
        return

  # 2) Fallback: remove directories (compile-time gated)
  when defined(experimentalRm):
    if dryRun:
      result.usedMethod = FallbackRm
      result.freed = targetSize(project)
      return

    result.usedMethod = FallbackRm
    for dir in project.targets:
      try:
        if not dirExists(dir): continue
        if symlinkExists(dir):
          result.error = "refusing to remove symlink: " & dir
          return
        let internalLinks = containsSymlinks(dir)
        if internalLinks.len > 0:
          result.error = "refusing to remove: contains symlink(s): " &
                         internalLinks[0]
          return
        let sz = dirSize(dir)
        removeDir(dir)
        result.freed += sz
      except OSError as e:
        result.error = e.msg
        return
  else:
    result.usedMethod = Skipped
    result.error = "no clean tool available (build with -d:experimentalRm to enable rm fallback)"

proc cleanAll*(projects: seq[Project], dryRun = false): seq[CleanResult] =
  ## Clean all projects in sequence.
  for p in projects:
    result.add cleanProject(p, dryRun)
