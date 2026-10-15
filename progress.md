# Progress — Kivy graphics drawing API

Checked = draws correctly through the shared C api into KivyRepresentable's shader node.
Verified headless by `Tests/kivy/test_render_nui.py` (real Kivy apps on the
Vulkan GL, framebuffer read back and checked).

This is a **verification** list, not a rewrite list. The instruction classes
below stay as Kivy wrote them; only the GPU layer underneath is replaced. An
item gets checked when it renders right through that layer, untouched. If an
item seems to need changes in its own `.pyx`, that's a sign the GPU layer is
missing something. Fix it there, and write it down in `kivy-notes.md`.

## Canvas structure (`instructions.pyx`)
- [ ] Instruction
- [ ] InstructionGroup
- [ ] CanvasBase
- [x] Canvas (`before` / `after`)
- [ ] RenderContext
- [ ] Callback

## Context instructions (`context_instructions.pyx`)
- [x] Color (rgba / hsv)
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
- [x] Rectangle
- [ ] RoundedRectangle
- [x] BorderImage
- [x] Ellipse (incl. `angle_start` / `angle_end` / `segments`)
- [ ] Bezier
- [ ] Point
- [x] Mesh
  - [ ] mode `points`
  - [ ] mode `line_strip`
  - [ ] mode `line_loop`
  - [ ] mode `lines`
  - [ ] mode `triangles`
  - [ ] mode `triangle_strip`
  - [x] mode `triangle_fan`
- [ ] StripMesh

## Line (`vertex_instructions_line.pxi`)
- [x] Line `points`
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
- [x] StencilPush
- [x] StencilUse
- [x] StencilUnUse
- [x] StencilPop
- [ ] ScissorPush
- [ ] ScissorPop

## Clear (`gl_instructions.pyx`)
- [x] ClearColor
- [x] ClearBuffers

## Resources / render targets
- [ ] Texture (create / blit_buffer / blit_data / mipmap / wrap / filters)
- [ ] TextureRegion (`get_region`)
- [x] Fbo (offscreen render, `fbo.texture`)
- [ ] Shader (default vs/fs, custom shader source → SPIR-V)
- [ ] VertexFormat (custom attributes)
- [x] VBO / VertexBatch (vertex + index upload)
