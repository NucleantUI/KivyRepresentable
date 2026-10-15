# Progress — Kivy graphics drawing API

Checked = draws correctly through the shared C api into KivyRepresentable's shader node.
Verified headless by `Tests/kivy/test_render_nui.py` (real Kivy apps on the
Vulkan GL, framebuffer read back and checked; one test per group below).
Internal ones are checked through what uses them: StripMesh through Svg,
AntiAliasingLine through the Smooth shapes.

This is a **verification** list, not a rewrite list. The instruction classes
below stay as Kivy wrote them; only the GPU layer underneath is replaced. An
item gets checked when it renders right through that layer, untouched. If an
item seems to need changes in its own `.pyx`, that's a sign the GPU layer is
missing something. Fix it there, and write it down in `kivy-notes.md`.

## Canvas structure (`instructions.pyx`)
- [x] Instruction
- [x] InstructionGroup
- [x] CanvasBase
- [x] Canvas (`before` / `after`)
- [x] RenderContext
- [x] Callback

## Context instructions (`context_instructions.pyx`)
- [x] Color (rgba / hsv)
- [x] BindTexture
- [x] PushState
- [x] ChangeState
- [x] PopState

## Transformations (`context_instructions.pyx`)
- [x] PushMatrix
- [x] PopMatrix
- [x] LoadIdentity
- [x] ApplyContextMatrix
- [x] UpdateNormalMatrix
- [x] MatrixInstruction
- [x] Transform
- [x] Translate
- [x] Rotate
- [x] Scale

## Vertex instructions (`vertex_instructions.pyx`)
- [x] Triangle
- [x] Quad
- [x] Rectangle
- [x] RoundedRectangle
- [x] BorderImage
- [x] Ellipse (incl. `angle_start` / `angle_end` / `segments`) — drawn by a distance shader, not a fan
- [x] Bezier
- [x] Point
- [x] Mesh
  - [x] mode `points`
  - [x] mode `line_strip`
  - [x] mode `line_loop`
  - [x] mode `lines`
  - [x] mode `triangles`
  - [x] mode `triangle_strip`
  - [x] mode `triangle_fan`
- [x] StripMesh

## Line (`vertex_instructions_line.pxi`)
- [x] Line `points`
- [x] Line `width` (> 1)
- [x] Line `close`
- [x] Line `cap` (none / square / round)
- [x] Line `joint` (none / round / bevel / miter)
- [x] Line `dash_length` / `dash_offset`
- [x] Line `dashes`
- [x] Line `circle` — drawn by a ring shader, not a polyline
- [x] Line `ellipse` — drawn by a ring shader, not a polyline
- [x] Line `rectangle`
- [x] Line `rounded_rectangle`
- [x] Line `bezier`
- [x] SmoothLine
- [x] AntiAliasingLine

## Smooth (anti-aliased) variants (`vertex_instructions.pyx`)
- [x] SmoothTriangle
- [x] SmoothQuad
- [x] SmoothRectangle
- [x] SmoothRoundedRectangle
- [x] SmoothEllipse

## Effects
- [x] BoxShadow (`boxshadow.pyx`)
- [x] Svg (`svg.pyx`, incl. LinearGradient / RadialGradient)
- [x] Tesselator (`tesselator.pyx`, fill polygons → Mesh)

## Clipping
- [x] StencilPush
- [x] StencilUse
- [x] StencilUnUse
- [x] StencilPop
- [x] ScissorPush
- [x] ScissorPop

## Clear (`gl_instructions.pyx`)
- [x] ClearColor
- [x] ClearBuffers

## Resources / render targets
- [x] Texture
  - [x] create / blit_buffer (label text)
  - [x] blit_data
  - [x] mipmap
  - [x] wrap / filters
- [x] TextureRegion (`get_region`)
- [x] Fbo (offscreen render, `fbo.texture`)
- [x] Shader (default vs/fs, custom shader source → SPIR-V)
- [x] VertexFormat (custom attributes)
- [x] VBO / VertexBatch (vertex + index upload)
