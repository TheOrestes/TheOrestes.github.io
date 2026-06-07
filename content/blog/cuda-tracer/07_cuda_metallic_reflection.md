+++
title = "The Metal Finally Shows Up..."
date = 2026-01-02T15:43:00+05:30
tags = ["cuda", "rendering", "raytracing", "opengl"]
description = "Adding more objects to the scene and teaching metal how to reflect."
math = true
+++

The scene just got bigger, and the renderer finally stopped pretending the world only contains two spheres. This commit adds two more objects, introduces a shiny metal material path, and makes the existing material setup a little more explicit.

&nbsp;

{{< youtube HT5CvJFPaW0 >}}

&nbsp;

## The Scene Grows Up

The host-side scene setup in `SetupScene()` now creates four spheres instead of two: the small sphere, the ground sphere, a left sphere, and a right sphere. The important part is not the extra geometry itself, but that each object gets a `MaterialID` that points into the materials list.

&nbsp;

That lookup relationship is now the real wiring diagram:

$$
\text{object} \rightarrow \text{MaterialID} \rightarrow \text{material}
$$

In code, the new sphere entries are added like this:

```cpp
// Left Sphere
RT::SceneObject leftSphere;
leftSphere.type = RT::SPHERE;
leftSphere.MaterialID = 2;
leftSphere.sphere.center = make_float3(-1.2f, 0, -1.0f);
leftSphere.sphere.radius = 0.5f;

sceneObjects.push_back(leftSphere);

// Right Sphere
RT::SceneObject rightSphere;
rightSphere.type = RT::SPHERE;
rightSphere.MaterialID = 3;
rightSphere.sphere.center = make_float3(1.2f, 0, -1.0f);
rightSphere.sphere.radius = 0.5f;

sceneObjects.push_back(rightSphere);
```

So yes, the scene now has more than one trick up its sleeve. The kernel is no longer looking at a two-sphere universe and calling it ambition.

## Materials Get a New Act

The materials list grows too. The original Lambertian materials stay in place, but now there are two metal materials:

```cpp
mats.push_back({RT::LAMBERTIAN, {0.8f, 0.8f, 0.0f}, 0.0f, 0.0f });// small sphere
mats.push_back({RT::LAMBERTIAN,{0.8f, 0.8f, 0.8f}, 0.0f, 0.0f });// ground sphere
mats.push_back({ RT::METAL,{0.2f, 0.2f, 0.7f}, 0.0f, 0.0f });// left shiny sphere
mats.push_back({ RT::METAL,{0.7f, 0.2f, 0.2f}, 0.3f, 0.0f });// right fuzzy sphere
```

The left sphere is a shiny blue metal, and the right sphere is a fuzzier red metal. The `Fuzz` value controls how rough the reflection is, so the right one scatters a little more after reflecting.

&nbsp;

That means the material model now behaves like:

$$
\text{perfect reflection} + \text{random perturbation}
$$

with the perturbation scaled by `Fuzz`.

## Reflection Finally Lands

The kernel adds a new helper:

```cpp
__device__ inline float3 Reflect(const float3& V, const float3& N)
{
    return V - 2.0f * dot(V, N) * N;
}
```

That is the standard reflection formula. If \(V\) is the incoming direction and \(N\) is the surface normal, then the reflected ray is:

$$
R = V - 2(V \cdot N)N
$$

Nothing fancy, just the kind of linear algebra that quietly runs the whole show.

## Metal Now Does Something

Inside the material switch, the `METAL` case finally does real work:

```cpp
case RT::METAL:
{
    float3 reflected = Reflect(unit_vector(r.Direction), rec.Normal);

    // Add Fuzziness (roughness) to the reflection
    float3 scattered = reflected + material.Fuzz * RandomVectorInUnitSphere(&localState);

    // only scatter if reflection isn't absorbed
    if(dot(scattered, rec.Normal) > 0.0f)
    {
        r = RT::Ray(rec.P, scattered);
        currentColor = currentColor * material.Albedo;
    }

    break;
}
```

So the ray first gets reflected about the normal, then a random vector from the unit sphere is added to introduce roughness. If the scattered direction still points above the surface, the bounce is accepted. That check matters because a metal surface is not supposed to reflect light into the inside of the object. That would be a very committed typo.

## What the Fuzz Does

The new metal materials differ mostly by `Fuzz`:

- `0.0f` means a clean mirror-like reflection.
- `0.3f` means a rougher reflection.

Conceptually, the reflected direction becomes:

$$
R' = R + f \cdot \xi
$$

where \(R\) is the perfect reflection, \(f\) is the fuzz factor, and \(\xi\) is a random vector inside the unit sphere.

&nbsp;

So the left sphere should look cleaner, while the right sphere should look a bit more diffuse. The renderer is finally getting out of the “everything is a Lambertian potato” phase.

## What Did Not Change

This commit does **not** change the overall rendering architecture. The scene is still built on the CPU and passed to the kernel. The object/material separation is still the same. The Lambertian path still exists and still works as before. What changed is that the renderer now has a second active material model, and the scene uses it with two extra spheres.

## Commit

GitHub commit: [The Metal Finally Shows Up](https://github.com/TheOrestes/CUDA_Tracer/commit/c4ab2db929574f06eeb428e5b40030d85e476394)