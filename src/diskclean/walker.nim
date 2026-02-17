{.push raises: [].}

import std/[os, options, sets, strutils]
import types

const permanentSkip* = [".git", ".hg", ".svn", ".cache"]

proc buildSkipSet*(rules: openArray[Rule]): HashSet[string] =
  ## Build skip set from all rules' targets + VCS/cache dirs.
  for d in permanentSkip: result.incl(d)
  for r in rules:
    for t in r.targets: result.incl(t)

proc dirSize*(path: string): int64 =
  ## Calculate total size of a directory recursively.
  ## Silently skips unreadable files (permission errors etc).
  if not dirExists(path): return 0
  try:
    for f in walkDirRec(path):
      try:
        result += getFileSize(f)
      except OSError:
        discard  # unreadable file — skip silently, size is best-effort
  except OSError:
    discard  # walkDirRec itself failed

proc findMarkers*(root: string, markers: openArray[string],
                  skip: HashSet[string]): seq[string] =
  ## Walk directory tree, skipping known artifact dirs,
  ## returning paths of any matching marker files.
  ##
  ## Marker patterns:
  ##   - Exact name:  "Cargo.toml"  (filename == marker)
  ##   - Suffix glob:  "*.nimble"   (filename.endsWith suffix)
  ##
  ## NOT supported: "**/" recursive glob, "?" single char, "[abc]" char class.
  if not dirExists(root): return @[]
  var exact: HashSet[string]
  var suffixes: seq[string]
  for m in markers:
    if m.startsWith("*"):
      suffixes.add(m[1..^1])   # "*.nimble" → ".nimble"
    else:
      exact.incl(m)
  var stack = @[root]
  while stack.len > 0:
    let dir = stack.pop()
    try:
      for kind, path in walkDir(dir):
        let name = extractFilename(path)
        case kind
        of pcDir, pcLinkToDir:
          if name notin skip:
            stack.add(path)
        of pcFile, pcLinkToFile:
          if name in exact:
            result.add(path)
          else:
            for sfx in suffixes:
              if name.endsWith(sfx):
                result.add(path)
                break
    except OSError:
      discard  # unreadable directory — skip

proc scan*(rule: Rule, searchRoot: string, skip: HashSet[string],
           withSize = false): seq[Project] =
  ## Scan for projects matching the given rule.
  let markers = findMarkers(searchRoot, rule.markers, skip)
  var seen: HashSet[string]
  for markerPath in markers:
    let projectRoot = parentDir(markerPath)
    if projectRoot in seen: continue
    seen.incl(projectRoot)
    var found: seq[string]
    var total: int64 = 0
    for t in rule.targets:
      let p = projectRoot / t
      if dirExists(p):
        found.add(p)
        if withSize:
          total += dirSize(p)
    if found.len > 0:
      result.add Project(
        root: projectRoot,
        rule: rule,
        targets: found,
        size: if withSize: some(total) else: none(int64))

proc scan*(rule: Rule, searchRoot: string,
           withSize = false): seq[Project] =
  ## Convenience: builds skip set from this single rule.
  scan(rule, searchRoot, buildSkipSet(@[rule]), withSize)

proc scanAll*(rules: openArray[Rule], searchRoot: string,
              withSize = false): seq[Project] =
  ## Scan for all project types. Builds skip set from ALL rules.
  ## Deduplicates projects that share the same root and target paths
  ## (e.g. Rust and Maven both targeting "target/").
  let skip = buildSkipSet(rules)
  var seenTargets: HashSet[string]
  for rule in rules:
    for project in scan(rule, searchRoot, skip, withSize):
      var uniqueTargets: seq[string]
      for t in project.targets:
        if t notin seenTargets:
          seenTargets.incl(t)
          uniqueTargets.add(t)
      if uniqueTargets.len > 0:
        var deduped = project
        deduped.targets = uniqueTargets
        result.add deduped
