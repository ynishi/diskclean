{.push raises: [].}

import std/sequtils
import types

const builtinRules* = @[
  # ── Systems ──
  Rule(name: "rust", icon: "🦀",
    markers: @["Cargo.toml"],
    tool: "cargo clean", toolBin: "cargo",
    targets: @["target"]),

  Rule(name: "zig", icon: "⚡",
    markers: @["build.zig"],
    tool: "", toolBin: "",
    targets: @["zig-cache", "zig-out"]),

  Rule(name: "swift", icon: "🐦",
    markers: @["Package.swift"],
    tool: "swift package clean", toolBin: "swift",
    targets: @[".build"]),

  # ── JVM ──
  Rule(name: "gradle", icon: "🐘",
    markers: @["build.gradle", "build.gradle.kts"],
    tool: "gradle clean", toolBin: "gradle",
    targets: @["build", ".gradle"]),

  Rule(name: "maven", icon: "🪶",
    markers: @["pom.xml"],
    tool: "mvn clean", toolBin: "mvn",
    targets: @["target"]),

  # ── Web / Frontend ──
  Rule(name: "node", icon: "📦",
    markers: @["package.json"],
    tool: "", toolBin: "",
    targets: @["node_modules"]),

  Rule(name: "composer", icon: "🎵",
    markers: @["composer.json"],
    tool: "", toolBin: "",
    targets: @["vendor"]),

  # ── Mobile ──
  Rule(name: "flutter", icon: "🦋",
    markers: @["pubspec.yaml"],
    tool: "flutter clean", toolBin: "flutter",
    targets: @["build", ".dart_tool", ".dart_tools"]),

  # ── Functional ──
  Rule(name: "haskell", icon: "λ",
    markers: @["stack.yaml"],
    tool: "stack clean", toolBin: "stack",
    targets: @[".stack-work"]),

  Rule(name: "elixir", icon: "💧",
    markers: @["mix.exs"],
    tool: "mix clean", toolBin: "mix",
    targets: @["_build", "deps"]),

  # ── Nim ──
  Rule(name: "nim", icon: "👑",
    markers: @["*.nimble"],
    tool: "", toolBin: "",
    targets: @["nimcache"]),

  # ── Python ──
  Rule(name: "python", icon: "🐍",
    markers: @["pyproject.toml", "setup.py"],
    tool: "", toolBin: "",
    targets: @[".venv", "venv", "dist", ".tox",
               "__pycache__", ".mypy_cache", ".pytest_cache"]),
]

proc ruleNames*(): seq[string] =
  builtinRules.mapIt(it.name)
