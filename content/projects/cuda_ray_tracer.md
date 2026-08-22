+++
title= "CUDA Ray Tracer"
date= 2026-06-01T11:00:00+05:30
tags= ["cuda", "c++", "raytracing", "opengl"]
summary= "A GPU ray tracer written while learning CUDA, rendering straight into an OpenGL texture through buffer interop."
repo= "https://github.com/TheOrestes/CUDA_Tracer"
series= "/blog/cuda-tracer"
cover= "images/covers/cuda_render.jpg"

[[gallery]]
  src= "images/covers/cuda_bvh.jpg"
  alt= "The same scene with BVH wireframe debug drawing enabled, orange bounding boxes wrapping each sphere"

[[gallery]]
  src= "images/covers/cuda_scene.jpg"
  alt= "The three-sphere scene fully converged at 50 samples per pixel"
+++

A ray tracer written as a way to actually learn CUDA rather than read about it. Rays are traced in a CUDA kernel and the result lands in an OpenGL texture through buffer interop, so the window shows a live image instead of a written-out file.

&nbsp;

The early posts are mostly interop plumbing — getting CUDA and OpenGL to agree on who owns a buffer. Once that's working, the renderer stops being a screensaver and starts being a ray tracer.

&nbsp;

## What it does

- CUDA/OpenGL buffer interop with a progressively accumulated image
- Spheres with diffuse, metal, and dielectric materials
- An FPS camera you can fly through the scene
- A BVH with debug visualisation, plus a bounce heatmap for seeing cost per pixel
- Dear ImGui integration for live tweaking and fixed-SPP render timing
