import unittest
import std/[options, os, osproc, tempfiles, sets]
from std/strutils import endsWith, contains
import diskclean
import diskclean/cli

# ── Test helpers ──

proc findRule(name: string): Rule =
  for r in builtinRules:
    if r.name == name: return r
  raise newException(KeyError, "rule not found: " & name)

# macOS: /tmp -> /private/tmp, git returns canonical paths
proc canonical(path: string): string =
  try: expandSymlink(path)
  except CatchableError: path

proc git(args: string): int =
  ## Run a git command and return exit code.
  let (output, code) = execCmdEx("git " & args)
  if code != 0:
    echo "git command failed: git " & args
    echo output
  result = code

proc initTestRepo(parentDir: string): string =
  ## Create a git repo at parentDir/repo with one commit on main.
  result = parentDir / "repo"
  createDir(result)
  doAssert git("-C " & result & " init -b main") == 0
  doAssert git("-C " & result & " config user.email test@test.com") == 0
  doAssert git("-C " & result & " config user.name test") == 0
  writeFile(result / "README.md", "hello")
  doAssert git("-C " & result & " add .") == 0
  doAssert git("-C " & result & " commit -m 'init'") == 0

proc cleanupWorktree(repo, wtPath: string) =
  discard execCmdEx("git -C " & repo & " worktree remove --force " & wtPath & " 2>/dev/null")

proc setupMergedWorktree(tmp, repo: string,
                         branchName = "feature/clean",
                         wtDirName = "repo-feat"): string =
  ## Create a merged worktree and return its path.
  result = tmp / wtDirName
  doAssert git("-C " & repo & " checkout -b " & branchName) == 0
  writeFile(repo / "feat.txt", "done")
  doAssert git("-C " & repo & " add .") == 0
  doAssert git("-C " & repo & " commit -m 'feature'") == 0
  doAssert git("-C " & repo & " checkout main") == 0
  doAssert git("-C " & repo & " merge " & branchName) == 0
  doAssert git("-C " & repo & " worktree add " & result & " " & branchName) == 0

suite "types":
  test "Rule zero-value is safe":
    let r = Rule(name: "test", icon: "T", markers: @["x"])
    check r.tool == ""
    check r.targets.len == 0

  test "CleanResult object variant — success":
    let r = CleanResult(kind: crkSuccess,
                        project: Project(root: "/tmp"),
                        cleanMethod: ToolClean, freed: 100)
    check r.kind == crkSuccess
    check r.freed == 100

  test "CleanResult object variant — skipped":
    let r = CleanResult(kind: crkSkipped,
                        project: Project(root: "/tmp"),
                        skipReason: "no targets")
    check r.kind == crkSkipped
    check r.skipReason == "no targets"

  test "CleanResult object variant — error":
    let r = CleanResult(kind: crkError,
                        project: Project(root: "/tmp"),
                        error: "permission denied")
    check r.kind == crkError
    check r.error == "permission denied"

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
    writeFile(tmp / ".nimble", "")

    let skip = buildSkipSet(builtinRules)
    let found = findMarkers(tmp, @["*.nimble"], skip)
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

    let proj = tmp / "jni-project"
    createDir(proj)
    writeFile(proj / "Cargo.toml", "[package]")
    writeFile(proj / "pom.xml", "<project/>")
    createDir(proj / "target")
    writeFile(proj / "target" / "out", "x")

    let all = scanAll(builtinRules, tmp)
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
    let r = cleanProject(project)
    check r.kind == crkSkipped
    check r.skipReason == "no targets"

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
      let r = cleanProject(projects[0])
      check r.kind == crkSkipped
      check r.skipReason.len > 0
      check dirExists(proj / "node_modules")  # NOT deleted

  test "cleanProject with missing tool binary falls through":
    let project = Project(
      root: "/tmp/fake",
      rule: Rule(name: "test", icon: "T", markers: @["x"],
                 tool: "nonexistent_tool_12345 clean",
                 toolBin: "nonexistent_tool_12345",
                 targets: @["/tmp/fake/target"]))
    let r = cleanProject(project)
    check r.kind != crkSuccess

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
      let r = cleanProject(projects[0], dryRun = true)
      check r.kind == crkSuccess
      check r.cleanMethod == FallbackRm
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
      let r = cleanProject(projects[0])
      check r.kind == crkSuccess
      check r.cleanMethod == FallbackRm
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
      let r = cleanProject(projects[0])
      check r.kind == crkError
      check "symlink" in r.error
      check dirExists(real)

    test "refuses to remove dir containing internal symlinks (experimentalRm)":
      let tmp = createTempDir("dc_", "_test")
      defer: removeDir(tmp)
      let proj = tmp / "nodeproj"
      createDir(proj)
      writeFile(proj / "package.json", "{}")
      createDir(proj / "node_modules")
      writeFile(proj / "node_modules" / "real.js", "data")
      let external = tmp / "external_lib"
      createDir(external)
      writeFile(external / "lib.js", "important")
      createSymlink(external, proj / "node_modules" / "linked_pkg")

      let projects = scan(findRule("node"), tmp)
      let r = cleanProject(projects[0])
      check r.kind == crkError
      check "symlink" in r.error
      check dirExists(external)
      check dirExists(proj / "node_modules")

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
        check r.kind == crkSuccess

suite "worktree - parseWorktreeList":
  test "parses single worktree entry":
    let output = "worktree /home/user/repo\nHEAD abc123\nbranch refs/heads/main\n\n"
    let result = parseWorktreeList(output)
    check result.len == 1
    check result[0].path == "/home/user/repo"
    check result[0].branch == "main"
    check result[0].isBare == false

  test "parses multiple worktree entries":
    let output = """worktree /home/user/repo
HEAD abc123
branch refs/heads/main

worktree /home/user/repo-feature
HEAD def456
branch refs/heads/feature/login

"""
    let result = parseWorktreeList(output)
    check result.len == 2
    check result[0].path == "/home/user/repo"
    check result[0].branch == "main"
    check result[1].path == "/home/user/repo-feature"
    check result[1].branch == "feature/login"

  test "detects bare worktree":
    let output = "worktree /home/user/repo\nHEAD abc123\nbare\n\n"
    let result = parseWorktreeList(output)
    check result.len == 1
    check result[0].isBare == true

  test "handles detached HEAD (no branch line)":
    let output = "worktree /home/user/repo-detached\nHEAD abc123\ndetached\n\n"
    let result = parseWorktreeList(output)
    check result.len == 1
    check result[0].branch == ""

  test "parses output without trailing newline":
    let output = "worktree /home/user/repo\nHEAD abc123\nbranch refs/heads/main"
    let result = parseWorktreeList(output)
    check result.len == 1
    check result[0].branch == "main"

  test "empty output returns empty":
    check parseWorktreeList("").len == 0

  test "branch name with trailing + is preserved":
    let output = "worktree /tmp/repo\nHEAD abc\nbranch refs/heads/feature/c++\n\n"
    let result = parseWorktreeList(output)
    check result.len == 1
    check result[0].branch == "feature/c++"

suite "worktree - findGitRepos":
  test "finds git repo in directory":
    let tmp = createTempDir("dc_", "_wt")
    defer: removeDir(tmp)
    let repo = tmp / "myrepo"
    createDir(repo / ".git")

    let repos = findGitRepos(tmp)
    check repos.len == 1
    check repos[0] == repo

  test "finds nested git repos":
    let tmp = createTempDir("dc_", "_wt")
    defer: removeDir(tmp)
    createDir(tmp / "a" / ".git")
    createDir(tmp / "b" / "sub" / ".git")

    let repos = findGitRepos(tmp)
    check repos.len == 2

  test "skips common artifact directories":
    let tmp = createTempDir("dc_", "_wt")
    defer: removeDir(tmp)
    createDir(tmp / "node_modules" / "fake" / ".git")
    createDir(tmp / "real" / ".git")

    let repos = findGitRepos(tmp)
    check repos.len == 1
    check repos[0] == tmp / "real"

  test "nonexistent root returns empty":
    check findGitRepos("/tmp/nonexistent_wt_12345").len == 0

suite "worktree - scanWorktrees integration":
  test "finds merged worktree in real git repo":
    let tmp = canonical(createTempDir("dc_", "_wt_integ"))
    let repo = initTestRepo(tmp)
    let wtPath = tmp / "repo-feat"
    defer:
      cleanupWorktree(repo, wtPath)
      removeDir(tmp)

    check git("-C " & repo & " checkout -b feature/done") == 0
    writeFile(repo / "feature.txt", "done")
    check git("-C " & repo & " add .") == 0
    check git("-C " & repo & " commit -m 'feature'") == 0
    check git("-C " & repo & " checkout main") == 0
    check git("-C " & repo & " merge feature/done") == 0
    check git("-C " & repo & " worktree add " & wtPath & " feature/done") == 0

    let results = scanWorktrees(tmp)
    check results.len == 1
    check results[0].branch == "feature/done"
    check results[0].mainRepo == repo

  test "does not include unmerged worktree":
    let tmp = canonical(createTempDir("dc_", "_wt_integ2"))
    let repo = initTestRepo(tmp)
    let wtPath = tmp / "repo-wip"
    defer:
      cleanupWorktree(repo, wtPath)
      removeDir(tmp)

    check git("-C " & repo & " branch feature/wip") == 0
    check git("-C " & repo & " worktree add " & wtPath & " feature/wip") == 0
    writeFile(wtPath / "wip.txt", "work in progress")
    check git("-C " & wtPath & " add .") == 0
    check git("-C " & wtPath & " commit -m 'wip'") == 0

    check scanWorktrees(tmp).len == 0

  test "excludes dirty worktree (uncommitted changes)":
    let tmp = canonical(createTempDir("dc_", "_wt_integ4"))
    let repo = initTestRepo(tmp)
    let wtPath = tmp / "repo-dirty"
    defer:
      cleanupWorktree(repo, wtPath)
      removeDir(tmp)

    check git("-C " & repo & " checkout -b feature/dirty") == 0
    writeFile(repo / "feature.txt", "done")
    check git("-C " & repo & " add .") == 0
    check git("-C " & repo & " commit -m 'feature'") == 0
    check git("-C " & repo & " checkout main") == 0
    check git("-C " & repo & " merge feature/dirty") == 0
    check git("-C " & repo & " worktree add " & wtPath & " feature/dirty") == 0
    writeFile(wtPath / "uncommitted.txt", "not committed")

    check scanWorktrees(tmp).len == 0

  test "no worktrees returns empty":
    let tmp = canonical(createTempDir("dc_", "_wt_integ3"))
    discard initTestRepo(tmp)
    defer: removeDir(tmp)

    check scanWorktrees(tmp).len == 0

suite "worktree - cleanWorktrees":
  test "dry-run reports size without removing":
    let tmp = canonical(createTempDir("dc_", "_wt_clean1"))
    let repo = initTestRepo(tmp)
    let wtPath = setupMergedWorktree(tmp, repo)
    defer:
      discard execCmdEx("git -C " & repo & " worktree remove --force " & wtPath & " 2>/dev/null")
      removeDir(tmp)

    let worktrees = scanWorktrees(tmp)
    check worktrees.len == 1

    let results = cleanWorktrees(worktrees, dryRun = true)
    check results.len == 1
    check results[0].kind == crkSuccess
    check results[0].cleanMethod == WorktreeRemove
    check results[0].freed > 0
    # Directory still exists after dry-run
    check dirExists(wtPath)

  test "actual removal deletes worktree":
    let tmp = canonical(createTempDir("dc_", "_wt_clean2"))
    let repo = initTestRepo(tmp)
    let wtPath = setupMergedWorktree(tmp, repo)
    defer: removeDir(tmp)

    let worktrees = scanWorktrees(tmp)
    check worktrees.len == 1

    let results = cleanWorktrees(worktrees)
    check results.len == 1
    check results[0].kind == crkSuccess
    check results[0].cleanMethod == WorktreeRemove
    check results[0].freed > 0
    # Directory removed
    check not dirExists(wtPath)

  test "nonexistent worktree path returns skipped":
    let wt = WorktreeInfo(
      path: "/tmp/nonexistent_wt_99999",
      branch: "feature/gone",
      mainRepo: "/tmp/nonexistent_repo_99999")

    let results = cleanWorktrees(@[wt])
    check results.len == 1
    check results[0].kind == crkSkipped
    check "does not exist" in results[0].skipReason

  test "empty list returns empty":
    let results = cleanWorktrees(@[])
    check results.len == 0

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
