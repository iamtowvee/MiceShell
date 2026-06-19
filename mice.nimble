
version = "0.1.0"
author = "iamtowvee"
description = "MiceShell"
license = "Apache-2.0"
srcDir = "src"
binDir = "bin"
bin = @["mice"]

requires "nim >= 2.0.0"
requires "winim"

task build, "Build MiceShell":
  exec "nim c -d:release src/mice.nim"