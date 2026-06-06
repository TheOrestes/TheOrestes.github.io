+++
title = "From CUDA Rays to OpenGL Pixels"
date = 2025-12-14T00:00:00+05:30
tags = ["cuda", "rendering", "raytracing", "opengl"]
description = "CUDA & OpenGL Inter-Op"
+++

Ray tracers are fun to write, but they only get truly satisfying once the result shows up on screen without the renderer taking the scenic route through system memory. CUDA and OpenGL both live on the GPU, but they do not automatically share resources, so displaying a CUDA-rendered image often turns into an awkward copy chain unless interop is set up properly.

This commit focuses on the wiring needed to connect an OpenGL texture to CUDA so the renderer can move toward a direct GPU-to-GPU display path. It is one of those changes that looks like plumbing in the diff but quietly removes a lot of friction from the rendering pipeline.

## The Problem

Without interop, the frame usually takes a needlessly dramatic route: CUDA renders, the image gets copied back to the CPU, and then OpenGL uploads it again for display. That approach works, but it is exactly the sort of detour that makes a GPU pipeline feel less like a renderer and more like a parcel delivery service.

The cleaner approach is to let OpenGL own the texture that will be shown on screen and let CUDA access that same resource directly. The whole point is to keep the frame on the GPU and stop paying for unnecessary travel.

## The Texture Becomes the Display Target

The first step is to create a normal OpenGL texture that will hold the rendered image. Nothing exotic here, just a 2D texture that acts as the on-screen destination.

```cpp
glGenTextures(1, &glTexture);
glBindTexture(GL_TEXTURE_2D, glTexture);
glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, width, height, 0, GL_RGBA, GL_FLOAT, nullptr);
```

At this point, the texture is still just an OpenGL object. CUDA does not know about it yet.

## Registering the Texture with CUDA

The key interop step is registering that OpenGL texture so CUDA can work with it. This is the point where the two APIs stop pretending the other one does not exist.

```cpp
cudaGraphicsResource* cudaResource;
cudaGraphicsGLRegisterImage(
    &cudaResource,
    glTexture,
    GL_TEXTURE_2D,
    cudaGraphicsRegisterFlagsWriteDiscard
);
```

The `cudaGraphicsRegisterFlagsWriteDiscard` flag tells CUDA that the texture contents will be replaced rather than preserved. For a renderer that refreshes pixels every frame, that is a very reasonable life choice.

## Mapping and Unmapping the Shared Resource

Once the texture is registered, CUDA still needs the resource to be mapped before it can use it. In this commit, the important part is the synchronization and ownership handoff: CUDA maps the OpenGL resource when it needs access, then unmaps it so OpenGL can safely use it again.

```cpp
cudaGraphicsMapResources(1, &cudaResource);

// CUDA uses the registered image here

cudaGraphicsUnmapResources(1, &cudaResource);
```

That map/unmap pair is the practical heart of the interop flow. It defines when CUDA is allowed to touch the texture and when control returns to OpenGL.

## Drawing It with OpenGL

Once CUDA is done with the shared resource, OpenGL can bind the texture and draw it to a fullscreen quad like any other rendered image. The presentation pass stays simple, which is exactly what it should do.

```cpp
glUseProgram(shader);
glActiveTexture(GL_TEXTURE0);
glBindTexture(GL_TEXTURE_2D, glTexture);
glBindVertexArray(quadVAO);
glDrawArrays(GL_TRIANGLES, 0, 6);
```

That is one of the nice parts of this setup: the display side does not need to know anything about ray traversal, intersections, or shading. It just samples a texture and puts it on screen.

## What we achieved?

This is a small but meaningful architectural step. It replaces a clunky GPU-to-CPU-to-GPU path with a cleaner direction where CUDA and OpenGL share the same display resource more directly.

It also lays the groundwork for a renderer that feels interactive rather than staged. Once the image path is clean, later work on accumulation, camera movement, or more advanced shading has a much better place to land.

That future post is where topics like CUDA image writes, surface access, and the actual per-pixel rendering logic can be unpacked properly. For this commit, the important story is simpler: OpenGL provides the texture, CUDA gets access to it, and the renderer moves one big step closer to drawing straight from GPU work to the screen.

---
[Github Commit URL](https://github.com/TheOrestes/CUDA_Tracer/commit/a2a2f72972498db4c82e262eddd4b1ca80f09101)