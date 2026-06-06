+++
title = "The Ray Tracer Stops Being a Screensaver"
date = 2025-12-25T00:00:00+05:30
tags = ["cuda", "rendering", "raytracing", "opengl"]
description = "The beginning of tracing actual rays..."
+++

The previous post proved that CUDA could write animated pixels into the shared OpenGL texture. Fun, useful, and a very respectable GPU-powered lava lamp. This post takes the next real step toward ray tracing: instead of generating time-based color waves, the CUDA kernel now generates rays from a camera and shades the background based on ray direction.

The renderer is no longer just filling the framebuffer with procedural color motion; it is starting to behave like a ray tracer, even if the only thing it can hit right now is the sky.

![CUDA Miss Color Sky Gradient](/images/blog/sky_miss_color.png)

## Some minor book keeping (Common.h)

Introduced a common header that becomes the shared language between the OpenGL side and the CUDA side. It contains a bunch of small math helpers for `float3`, including vector addition, subtraction, scaling, division, dot product, cross product, and normalization. None of that is glamorous, but this is exactly the sort of code a ray tracer needs before it can do anything interesting without immediately tripping over vector math.

## Rays Become Real Types

Inside `Common.h`, we introduce `RT::Ray` struct:

```cpp
struct Ray
{
    float3 Origin;
    float3 Direction;

    __host__ __device__ Ray() {}

    __host__ __device__ Ray(const float3& o, const float3& d)
    : Origin(o), Direction(d) { }

    __host__ __device__ float3 GetAt(float t) const { return Origin + Direction * t; }
};
```

This is the first moment where the renderer starts speaking in ray-tracing nouns instead of just “kernel writes colors.” A ray now exists as an origin and a direction, which is the minimum required equipment for launching pixels into a 3D scene and asking uncomfortable questions about what they hit.

## A Camera Enters the Scene

The same header also introduces `RT::Camera`, which stores:

- `Origin`
- `Lower_Left_Corner`
- `Horizontal`
- `Vertical`

That camera constructor builds a viewport from `lookfrom`, `lookat`, `vup`, vertical field of view, and aspect ratio. In other words, the renderer now has a proper camera model instead of just treating each pixel like a coordinate in procedural color space.

The key method is:

```cpp
__host__ __device__ Ray GetRay(float u, float v)
{
    return Ray(Origin, Lower_Left_Corner + Horizontal * u + Vertical * v - Origin);
}
```

That is the line where a screen-space UV turns into an actual viewing ray.

## The Main Loop Stops Passing Time

In `Main.cpp`, the CUDA entry point changes from this:

```cpp
RunRayTracingKernel(fbCudaResource, width, height, time);
```

to this:

```cpp
RunRayTracingKernel(fbCudaResource, width, height, mainCamera);
```

That one signature change tells the whole story. The kernel no longer needs `time` to animate colors; it now needs a camera so it can decide which ray belongs to each pixel.

The scene setup added in `Main.cpp` is also very explicit:

```cpp
float3 lookfrom = make_float3(0, 0, 2);
float3 lookat = make_float3(0, 0, -1);
float3 vup = make_float3(0, 1, 0);

RT::Camera mainCamera(lookfrom, lookat, vup, 45.0f, static_cast<float>(width) / static_cast<float>(height));
```

That gives the renderer a fixed camera positioned at `(0, 0, 2)`, looking toward `(0, 0, -1)`, with a 45-degree field of view.

## The Kernel Stops Faking Motion

The old kernel generated RGB values with `sinf` and `cosf`, which was a nice proof that CUDA-to-texture output worked. That logic is now gone.

The new kernel starts like this:

```cpp
__global__ void RayTracer(cudaSurfaceObject_t surface, int width, int height, RT::Camera cam)
```

and after computing the pixel coordinates, it converts them to normalized screen-space values:

```cpp
float u = float(x) / float(width - 1);
float v = float(y) / float(height - 1);
```

That is a subtle but important change. The pixel is no longer treated as a place to invent color from; it is treated as a place from which to launch a ray.

## Each Pixel Now Gets a Ray

The next line is the real transition point:

```cpp
RT::Ray r = cam.GetRay(u, v);
```

That means every CUDA thread now does something ray-tracing shaped. It asks the camera for the ray corresponding to its pixel, and then uses that ray to decide the pixel color.

At this stage, there is still no scene intersection logic. The ray does not test against spheres, triangles, or anything else that might object to being intersected. But the control flow is now structurally correct for a ray tracer: generate ray first, shade second.

## The Background Becomes a Sky Gradient

The new shading logic lives in `GetMissColor`:

```cpp
__device__ float3 GetMissColor(const RT::Ray& r)
{
    float3 unit_direction = unit_vector(r.Direction);
    float t = 0.5f * (unit_direction.y + 1.0f);

    float3 white = make_float3(1.0f, 1.0f, 1.0f);
    float3 blue = make_float3(0.5f, 0.7f, 1.0f);

    return white * (1.0f - t) + blue * t;
}
```

This is the classic “miss shader” move: if the ray hits nothing, color the background based on its vertical direction. Rays pointing upward get pushed toward blue, and rays lower in the image stay closer to white.

That makes the framebuffer look like a sky gradient rather than a procedural animation. It is simple, but it immediately feels more like a renderer looking into a world instead of a screensaver! 

## Writing the Final Pixel Is Still the Same Last Step

Once the miss color is computed, the kernel packs it into a `float4` and writes it to the surface:

```cpp
float4 finalColor = make_float4(pixelColor.x, pixelColor.y, pixelColor.z, 1.0f);
surf2Dwrite(finalColor, surface, x * sizeof(float4), y);
```

That part has not changed conceptually. The interop path is stable enough now that the code can focus on improving what gets written, not constantly re-litigating how to write it.

## What we achieved? 

This is the commit where the project starts to deserve the words “ray tracer” a little more seriously. It adds the core types and math needed to generate camera rays, replaces time-based color animation with ray-based shading, and introduces a proper miss color for rays that do not hit geometry.

There is still no scene intersection, no materials, and no lighting model beyond “the sky is blue-ish if you look upward,” but the pipeline is now pointed in the right direction. The renderer is no longer faking interesting pixels; it is beginning to compute them from a camera model, which is a much more promising personality trait.

This commit does not add hittable objects, bounce logic, or full scene rendering. No spheres are harmed yet! 
But architecturally it is the kind of step that turns “CUDA image demo” into a humble “early ray tracer.” 😊

---
[GitHub commit URL](https://github.com/TheOrestes/CUDA_Tracer/commit/df3466468944fb4695b20999d1a04108995de983)

