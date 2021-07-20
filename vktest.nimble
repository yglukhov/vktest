# Package

version       = "0.1.0"
author        = "Yuriy Glukhov"
description   = "A new awesome nimble package"
license       = "MIT"


# Dependencies

requires "nim >= 1.4.4"
requires "nimgl"
requires "https://github.com/nimious/vulkan"

proc compileShader(name: string) =
  exec "glslc " & name & " -o " & name & ".spv"

task shaders, "Compile shaders":
  compileShader("shader.vert")
  compileShader("shader.frag")
