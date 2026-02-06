# diskclean

Declarative disk cleanup for development projects. Tool-first, minimal, fast.

Scans a directory tree for development projects (Rust, Node, Python, etc.)
and cleans their build artifacts using each project's native clean tool.

## Install

```bash
nimble build
```

## Usage

```bash
# Scan current directory
diskclean

# Scan with size info (slower — walks target dirs)
diskclean --size

# Scan specific directory
diskclean ~/projects

# Rust projects only
diskclean --only=rust

# Rust + Node only
diskclean --only=rust,node

# Preview what would be cleaned
diskclean --clean --dry-run

# Clean all found projects
diskclean --clean

# Exclude specific projects
diskclean --exclude=myapp --clean
```

## Supported Project Types

| Type | Marker | Clean Tool | Targets |
|------|--------|------------|---------|
| Rust | `Cargo.toml` | `cargo clean` | `target/` |
| Zig | `build.zig` | - | `zig-cache/`, `zig-out/` |
| Swift | `Package.swift` | `swift package clean` | `.build/` |
| Gradle | `build.gradle(.kts)` | `gradle clean` | `build/`, `.gradle/` |
| Maven | `pom.xml` | `mvn clean` | `target/` |
| Node | `package.json` | - | `node_modules/` |
| Composer | `composer.json` | - | `vendor/` |
| Flutter | `pubspec.yaml` | `flutter clean` | `build/`, `.dart_tool/` |
| Haskell | `stack.yaml` | `stack clean` | `.stack-work/` |
| Elixir | `mix.exs` | `mix clean` | `_build/`, `deps/` |
| Nim | `*.nimble` | - | `nimcache/` |
| Python | `pyproject.toml`, `setup.py` | - | `.venv/`, `dist/`, etc. |

## Cleaning Strategy

diskclean uses a **tool-first** strategy:

1. If the project type has a native clean tool (e.g. `cargo clean`), run it
2. If the tool is not installed or fails, the project is **skipped**

Projects without a native clean tool (Node, Zig, Python, etc.) are
detected and reported, but **not cleaned** by default. This is a deliberate
safety choice — recursive directory removal carries inherent risk
(symlink traversal, permission issues, accidental data loss).

## Experimental: rm Fallback

> **Warning**: This feature performs recursive `removeDir` on detected
> artifact directories. Use at your own risk.

To enable direct directory removal as a fallback for projects without a
native clean tool, build with the `-d:experimentalRm` compile flag:

```bash
# Build with rm fallback enabled
nimble buildExperimental

# Or manually:
nim c -d:release -d:experimentalRm -o:bin/diskclean src/diskclean.nim
```

When `experimentalRm` is enabled:

- Projects without a tool fall back to `removeDir` instead of being skipped
- Symlink targets are **refused** as a safety measure
- `--dry-run` still works and shows what would be removed

When `experimentalRm` is **not** enabled (default):

- Only tool-based cleaning is available
- Projects without a tool are reported as skipped
- No filesystem modifications beyond what the native tool does

### Running Tests with experimentalRm

```bash
nimble testExperimental
```

## Options

```
-h, --help          Show help
-v, --version       Show version
-l, --list          List supported project types
--size              Calculate directory sizes (slower)
--clean             Actually delete (default: scan only)
--dry-run           Show what would be cleaned (with --clean)
--only=TYPE[,TYPE]  Filter by type (comma-separated)
--exclude=PATH      Exclude project path (substring match, repeatable)
```

## License

MIT
