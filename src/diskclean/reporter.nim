{.push raises: [].}

import std/[options, strutils]
import types

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

proc reportClean*(results: seq[CleanResult]) =
  var freed: int64 = 0
  var errors = 0
  var skipped = 0
  for r in results:
    case r.kind
    of crkError:
      echo "✗ " & r.project.root & "  " & r.error
      inc errors
    of crkSkipped:
      echo "- " & r.project.rule.icon & "  " & r.project.root &
           "  [skip: " & r.skipReason & "]"
      inc skipped
    of crkSuccess:
      let m = case r.cleanMethod
        of ToolClean:  r.project.rule.tool
        of FallbackRm: "rm"
      var line = "✓ " & r.project.rule.icon & "  " & r.project.root
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
