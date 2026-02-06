import unittest
import std/[options, os, tempfiles, sets]
from std/strutils import endsWith, contains
import diskclean

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
