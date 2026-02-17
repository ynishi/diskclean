{.push raises: [].}

import std/[options, strutils]
import types, worktree

const
  GiB = 1_073_741_824'i64
  MiB = 1_048_576'i64
  KiB = 1024'i64

proc formatSize*(bytes: int64): string =
  if bytes >= GiB:
    formatFloat(bytes.float / GiB.float, ffDecimal, 1) & " GB"
  elif bytes >= MiB:
    formatFloat(bytes.float / MiB.float, ffDecimal, 1) & " MB"
  elif bytes >= KiB:
    formatFloat(bytes.float / KiB.float, ffDecimal, 1) & " KB"
  else:
    $bytes & " B"

proc reportScan*(projects: seq[Project]) =
  if projects.len == 0:
    echo "No cleanable projects found."
    return
  var total: int64 = 0
  var hasSize = false
  for p in projects:
    if p.size.isSome:
      hasSize = true
      let sz = p.size.get
      echo p.rule.icon & "  " & p.root & "  " & formatSize(sz)
      total += sz
    else:
      let dirs = p.targets.len
      echo p.rule.icon & "  " & p.root & "  (" & $dirs & " dir)"
  echo ""
  if hasSize:
    echo "Total reclaimable: ~" & formatSize(total) &
         " across " & $projects.len & " projects"
  else:
    echo $projects.len & " projects found"

proc reportWorktreeScan*(worktrees: seq[WorktreeInfo]) =
  if worktrees.len == 0:
    echo "No merged worktrees found."
    return
  var total: int64 = 0
  var hasSize = false
  for wt in worktrees:
    var line = worktreeRule.icon & "  " & wt.path & "  [" & wt.branch & "]"
    if wt.size.isSome:
      hasSize = true
      let sz = wt.size.get
      line &= "  " & formatSize(sz)
      total += sz
    echo line
  echo ""
  if hasSize:
    echo "Merged worktrees: " & formatSize(total) &
         " across " & $worktrees.len & " worktrees"
  else:
    echo $worktrees.len & " merged worktrees found"

proc reportClean*(results: seq[CleanResult]) =
  var freed: int64 = 0
  var errors = 0
  var skipped = 0
  for r in results:
    let isWorktree = r.worktree.isSome
    case r.kind
    of crkError:
      let label = if isWorktree: r.worktree.get.path
                  else: r.project.root
      echo "✗ " & label & "  " & r.error
      inc errors
    of crkSkipped:
      let (icon, label) =
        if isWorktree:
          (worktreeRule.icon, r.worktree.get.path)
        else:
          (r.project.rule.icon, r.project.root)
      echo "- " & icon & "  " & label &
           "  [skip: " & r.skipReason & "]"
      inc skipped
    of crkSuccess:
      let m = case r.cleanMethod
        of ToolClean:      r.project.rule.tool
        of FallbackRm:     "rm"
        of WorktreeRemove: "git worktree remove"
      let (icon, label) =
        if isWorktree:
          (worktreeRule.icon,
           r.worktree.get.path & "  [" & r.worktree.get.branch & "]")
        else:
          (r.project.rule.icon, r.project.root)
      var line = "✓ " & icon & "  " & label
      if r.freed > 0:
        line &= "  ~" & formatSize(r.freed)
      line &= "  [" & m & "]"
      echo line
      freed += r.freed
  echo ""
  if errors > 0:
    echo $errors & " error(s)"
  if skipped > 0:
    echo $skipped & " skipped"
  echo "Freed: ~" & formatSize(freed)
