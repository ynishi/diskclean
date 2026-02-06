import std/[options, strutils]
import types

proc formatSize*(bytes: int64): string =
  if bytes >= 1_073_741_824:
    formatFloat(bytes.float / 1_073_741_824.0, ffDecimal, 1) & " GB"
  elif bytes >= 1_048_576:
    formatFloat(bytes.float / 1_048_576.0, ffDecimal, 1) & " MB"
  elif bytes >= 1024:
    formatFloat(bytes.float / 1024.0, ffDecimal, 1) & " KB"
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
    echo "Total reclaimable: " & formatSize(total) &
         " across " & $projects.len & " projects"
  else:
    echo $projects.len & " projects found"

proc reportClean*(results: seq[CleanResult]) =
  var freed: int64 = 0
  var errors = 0
  for r in results:
    if r.error.len > 0:
      echo "✗ " & r.project.root & "  " & r.error
      inc errors
    else:
      let m = case r.usedMethod
        of ToolClean:  r.project.rule.tool
        of FallbackRm: "rm"
        of Skipped:    "skip"
      var line = "✓ " & r.project.rule.icon & "  " & r.project.root
      if r.freed > 0:
        line &= "  " & formatSize(r.freed)
      line &= "  [" & m & "]"
      echo line
      freed += r.freed
  echo ""
  if errors > 0:
    echo $errors & " error(s)"
  echo "Freed: " & formatSize(freed)
