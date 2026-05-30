+++
title = "From Interop Plumbing to Actual Pixels"
date = 2024-09-28T16:30:22Z
tags = ["cuda", "rendering", "raytracing", "opengl"]
description = "CUDA to OpenGL FBO rendering"
+++

The previous post was all about getting CUDA and OpenGL to share nicely. Useful, necessary, slightly plumbing-shaped work. This commit is where things become visually more fun: CUDA now actually writes animated color data into the shared texture, and OpenGL displays it through a framebuffer blit.

In other words, the texture is no longer just a properly registered GPU resource with good intentions. It now contains pixels produced by a CUDA kernel, updated every frame, and pushed to the window in a way that is simple enough to understand at a glance.

## CUDA-written framebuffer texture in motion: 

{{< youtube iS5jBNsLVsk >}}

# The Main Loop Stops Clearing and Starts Rendering

Apart from minor code refactoring, The biggest change in `Main.cpp` is inside the render loop. Instead of clearing the screen with a chosen solid color, the program now grabs the current time and calls a CUDA entry point:

```cpp
const float time = static_cast<float>(glfwGetTime());

RunRayTracingKernel(fbCudaResource, width, height, time);
```

That one call is the handoff from the OpenGL side to the CUDA side. The shared texture, the frame dimensions, and the current time all get passed in so the CUDA code can update the image each frame.

## A Framebuffer Gets Added to the Display Path

We also create the framebuffer object(FBO) and attach the CUDA-written texture to it:

```cpp
GLuint fbo;
glGenFramebuffers(1, &fbo);
glBindFramebuffer(GL_READ_FRAMEBUFFER, fbo);

glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, fbTexture, 0);
```

That setup changes how the final image reaches the screen. Instead of drawing a textured quad, the code now treats the CUDA texture as the read source and blits it directly into the default framebuffer.

## The Display Path Becomes a Blit

Once the CUDA kernel has updated the texture, OpenGL presents it like this:

```cpp
glBindFramebuffer(GL_READ_FRAMEBUFFER, fbo);
glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);

glBlitFramebuffer(
    0, 0, width, height,
    0, 0, width, height,
    GL_COLOR_BUFFER_BIT,
    GL_NEAREST
);
```

This is a nice simplification. OpenGL is no longer asked to draw geometry just to show the image; it simply copies the color buffer from the framebuffer-backed texture into the window. It is a very direct “here are the pixels, please show them” kind of move.

## The CUDA Side Becomes Real

```cpp
__global__ void RayTracer(cudaSurfaceObject_t surface, int width, int height, float time)
```

Inside that kernel, each thread computes its `x` and `y` pixel position, converts those coordinates into normalized `u` and `v` values, and then generates animated RGB values using `sinf` and `cosf`.

```cpp
float u = x / (float)width;
float v = y / (float)height;

float r = 0.5f + 0.5f * sinf(time + u * 6.28f);
float g = 0.5f + 0.5f * cosf(time + v * 6.28f);
float b = 0.5f + 0.5f * sinf(time + (u + v) * 6.28f);
```

This is not ray tracing yet in the scene-intersection sense, despite the kernel name. What it is doing is generating an animated procedural color pattern across the framebuffer. Think of it as a GPU-written test image with enough motion to prove that the whole CUDA-to-texture-to-screen path is alive.

## Writing into the Shared Texture

Once the color is computed, the kernel writes it into the surface object:

```cpp
surf2Dwrite(make_float4(r, g, b, 1.0f), surface, x * sizeof(float4), y);
```

That line is the real moment of payoff. CUDA is now writing actual pixel data into the shared OpenGL texture, one thread per pixel, using a surface object created from the mapped graphics resource.

The code even leaves a warning comment right above it:

```cpp
// x * sizeof(float4) is CRITICAL for surf2Dwrite
```

That comment earns its capital letters. `surf2Dwrite` expects a byte offset in the horizontal direction, not a plain pixel index, so this is one of those details that looks tiny and ruins everything when wrong.

## The Interop Path Gets Wrapped in One Function

```cpp
extern "C" void RunRayTracingKernel(cudaGraphicsResource_t res, int cuWidth, int cuHeight, float t);
```

That function wraps the whole CUDA side of the interop cycle:

- Map the OpenGL resource.
- Get the mapped CUDA array.
- Create a surface object from that array.
- Launch the kernel.
- Destroy the surface object.
- Unmap the resource so OpenGL can use it again.

That is a nice step up from scattering interop code across the rendering loop. `Main.cpp` can stay focused on orchestration, while the CUDA file owns the details of texture access and kernel dispatch.

## What we achieved?

This is the first post in the series that visibly proves the pipeline works end to end. The earlier interop setup made sharing possible; this one actually uses that shared path to generate animated image data on the CUDA side and present it with OpenGL.

It also establishes a structure that future posts can build on cleanly. There is now a dedicated render entry point, a dedicated CUDA kernel file, a framebuffer-backed display path, and a time-driven image update loop. Right now the output is a procedural animated gradient, which is exactly the right kind of stepping stone before the code graduates into actual scene rendering.

Hopefully in our next post, we will do some ray tracing! :sunglasses:

---
[GitHub Commit URL](https://github.com/TheOrestes/CUDA_Tracer/commit/6304b77bf0d1e696f96200c6a76c6baf8b43879f)


