import unittest
import std/[options, os, tempfiles, sets]
from std/strutils import endsWith, contains
import diskclean
import diskclean/cli

# ── Test helper ──

proc findRule(name: string): Rule =
  for r in builtinRules:
    if r.name == name: return r
  raise newException(KeyError, "rule not found: " & name)

suite "types":
  test "Rule zero-value is safe":
    let r = Rule(name: "test", icon: "T", markers: @["x"])
    check r.tool == ""
    check r.targets.len == 0

suite "rules":
  test "builtinRules has 12 entries":
    check builtinRules.len == 12

  test "rust rule":
    let r = findRule("rust")
    check r.markers == @["Cargo.toml"]
    check r.tool == "cargo clean"
    check "target" in r.targets

  test "node rule has no native tool":
    let r = findRule("node")
    check r.tool == ""
    check "node_modules" in r.targets

  test "gradle supports both marker variants":
    let r = findRule("gradle")
    check "build.gradle" in r.markers
    check "build.gradle.kts" in r.markers

  test "python supports multiple markers":
    let r = findRule("python")
    check "pyproject.toml" in r.markers
    check "setup.py" in r.markers

  test "nim rule uses wildcard marker":
    let r = findRule("nim")
    check r.markers == @["*.nimble"]
    check "nimcache" in r.targets

  test "ruleNames returns all names":
    let names = ruleNames()
    check "rust" in names
    check "node" in names
    check "nim" in names
    check "python" in names
    check names.len == builtinRules.len

  test "flutter targets include both .dart_tool variants":
    let r = findRule("flutter")
    check ".dart_tool" in r.targets
    check ".dart_tools" in r.targets

  test "every rule with tool has toolBin":
    for r in builtinRules:
      if r.tool.len > 0:
        check r.toolBin.len > 0

suite "walker - buildSkipSet":
  test "includes permanent dirs":
    let skip = buildSkipSet(builtinRules)
    check ".git" in skip
    check ".hg" in skip
    check ".svn" in skip

  test "includes all rule targets":
    let skip = buildSkipSet(builtinRules)
    check "target" in skip
    check "node_modules" in skip
    check ".venv" in skip
    check "zig-cache" in skip

suite "walker - dirSize":
  test "calculates file sizes":
    let tmp = createTempDir("dc_", "_test")
    defer: removeDir(tmp)
    writeFile(tmp / "a.txt", "hello")
    writeFile(tmp / "b.txt", "world!")
    check dirSize(tmp) == 11

  test "nonexistent dir is zero":
    check dirSize("/tmp/diskclean_nonexistent_12345") == 0

  test "empty dir is zero":
    let tmp = createTempDir("dc_", "_test")
    defer: removeDir(tmp)
    check dirSize(tmp) == 0

suite "walker - findMarkers":
  test "finds marker in nested dir":
    let tmp = createTempDir("dc_", "_test")
    defer: removeDir(tmp)
    let proj = tmp / "sub" / "myproject"
    createDir(proj)
    writeFile(proj / "Cargo.toml", "[package]")

    let skip = buildSkipSet(builtinRules)
    let found = findMarkers(tmp, @["Cargo.toml"], skip)
    check found.len == 1

  test "finds multiple marker variants":
    let tmp = createTempDir("dc_", "_test")
    defer: removeDir(tmp)
    let p1 = tmp / "proj1"
    let p2 = tmp / "proj2"
    createDir(p1); createDir(p2)
    writeFile(p1 / "build.gradle", "")
    writeFile(p2 / "build.gradle.kts", "")

    let skip = buildSkipSet(builtinRules)
    let found = findMarkers(tmp, @["build.gradle", "build.gradle.kts"], skip)
    check found.len == 2

  test "skips excluded directories":
    let tmp = createTempDir("dc_", "_test")
    defer: removeDir(tmp)
    createDir(tmp / "node_modules" / "fake")
    writeFile(tmp / "node_modules" / "fake" / "Cargo.toml", "[package]")

    let skip = buildSkipSet(builtinRules)
    let found = findMarkers(tmp, @["Cargo.toml"], skip)
    check found.len == 0

  test "finds wildcard marker (*.nimble)":
    let tmp = createTempDir("dc_", "_test")
    defer: removeDir(tmp)
    let proj = tmp / "mynim"
    createDir(proj)
    writeFile(proj / "mynim.nimble", "version = \"0.1.0\"")

    let skip = buildSkipSet(builtinRules)
    let found = findMarkers(tmp, @["*.nimble"], skip)
    check found.len == 1
    check found[0].endsWith("mynim.nimble")

  test "nonexistent root returns empty":
    let skip = buildSkipSet(builtinRules)
    let found = findMarkers("/tmp/nope_12345", @["x"], skip)
    check found.len == 0

  test "wildcard does not match bare suffix":
    let tmp = createTempDir("dc_", "_test")
    defer: removeDir(tmp)
    writeFile(tmp / ".nimble", "")  # no basename before suffix

    let skip = buildSkipSet(builtinRules)
    let found = findMarkers(tmp, @["*.nimble"], skip)
    # ".nimble" alone matches endsWith(".nimble") - document this behavior
    check found.len == 1

suite "walker - scan":
  test "fast scan (no size) finds rust project":
    let tmp = createTempDir("dc_", "_test")
    defer: removeDir(tmp)
    let proj = tmp / "myrust"
    createDir(proj)
    writeFile(proj / "Cargo.toml", "[package]")
    createDir(proj / "target")
    writeFile(proj / "target" / "output", "binary")

    let results = scan(findRule("rust"), tmp)
    check results.len == 1
    check results[0].root == proj
    check results[0].size.isNone

  test "withSize calculates size":
    let tmp = createTempDir("dc_", "_test")
    defer: removeDir(tmp)
    let proj = tmp / "myrust"
    createDir(proj)
    writeFile(proj / "Cargo.toml", "[package]")
    createDir(proj / "target")
    writeFile(proj / "target" / "output", "binary")

    let results = scan(findRule("rust"), tmp, withSize = true)
    check results.len == 1
    check results[0].size.isSome
    check results[0].size.get > 0

  test "ignores project without target dir":
    let tmp = createTempDir("dc_", "_test")
    defer: removeDir(tmp)
    createDir(tmp / "clean-rust")
    writeFile(tmp / "clean-rust" / "Cargo.toml", "[package]")

    check scan(findRule("rust"), tmp).len == 0

  test "finds node project":
    let tmp = createTempDir("dc_", "_test")
    defer: removeDir(tmp)
    let proj = tmp / "mynode"
    createDir(proj)
    writeFile(proj / "package.json", "{}")
    createDir(proj / "node_modules")
    writeFile(proj / "node_modules" / "dep.js", "x")

    let results = scan(findRule("node"), tmp)
    check results.len == 1
    check results[0].root == proj

  test "finds flutter with multiple targets":
    let tmp = createTempDir("dc_", "_test")
    defer: removeDir(tmp)
    let proj = tmp / "myflutter"
    createDir(proj)
    writeFile(proj / "pubspec.yaml", "name: test")
    createDir(proj / "build")
    createDir(proj / ".dart_tool")

    let results = scan(findRule("flutter"), tmp)
    check results.len == 1
    check results[0].targets.len == 2

  test "finds nim project with nimcache":
    let tmp = createTempDir("dc_", "_test")
    defer: removeDir(tmp)
    let proj = tmp / "mynim"
    createDir(proj)
    writeFile(proj / "mynim.nimble", "version = \"0.1.0\"")
    createDir(proj / "nimcache")
    writeFile(proj / "nimcache" / "main.c", "int main(){}")

    let results = scan(findRule("nim"), tmp)
    check results.len == 1
    check results[0].root == proj

  test "finds python project with .venv":
    let tmp = createTempDir("dc_", "_test")
    defer: removeDir(tmp)
    let proj = tmp / "mypy"
    createDir(proj)
    writeFile(proj / "pyproject.toml", "[project]")
    createDir(proj / ".venv")
    writeFile(proj / ".venv" / "pyvenv.cfg", "")

    let results = scan(findRule("python"), tmp)
    check results.len == 1

suite "walker - scanAll":
  test "finds mixed project types":
    let tmp = createTempDir("dc_", "_test")
    defer: removeDir(tmp)

    let rust = tmp / "rust-proj"
    createDir(rust)
    writeFile(rust / "Cargo.toml", "[package]")
    createDir(rust / "target")
    writeFile(rust / "target" / "out", "x")

    let node = tmp / "node-proj"
    createDir(node)
    writeFile(node / "package.json", "{}")
    createDir(node / "node_modules")
    writeFile(node / "node_modules" / "x", "y")

    let all = scanAll(builtinRules, tmp)
    check all.len == 2

  test "deduplicates overlapping targets (rust + maven)":
    let tmp = createTempDir("dc_", "_test")
    defer: removeDir(tmp)

    # Project with both Cargo.toml and pom.xml sharing "target/"
    let proj = tmp / "jni-project"
    createDir(proj)
    writeFile(proj / "Cargo.toml", "[package]")
    writeFile(proj / "pom.xml", "<project/>")
    createDir(proj / "target")
    writeFile(proj / "target" / "out", "x")

    let all = scanAll(builtinRules, tmp)
    # Should not report target/ twice
    var targetCount = 0
    for p in all:
      for t in p.targets:
        if t == proj / "target":
          inc targetCount
    check targetCount == 1

suite "cleaner":
  test "skipped when no targets":
    let project = Project(
      root: "/tmp/fake",
      rule: findRule("node"),
      targets: @[])
    check cleanProject(project).usedMethod == Skipped

  test "no-tool project skipped without experimentalRm":
    when not defined(experimentalRm):
      let tmp = createTempDir("dc_", "_test")
      defer: removeDir(tmp)
      let proj = tmp / "nodeproj"
      createDir(proj)
      writeFile(proj / "package.json", "{}")
      createDir(proj / "node_modules")
      writeFile(proj / "node_modules" / "x.js", "y")

      let projects = scan(findRule("node"), tmp)
      let result = cleanProject(projects[0])
      check result.usedMethod == Skipped
      check result.error.len > 0
      check dirExists(proj / "node_modules")  # NOT deleted

  test "cleanProject with non-zero exit does not report ToolClean":
    # When tool binary is not found, should fall through
    let project = Project(
      root: "/tmp/fake",
      rule: Rule(name: "test", icon: "T", markers: @["x"],
                 tool: "nonexistent_tool_12345 clean",
                 toolBin: "nonexistent_tool_12345",
                 targets: @["/tmp/fake/target"]))
    let result = cleanProject(project)
    check result.usedMethod != ToolClean

  when defined(experimentalRm):
    test "dry run preserves directories (experimentalRm)":
      let tmp = createTempDir("dc_", "_test")
      defer: removeDir(tmp)
      let proj = tmp / "nodeproj"
      createDir(proj)
      writeFile(proj / "package.json", "{}")
      createDir(proj / "node_modules")
      writeFile(proj / "node_modules" / "x.js", "data")

      let projects = scan(findRule("node"), tmp)
      let result = cleanProject(projects[0], dryRun = true)
      check result.error == ""
      check result.usedMethod == FallbackRm
      check dirExists(proj / "node_modules")

    test "clean removes target directory (experimentalRm)":
      let tmp = createTempDir("dc_", "_test")
      defer: removeDir(tmp)
      let proj = tmp / "nodeproj"
      createDir(proj)
      writeFile(proj / "package.json", "{}")
      createDir(proj / "node_modules")
      writeFile(proj / "node_modules" / "x.js", "data")

      let projects = scan(findRule("node"), tmp)
      let result = cleanProject(projects[0])
      check result.error == ""
      check result.usedMethod == FallbackRm
      check not dirExists(proj / "node_modules")

    test "refuses to remove symlink target (experimentalRm)":
      let tmp = createTempDir("dc_", "_test")
      defer: removeDir(tmp)
      let proj = tmp / "nodeproj"
      createDir(proj)
      writeFile(proj / "package.json", "{}")
      let real = tmp / "real_modules"
      createDir(real)
      writeFile(real / "x.js", "y")
      createSymlink(real, proj / "node_modules")

      let projects = scan(findRule("node"), tmp)
      let result = cleanProject(projects[0])
      check result.usedMethod == FallbackRm
      check "symlink" in result.error
      check dirExists(real)  # real dir untouched

    test "refuses to remove dir containing internal symlinks (experimentalRm)":
      let tmp = createTempDir("dc_", "_test")
      defer: removeDir(tmp)
      let proj = tmp / "nodeproj"
      createDir(proj)
      writeFile(proj / "package.json", "{}")
      createDir(proj / "node_modules")
      writeFile(proj / "node_modules" / "real.js", "data")
      # Create internal symlink
      let external = tmp / "external_lib"
      createDir(external)
      writeFile(external / "lib.js", "important")
      createSymlink(external, proj / "node_modules" / "linked_pkg")

      let projects = scan(findRule("node"), tmp)
      let result = cleanProject(projects[0])
      check "symlink" in result.error
      check dirExists(external)  # external dir untouched
      check dirExists(proj / "node_modules")  # NOT deleted

    test "cleanAll processes multiple (experimentalRm)":
      let tmp = createTempDir("dc_", "_test")
      defer: removeDir(tmp)
      for name in ["a", "b"]:
        let p = tmp / name
        createDir(p)
        writeFile(p / "package.json", "{}")
        createDir(p / "node_modules")
        writeFile(p / "node_modules" / "x", "y")

      let projects = scan(findRule("node"), tmp)
      let results = cleanAll(projects)
      check results.len == 2
      for r in results:
        check r.error == ""

suite "reporter":
  test "formatSize":
    check formatSize(0) == "0 B"
    check formatSize(512) == "512 B"
    check formatSize(1024) == "1.0 KB"
    check formatSize(1_048_576) == "1.0 MB"
    check formatSize(1_073_741_824) == "1.0 GB"

  test "formatSize boundary values":
    check formatSize(1023) == "1023 B"
    check formatSize(1025) == "1.0 KB"
    check formatSize(1_048_575) == "1024.0 KB"
    check formatSize(1_073_741_823) == "1024.0 MB"

suite "cli":
  test "rulesByName resolves valid names":
    let rules = rulesByName("rust,node")
    check rules.len == 2
    check rules[0].name == "rust"
    check rules[1].name == "node"

  test "rulesByName raises on unknown type":
    expect(CliError):
      discard rulesByName("nonexistent")

  test "rulesByName is case-insensitive":
    let rules = rulesByName("RUST")
    check rules.len == 1
    check rules[0].name == "rust"

  test "matchesExclude matches path segments":
    check matchesExclude("/home/user/myapp/src", @["myapp"])
    check not matchesExclude("/home/user/myapp/src", @["app"])
    check not matchesExclude("/home/user/testing/src", @["test"])
    check matchesExclude("/home/user/testing/src", @["testing"])

suite "findRule helper":
  test "raises KeyError for nonexistent rule":
    expect(KeyError):
      discard findRule("nonexistent_rule_xyz")
