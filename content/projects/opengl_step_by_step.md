+++
title= "OpenGL Step by Step"
date= 2026-02-17T09:00:00+05:30
tags= ["opengl", "c++", "pbr", "graphics"]
summary= "A rasterizer grown one commit at a time — from an empty window and a spinning quad all the way to physically based rendering with image-based lighting."
repo= "https://github.com/TheOrestes/OpenGL_StepByStep"
series= "/blog/opengl-step-by-step"
cover= "images/covers/opengl_pbr_shadow.jpg"

[[gallery]]
  src= "images/covers/opengl_pbr_front.jpg"
  alt= "The PBR robot mid-rotation, its PCF-softened shadow falling across the tiled plane"

[[gallery]]
  src= "images/covers/opengl_pbr_angle.jpg"
  alt= "The same scene from a lower angle, showing the HDRI courtyard reflected in the metal"
+++

The longest-running of the three projects: a renderer built one feature at a time, starting with an empty window and a single spinning quad, and ending with a physically based pipeline lit by a real photographed sky.

&nbsp;

Every step is its own post, and every post is its own commit. Nothing is skipped over — including the passes that got built, used for a while, and then quietly abandoned when something better replaced them.

&nbsp;

## Roughly where it goes

1. **Foundations** — window, quad, textures, cube, free-flying camera, skybox
2. **Meshes and materials** — Assimp loading, a material system, multi-texturing
3. **Lighting** — diffuse, specular, environment reflection, a real point-light system
4. **Normal mapping** — world space first, then tangent space
5. **Framebuffers** — post-processing, HDR and tone mapping, bloom
6. **Deferred rendering** — a G-buffer, deferred bloom, shadow mapping, debug views
7. **PBR** — Cook-Torrance, IBL diffuse and specular, and PCF-softened shadows

&nbsp;

Dear ImGui arrives late, at post 24, which means the first twenty-three entries debug everything with console prints. That ordering was not intentional, but it is honest.
