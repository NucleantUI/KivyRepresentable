# Progress — Kivy graphics drawing API

Checked = draws correctly through the shared C api into KivyRepresentable's shader node.

This is a **verification** list, not a rewrite list. The instruction classes
below stay as Kivy wrote them; only the GPU layer underneath is replaced. An
item gets checked when it renders right through that layer, untouched. If an
item seems to need changes in its own `.pyx`, that's a sign the GPU layer is
missing something. Fix it there, and write it down in `kivy-notes.md`.

## Canvas structure (`instructions.pyx`)
- [ ] Instruction
- [ ] InstructionGroup
- [ ] CanvasBase
- [ ] Canvas (`before` / `after`)
- [ ] RenderContext
- [ ] Callback

## Context instructions (`context_instructions.pyx`)
- [ ] Color (rgba / hsv)
- [ ] BindTexture
- [ ] PushState
- [ ] ChangeState
- [ ] PopState

## Transformations (`context_instructions.pyx`)
- [ ] PushMatrix
- [ ] PopMatrix
- [ ] LoadIdentity
- [ ] ApplyContextMatrix
- [ ] UpdateNormalMatrix
- [ ] MatrixInstruction
- [ ] Transform
- [ ] Translate
- [ ] Rotate
- [ ] Scale

## Vertex instructions (`vertex_instructions.pyx`)
- [ ] Triangle
- [ ] Quad
- [ ] Rectangle
- [ ] RoundedRectangle
- [ ] BorderImage
- [ ] Ellipse (incl. `angle_start` / `angle_end` / `segments`)
- [ ] Bezier
- [ ] Point
- [ ] Mesh
  - [ ] mode `points`
  - [ ] mode `line_strip`
  - [ ] mode `line_loop`
  - [ ] mode `lines`
  - [ ] mode `triangles`
  - [ ] mode `triangle_strip`
  - [ ] mode `triangle_fan`
- [ ] StripMesh

## Line (`vertex_instructions_line.pxi`)
- [ ] Line `points`
- [ ] Line `width` (> 1)
- [ ] Line `close`
- [ ] Line `cap` (none / square / round)
- [ ] Line `joint` (none / round / bevel / miter)
- [ ] Line `dash_length` / `dash_offset`
- [ ] Line `dashes`
- [ ] Line `circle`
- [ ] Line `ellipse`
- [ ] Line `rectangle`
- [ ] Line `rounded_rectangle`
- [ ] Line `bezier`
- [ ] SmoothLine
- [ ] AntiAliasingLine

## Smooth (anti-aliased) variants (`vertex_instructions.pyx`)
- [ ] SmoothTriangle
- [ ] SmoothQuad
- [ ] SmoothRectangle
- [ ] SmoothRoundedRectangle
- [ ] SmoothEllipse

## Effects
- [ ] BoxShadow (`boxshadow.pyx`)
- [ ] Svg (`svg.pyx`, incl. LinearGradient / RadialGradient)
- [ ] Tesselator (`tesselator.pyx`, fill polygons → Mesh)

## Clipping
- [ ] StencilPush
- [ ] StencilUse
- [ ] StencilUnUse
- [ ] StencilPop
- [ ] ScissorPush
- [ ] ScissorPop

## Clear (`gl_instructions.pyx`)
- [ ] ClearColor
- [ ] ClearBuffers

## Resources / render targets
- [ ] Texture (create / blit_buffer / blit_data / mipmap / wrap / filters)
- [ ] TextureRegion (`get_region`)
- [ ] Fbo (offscreen render, `fbo.texture`)
- [ ] Shader (default vs/fs, custom shader source → SPIR-V)
- [ ] VertexFormat (custom attributes)
- [ ] VBO / VertexBatch (vertex + index upload)
