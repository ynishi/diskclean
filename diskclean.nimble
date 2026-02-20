# Package

version       = "0.3.1"
author        = "Yutaka Nishimura"
description   = "Declarative disk cleanup for development projects"
license       = "MIT"
srcDir        = "src"
bin           = @["diskclean"]
binDir        = "bin"


# Dependencies

requires "nim >= 2.2.6"

task test, "Run tests":
  exec "nim c -r --path:src tests/test_diskclean.nim"

task testExperimental, "Run tests with experimentalRm enabled":
  exec "nim c -r -d:experimentalRm --path:src tests/test_diskclean.nim"

task build, "Build binary (tool-clean only)":
  exec "nim c -d:release --path:src -o:bin/diskclean src/diskclean.nim"

task buildExperimental, "Build binary with rm fallback enabled":
  exec "nim c -d:release -d:experimentalRm --path:src -o:bin/diskclean src/diskclean.nim"
