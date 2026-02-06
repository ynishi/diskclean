import std/[os, strutils, sequtils, parseopt]
import types, rules, walker, cleaner, reporter

const Version = "0.1.0"

const Help = """
diskclean — Declarative disk cleanup for development projects

Usage:
  diskclean [options] [path]

Arguments:
  path                Search root (default: current directory)

Options:
  -h, --help          Show this help
  -v, --version       Show version
  -l, --list          List supported project types
  --size              Calculate directory sizes (slower)
  --clean             Actually delete (default: scan only)
  --dry-run           Show what would be cleaned (with --clean)
  --only=TYPE[,TYPE]  Filter by type (comma-separated)
  --exclude=PATH      Exclude project path (substring match, repeatable)

Examples:
  diskclean                            Scan current directory (fast)
  diskclean /path/to/code              Scan specific directory
  diskclean --size                     Scan with size info
  diskclean --only=rust                Rust projects only
  diskclean --only=rust,node           Rust + Node only
  diskclean --clean --dry-run          Preview what would be cleaned
  diskclean --clean                    Clean all found projects
  diskclean --clean --only=node        Clean node_modules only
  diskclean --exclude=myapp --clean    Clean all except myapp
"""

proc showTypes() =
  echo "Supported project types:"
  echo ""
  for r in builtinRules:
    var line = "  " & r.icon & "  " & alignLeft(r.name, 12)
    line &= alignLeft(r.markers.join(", "), 32)
    if r.targets.len > 0:
      line &= "→ " & r.targets.join(", ")
    if r.tool.len > 0:
      line &= "  [" & r.tool & "]"
    echo line

proc rulesByName(names: string): seq[Rule] =
  for name in names.split(","):
    let lower = name.strip.toLowerAscii
    var found = false
    for r in builtinRules:
      if r.name == lower:
        result.add(r)
        found = true
        break
    if not found:
      echo "Unknown type: " & name.strip
      echo "Available: " & ruleNames().join(", ")
      quit(1)

proc run*() =
  var searchRoot = getCurrentDir()
  var withSize = false
  var doClean = false
  var dryRun = false
  var selectedRules = builtinRules
  var excludes: seq[string]

  var p = initOptParser()
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      case p.key
      of "h", "help":
        echo Help
        quit(0)
      of "v", "version":
        echo "diskclean " & Version
        quit(0)
      of "l", "list":
        showTypes()
        quit(0)
      of "size":
        withSize = true
      of "clean":
        doClean = true
      of "dry-run":
        dryRun = true
      of "only":
        selectedRules = rulesByName(p.val)
      of "exclude":
        excludes.add(p.val)
      else:
        echo "Unknown option: --" & p.key
        echo "Run diskclean --help for usage"
        quit(1)
    of cmdArgument:
      searchRoot = p.key

  echo "Scanning: " & searchRoot
  if withSize:
    echo "(with size calculation)"
  echo ""

  var projects = scanAll(selectedRules, searchRoot, withSize)

  if excludes.len > 0:
    projects = projects.filterIt(
      block:
        var dominated = false
        for ex in excludes:
          if ex in it.root:
            dominated = true
            break
        not dominated
    )

  reportScan(projects)

  if doClean and projects.len > 0:
    echo ""
    if dryRun:
      echo "--- Dry Run ---"
      let results = cleanAll(projects, dryRun = true)
      reportClean(results)
    else:
      echo "--- Cleaning ---"
      let results = cleanAll(projects)
      reportClean(results)
