+++
title = "OpenGL Step by Step: What This Series Set Out to Do, and What It Became"
date = 2019-10-20T18:03:00+05:30
tags = ["opengl", "rendering"]
description = "An index and retrospective for the OpenGL Step by Step series: the intent behind it, how the renderer actually evolved commit by commit, and links to all twenty-eight posts."
math = false
+++

![OpenGL Step by Step](https://user-images.githubusercontent.com/5098227/154793719-bbe19bbf-d470-47ce-82a6-9a236e1d0416.png)

## What This Series Is All About

This series started from a simple constraint: take a personal C++/OpenGL renderer being built one commit at a time, and turn every meaningful commit into a blog post, in order, with no skipping ahead and no glossing over the parts that didn't work yet. Each post is written straight from the diff between two commits, so the code shown is exactly the code that existed at that point, dead code, commented-out experiments, half-wired scaffolding, and all. The goal was never to explain OpenGL in the abstract, it was to document what actually happens when a renderer grows from nothing into something, one honest step at a time.

## How It Actually Played Out

What began as "put a window on screen" ended, twenty-eight posts later, as a deferred renderer with physically based materials, image-based lighting sampled from a real HDRI photograph, and filtered soft shadows, plus a live ImGui editor to poke at all of it while it runs. Along the way, the series kept circling back on itself in a way that wasn't planned but became one of its most consistent threads: code written in one post and left unused, commented out, or quietly wrong would resurface posts later, finally doing the job it was written for. A camera-post `brightColor` variable waited for the bloom post to mean anything. A directional light's scaffolding sat inert for eight posts before shadow mapping switched it on. A five-slot material struct declared three unused texture slots that took until multitexturing and beyond to fill in. That pattern, write it, bench it, activate it later, ended up being as much the story of this series as any single rendering technique.

&nbsp;

## The Posts, In Order

### Foundations

#### [01. Empty Window and First Quad](/blog/opengl-step-by-step/01_ogl_window_to_spinning_quad/)
A first mesh, compiled shaders, and a quad transformed through the pipeline.
{.text-sm .text-gray-400}

#### [02. Texturing a Quad](/blog/opengl-step-by-step/02_texturing_quad/)
Vertex colors give way to texture coordinates and a sampled 2D image.
{.text-sm .text-gray-400}

#### [03. Building a Cube](/blog/opengl-step-by-step/03_from_quad_to_cube/)
An eight-vertex, thirty-six-index cube, and depth testing finally has a job.
{.text-sm .text-gray-400}

#### [04. Cutting the Camera Loose](/blog/opengl-step-by-step/04_cutting_the_camera_loose/)
A hardcoded `lookAt` becomes WASD-and-mouse free-look.
{.text-sm .text-gray-400}

#### [05. Building a Skybox](/blog/opengl-step-by-step/05_building_a_skybox/)
Cubemaps, a resurrected `TextureManager`, and the `GL_LEQUAL` trick.
{.text-sm .text-gray-400}

### Real Assets and Classic Lighting

#### [06. Loading a Real Mesh](/blog/opengl-step-by-step/06_loading_a_real_mesh/)
Assimp loads an actual FBX file, and the hand-typed cube gets benched.
{.text-sm .text-gray-400}

#### [07. Texturing the Custom Mesh](/blog/opengl-step-by-step/07_texturing_the_custom_mesh/)
A real `Material` struct arrives, and the permanent wireframe goes away.
{.text-sm .text-gray-400}

#### [08. Multi-Texturing](/blog/opengl-step-by-step/08_multitexturing/)
Specular and normal maps load, though the shader still ignores them.
{.text-sm .text-gray-400}

#### [09. Basic Diffuse Lighting](/blog/opengl-step-by-step/09_basic_diffuse_lighting/)
Per-vertex normals, computed three posts ago, finally earn their keep.
{.text-sm .text-gray-400}

#### [10. Basic Specular Lighting](/blog/opengl-step-by-step/10_basic_specular_lighting/)
A Phong highlight arrives, and last post's unused ambient term gets fixed.
{.text-sm .text-gray-400}

#### [11. Basic Environment Reflection](/blog/opengl-step-by-step/11_basic_environment_reflection/)
The mesh finally samples the skybox for a mirror-style reflection.
{.text-sm .text-gray-400}

#### [12. Building a Lighting System](/blog/opengl-step-by-step/12_lighting_system/)
A real multi-light `LightsManager` and point lights, while reflection quietly steps aside.
{.text-sm .text-gray-400}

#### [13. World-Space Normal Mapping](/blog/opengl-step-by-step/13_normal_mapping_world_space/)
Tangents and bitangents build a TBN matrix for a real normal map.
{.text-sm .text-gray-400}

#### [14. Tangent-Space Normal Mapping](/blog/opengl-step-by-step/14_normal_mapping_tangent_space/)
The transform flips: light and view vectors move into tangent space instead.
{.text-sm .text-gray-400}

### Post-Processing and the Deferred Pipeline

#### [15. Framebuffers Arrive](/blog/opengl-step-by-step/15_framebuffers/)
`Application`/`Scene` classes, an offscreen render target, and a `Framebuffer` class that never compiles.
{.text-sm .text-gray-400}

#### [16. HDR](/blog/opengl-step-by-step/16_framebuffers_hdr/)
A floating-point render target lets light exceed 1.0, tamed back down with exposure tone mapping.
{.text-sm .text-gray-400}

#### [17. Bloom Arrives](/blog/opengl-step-by-step/17_bloom/)
Extract, blur, and composite, the setup this series had been quietly carrying since the camera post.
{.text-sm .text-gray-400}

#### [18. Deferred Rendering](/blog/opengl-step-by-step/18_deferred_rendering/)
One lighting pass replaces many, and three posts of HDR/bloom work get left behind in the switch.
{.text-sm .text-gray-400}

#### [19. Deferred Bloom](/blog/opengl-step-by-step/19_deferred_bloom/)
Emission becomes the G-buffer's fourth channel, and bloom works again.
{.text-sm .text-gray-400}

#### [20. Shadow Mapping](/blog/opengl-step-by-step/20_shadow_mapping/)
The directional-light scaffolding from the lighting-system post finally comes alive.
{.text-sm .text-gray-400}

#### [21. Deferred Debug Views](/blog/opengl-step-by-step/21_deferred_debug_views/)
The G-buffer's channels get tiled on screen as debug thumbnails.
{.text-sm .text-gray-400}

### Environment and Tooling

#### [22. HDRI](/blog/opengl-step-by-step/22_hdri_skybox/)
A real photographed sky gets baked into a cubemap once, at startup.
{.text-sm .text-gray-400}

#### [23. Wireframe Overlay](/blog/opengl-step-by-step/23_wireframe_overlay/)
Barycentric coordinates and `fwidth()` finally replace `GL_LINE`.
{.text-sm .text-gray-400}

#### [24. Dear ImGui](/blog/opengl-step-by-step/24_dear_imgui/)
Every scattered console print becomes one panel, and the scene becomes a live, editable list.
{.text-sm .text-gray-400}

### Physically Based Rendering

#### [25. PBR: Cook-Torrance](/blog/opengl-step-by-step/25_pbr_cook_torrance/)
A hand-tuned specular exponent gives way to a real GGX/Smith/Fresnel BRDF.
{.text-sm .text-gray-400}

#### [26. PBR IBL Diffuse](/blog/opengl-step-by-step/26_pbr_ibl_diffuse/)
The baked HDRI sky gets convolved into an irradiance map for ambient diffuse.
{.text-sm .text-gray-400}

#### [27. PBR IBL Specular](/blog/opengl-step-by-step/27_pbr_ibl_specular/)
A prefiltered reflection map and a BRDF lookup table complete image-based lighting.
{.text-sm .text-gray-400}

#### [28. PCF Shadows](/blog/opengl-step-by-step/28_pcf_shadows/)
A hardware comparison sampler and nine depth taps soften a hard shadow edge.
{.text-sm .text-gray-400}

&nbsp;

## Where It Stands

Twenty-eight commits, from a blank GLFW window to a deferred PBR renderer with real image-based lighting and filtered shadows, each one written up the same way: read the diff, describe what's actually there, and call out what's still unfinished rather than pretend it isn't. This page is the map back through all of it, and if the underlying project picks back up, it's the place a twenty-ninth entry would get added.

&nbsp;

The actual source lives at [github.com/TheOrestes/OpenGL_StepByStep](https://github.com/TheOrestes/OpenGL_StepByStep), commit by commit, exactly as described across these twenty-eight posts. It was a genuinely fun project to build and write up, watching a renderer earn its features one honest diff at a time, and this series is the record of that.
