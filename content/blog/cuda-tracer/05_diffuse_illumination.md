+++
title = "Diffuse Bounces and Albedo Finally Doing Its Job"
date = 2025-12-27T20:28:00+05:30
tags = ["cuda", "rendering", "raytracing", "opengl"]
+++

Last time the renderer learned how to hit things. In this commit, it learns what to do *after* hitting them, which is where ray tracing stops being a glorified visibility test and starts pretending to understand light. 

&nbsp;

{{< youtube x1BJrxPgtvo >}}

&nbsp;

There are three real changes here:

1. The sphere intersection math is fixed.
2. Surface color is promoted into the hit record as albedo.
3. Rays now bounce through the scene instead of stopping at the first hit.

That sounds suspiciously like progress.

## The Quadratic Was Off by a Factor of Two

The ray-sphere intersection code already solved the quadratic, but the actual root evaluation was slightly wrong. The code was doing:

```cpp
float temp = (-b - sqrtf(discriminant)) / a;
```

and later:

```cpp
temp = (-b + sqrtf(discriminant)) / a;
```

But the quadratic formula is:

$$t = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$$

That missing 2 in the denominator is not a “close enough for graphics” kind of bug. It changes the hit distance outright. This commit fixes both roots:

```cpp
float temp = (-b - sqrtf(discriminant)) / (2.0f * a);
```

```cpp
temp = (-b + sqrtf(discriminant)) / (2.0f * a);
```

So yes, the spheres were being intersected with confidence, just not mathematical correctness. Very GPU of us.

## Hit Records Now Carry Albedo

`HitRecord` gets a new field:

```cpp
float3 Albedo;
```

That matters because once rays start bouncing, the hit point needs to carry not just *where* it was hit and *what* the normal is, but also the surface reflectance used to attenuate light along the path. So when a sphere is hit, the record now stores the sphere color directly:

```cpp
rec.Albedo = color;
```

This happens in both valid root branches, which means every successful intersection now returns geometry plus material tint. Tiny change in code, very large promotion in responsibility.

## `HitWorld` Stops Pretending to Shade

Previously, `HitWorld` returned both the hit result and an output color. That made sense for flat shading, where the moment you hit a thing, you immediately decide the pixel color and go home. That is no longer the job. The function signature changes from:

```cpp
__device__ bool HitWorld(const RT::Ray& r, float t_min, float t_max, RT::HitRecord& rec, float3& outColor)
```

to:

```cpp
__device__ bool HitWorld(const RT::Ray& r, float t_min, float t_max, RT::HitRecord& rec)
```

and the old flat-color assignment disappears entirely. Good. A world-intersection function should answer “what did I hit?”, not “what is art?”. The actual new piece is this:

```cpp
__device__ float3 RandomVectorInUnitSphere(curandState* state)
{
float3 p;

do 
{
p = 2.0f * make_float3(RandomFloat(state), RandomFloat(state), RandomFloat(state)) - make_float3(1, 1, 1);
}
while (dot(p, p) >= 1.0f);

return p;
}
```

This uses rejection sampling to generate a random point inside the unit sphere. In other words, keep throwing darts into the cube \([-1,1]^3\) until one lands inside the sphere:

$$x^2 + y^2 + z^2 < 1$$

Nothing fancy, but exactly what the next step needs.

## The Renderer Gets Its First Bounce Loop

This is the real upgrade. Instead of tracing one camera ray, checking one hit, and assigning one color, the kernel now iterates up to 50 times:

```cpp
for (int depth = 0 ; depth < 50 ; ++depth)
```

That is not recursive path tracing yet, but it is absolutely the same idea wearing iterative CUDA-friendly clothing. The ray starts from the camera as before:

```cpp
RT::Ray r = cam.GetRay(u, v);
float3 currentColor = make_float3(1, 1, 1);
float3 pixelColor = make_float3(0, 0, 0);
```

The important part is `currentColor`. Think of it as the throughput carried by the ray. It starts at white, meaning “no energy lost yet.” Every time the ray hits a diffuse surface, that throughput gets multiplied by the surface albedo:

```cpp
currentColor = currentColor * rec.Albedo;
```

So after one bounce, the ray is tinted by the first surface. After two bounces, it is tinted again. Light is now paying rent at every wall it touches.

## Diffuse Scattering Enters the Chat

When a ray hits geometry, it no longer stops. Instead, a new target is built:

```cpp
float3 target = rec.P + rec.Normal + RandomVectorInUnitSphere(&localState);
```

and the scattered ray becomes:

```cpp
r = RT::Ray(rec.P, target - rec.P);
```

This is the classic “normal plus random vector” diffuse scatter approximation. It pushes the new ray into the hemisphere around the surface normal, giving a rough Lambertian-style bounce.

&nbsp;

In spirit, it is aiming for diffuse reflection where outgoing light is distributed according to the surface orientation. Not a perfect BRDF sermon yet, but definitely no longer flat-color kindergarten.

## The Sky Becomes the Light Source

If a bounce misses the scene, the renderer samples the sky and stops:

```cpp
pixelColor = currentColor * GetMissColor(r, localState);
break;
```

That line is doing more work than it looks like.

The miss color is no longer just a background color. In this bounce-based version, the sky effectively acts as the light source at the end of the path. The final radiance is the accumulated throughput multiplied by the sky color encountered by the escaped ray.

So the pixel now represents:

$$
L \approx T \cdot L_{\text{sky}}
$$

where \(T\) is the product of all albedo terms collected along the bounce chain.

That is a very respectable first step into path tracing territory.

## Scene Color Changes

The scene still has the same two spheres, but their colors change:

```cpp
{ make_float3(0.0f, 0.0f, -1.0f),    0.5f,   make_float3(0.1f, 0.2f, 0.5f) },
{ make_float3(0.0f, -100.5f, -1.0f), 100.0f, make_float3(0.8f, 0.8f, 0.0f) }
```

The first sphere is now a dark bluish material, and the ground becomes yellow. That makes more sense once albedo is part of the bounce chain, because now those colors actually modulate transported light instead of merely being painted onto the first visible hit.

So yes, color has been promoted from cosmetic to causal. Big day for `float3`.

## Accumulation Still Works, Just With Real Paths Now

The accumulation buffer logic stays the same structurally, but it now blends `pixelColorRGBA` instead of the old one-hit color:

```cpp
finalColor.x = oldColor.x + (pixelColorRGBA.x - oldColor.x) / n;
finalColor.y = oldColor.y + (pixelColorRGBA.y - oldColor.y) / n;
finalColor.z = oldColor.z + (pixelColorRGBA.z - oldColor.z) / n;
```

That means the accumulation system is now averaging noisy bounced-light samples instead of flat primary-ray hits. Which is exactly why it exists. Monte Carlo rendering without accumulation is just an expensive way to admire noise.

## One Curious Passenger: `GetHeatmapColor`

There is also a new helper:

```cpp
__device__ float3 GetHeatmapColor(float t)
```

It maps `t` in `[0,1]` from blue to green to red. In this commit, it is not used anywhere. So functionally, it changes nothing in the renderer right now. It is just there, waiting patiently, like a debug visualization feature that knows its time will come.

## Commit

GitHub commit: [TheOrestes/CUDA_Tracer@fc97d41](https://github.com/TheOrestes/CUDA_Tracer/commit/fc97d418048619958a2ec4ffc7a45732abc3185c)
