import std/os
import diskclean

when isMainModule:
  var searchRoot = expandTilde("~/projects")
  var withSize = false

  for i in 1..paramCount():
    let arg = paramStr(i)
    if arg == "--size":
      withSize = true
    else:
      searchRoot = arg

  echo "Scanning: " & searchRoot
  if withSize:
    echo "(with size calculation — may take a while)"
  echo ""

  let projects = scanAll(builtinRules, searchRoot, withSize)
  reportScan(projects)
