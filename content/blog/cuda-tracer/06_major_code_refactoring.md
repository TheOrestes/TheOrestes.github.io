+++
title = "Scene Objects, Materials IDs, and misc. Plumbing!"
date = 2025-12-28T21:29:00+05:30
tags = ["cuda", "rendering", "raytracing", "opengl"]
+++

Up to this point, the renderer had a charming habit of knowing exactly two things in the universe: one small sphere, one giant floor sphere, and a deeply personal belief that both should live directly inside the kernel. This commit starts fixing that.

&nbsp;

Nothing visually dramatic is added here. No shiny metals. No glass. No triumphant dragon mesh crashing through the frame. What *does* happen is more important: the renderer stops hardcoding scene data into `HitWorld` and starts moving toward an actual scene representation with object data and material lookup.

&nbsp;

In other words, the code grows up a little and becomes slightly less of a feral demo.

## The File Layout Gets Reorganized

The first change is structural. `Common.h` moves out of the OpenGL-side folder and becomes:

```cpp
Source/Kernels/RT_Common.cuh
```

Likewise, `Kernels.cu` becomes:

```cpp
Source/Kernels/RT_Kernel.cu
```

That is not just a rename for cosmetics. The new names make it clear that these files belong to the CUDA ray tracing side of the project, not the OpenGL renderer. The Visual Studio project is updated accordingly so it now compiles `RT_Common.cuh` and `RT_Kernel.cu` instead of the older file names.

&nbsp;

This is the kind of change nobody tweets about, but everyone appreciates three commits later.

## Scene Data Leaves the Kernel

Previously, the world definition lived right inside `HitWorld` as a tiny hardcoded array of spheres. Convenient, yes. Scalable, absolutely not. That code is removed and replaced by a more general setup where scene objects are built on the CPU and uploaded to GPU memory. `Main.cpp` now owns:

```cpp
RT::SceneObject* dSceneObject = nullptr;
RT::Material* dMaterial = nullptr;
int gNumObjects = 0;
```

Then `SetupScene()` creates host-side vectors for objects and materials, fills them in, and copies them to device memory using `cudaMalloc` and `cudaMemcpy`.

&nbsp;

So instead of the kernel saying, “trust me, I know what the world is,” the host now explicitly sends the world over. Much healthier relationship.

## The Scene Is Now Object + Material

This commit introduces a proper split between geometry and shading data.

A hit record now stores:

```cpp
float   t;
float3  P;
float3  Normal;
float2  UV;
int     MaterialID;
```

That `MaterialID` is the important promotion. Instead of attaching color directly to the hit itself, the intersection code now reports *which material was hit*. That is a much better model, because geometry and material are not the same thing, even if small demos often pretend otherwise.

&nbsp;

The new shared types in `RT_Common.cuh` also add:

- `ObjectType`, currently `SPHERE` and `MESH`
- `SphereData`
- `TriangleData`
- `SceneObject`
- `MaterialType`, with `LAMBERTIAN`, `METAL`, `PHONG`, and `TRANSPARENT`
- `Material`, carrying `type`, `Albedo`, `Fuzz`, and `IoR`

Not all of those are used yet, but the architecture clearly widens the door.

## Spheres Learn UVs

The old sphere hit code used to compute only position and normal. The new `HitSphere` function still solves the same quadratic; but after a successful hit it now also computes spherical UV coordinates from the normal:

```cpp
const float phi = atan2(rec.Normal.z, rec.Normal.x);
const float theta = asin(rec.Normal.y);

rec.UV.x = 1.0f - (phi + RT_PI) / (2.0f * RT_PI);
rec.UV.y = (theta + RT_PI / 2.0f) / RT_PI;
```

That maps the unit normal on the sphere surface into a \((u,v)\) range of roughly \([0,1]\). No textures are sampled in this commit, but the renderer is now carrying the coordinates needed for that future step.

&nbsp;

So yes, the sphere still looks like a sphere. But under the hood it now knows where it is on itself, which is a surprisingly philosophical improvement.

## `SceneObject` Becomes the Dispatch Point

A new `SceneObject` struct is introduced with a tagged union:

```cpp
struct SceneObject
{
    ObjectType type;
    int MaterialID;

    union
    {
        SphereData sphere;
        TriangleData triangle;
    };

    __device__ bool Hit(const Ray& r, float tMin, float tMax, HitRecord& rec) const;
};
```

In practice, this commit uses a helper called `HitObject`, which switches on `obj.type` and routes to the correct intersection routine:

```cpp
switch (obj.type)
{
case RT::SPHERE:
    hit = HitSphere(obj.sphere, r, t_min, t_max, rec);
    break;
}
```

If the hit succeeds, the object’s `MaterialID` is copied into the hit record. That means `HitWorld` no longer knows anything specific about spheres as *scene content*. It just loops over objects and asks each one to prove its innocence.

## `HitWorld` Becomes an Actual World Query

The new signature is:

```cpp
__device__ bool HitWorld(RT::Ray& r, float t_min, float t_max, RT::HitRecord& rec, RT::SceneObject* objects, int numObjects)
```

and the loop is exactly what you want at this stage:

```cpp
for (int i = 0; i < numObjects; i++)
{
    if (HitObject(objects[i], r, t_min, closest_so_far, temp_rec))
    {
        hit_anything = true;
        closest_so_far = temp_rec.t;
        rec = temp_rec;
    }
}
```

Closest-hit logic stays the same, but now the world is provided externally. The kernel has stopped being a tiny all-knowing god and become a function with arguments. 

## Materials Enter the Bounce Loop

The ray tracing kernel now receives three new inputs:

```cpp
RT::SceneObject* pObjects,
int numObject,
RT::Material* pMaterials
```

and after a hit, it fetches material data explicitly:

```cpp
RT::Material material = pMaterials[rec.MaterialID];
```

Then shading is dispatched by material type:

```cpp
switch (material.type)
{
case RT::LAMBERTIAN:
{
    float3 target = rec.P + rec.Normal + RandomVectorInUnitSphere(&localState);
    r = RT::Ray(rec.P, target - rec.P);
    currentColor = currentColor * material.Albedo;

    break;
}

case RT::METAL:
{
    break;
}

case RT::PHONG:
{
    break;
}

case RT::TRANSPARENT:
{
    break;
}
}
```

Only Lambertian shading is implemented right now. The other material types are placeholders, but they are not fake placeholders — the plumbing is genuinely there now.

That is the key value of this commit. It does not add metal, phong, or transparency behavior yet. It adds the *shape* of a renderer that can support them without turning into spaghetti with a CUDA license.

## The Scene Setup Moves to the Host

`SetupScene()` now creates two spheres as `SceneObject`s:

- a small sphere at \((0,0,-1)\) with `MaterialID = 0`
- a big ground sphere at \((0,-100.5,-1)\) with `MaterialID = 1`

Then it creates two Lambertian materials:

```cpp
mats.push_back({RT::LAMBERTIAN, {0.8f, 0.8f, 0.0f}, 0.0f }); // small sphere
mats.push_back({RT::LAMBERTIAN,{0.8f, 0.8f, 0.8f}, 0.0f }); // big sphere
```

Mathematically, the renderer has moved from a direct per-object color lookup to a two-step association:

$$
\text{object} \rightarrow \text{MaterialID} \rightarrow \text{material}
$$

That is a very ordinary idea in offline rendering, but it is a big architectural jump compared to “sphere contains color, done.”

## Camera and Kernel Signatures Get Narrower

A few host/device boundaries are also cleaned up.

&nbsp;

`Camera::Init` becomes host-only, which makes sense because camera setup is happening on the CPU. `Camera::GetRay` becomes device-only, which also makes sense because the kernel is where rays are generated.

&nbsp;

The exported kernel launcher now takes the full scene payload:

```cpp
void RunRayTracingKernel(cudaGraphicsResource_t cuda_graphics_resource, int cuWidth, int cuHeight, RT::Camera camera, float4* pAccumBuffer, int frameCount, RT::SceneObject* pObjects, int numObjects, RT::Material* pMaterials);
```

That signature is longer, yes. But it is honest now.

## What This Commit Actually Achieves

Visually, this commit probably looks very similar to the previous one because Lambertian scattering is still the only active material path.

Architecturally, though, it is a much bigger deal:

- scene definition moves out of the kernel
- intersections return `MaterialID` instead of direct surface color
- sphere hits now compute UVs
- shading is driven by material lookup
- the codebase is reorganized around ray tracing files rather than generic “common” and “kernel” names

This is one of those commits that makes the next five commits possible. Not glamorous, but extremely adult.

## Commit

GitHub commit: [Major code refactoring! · TheOrestes/CUDA_Tracer@c4ab2db](https://github.com/TheOrestes/CUDA_Tracer/commit/c4ab2db929574f06eeb428e5b40030d85e476394)
