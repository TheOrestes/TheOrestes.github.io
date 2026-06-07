+++
title = "FPS Camera, Transparent Glass, and a Timer"
date = 2026-01-03T18:03:00+05:30
tags = ["cuda", "rendering", "raytracing", "opengl"]
description = "Mouse-look camera, Snell's law refraction, Fresnel via Schlick, SPP tracking, and render timing."
math = true
+++

In this post, we mostly talk about making the renderer feel less like a demo held together with optimism. One of them, however, sneaks in actual physics — the transparent material is now real, and it bends light the way real glass does.

&nbsp;

{{< youtube hXhUGmUcdKs >}}

&nbsp;

The changes are:

1. The center sphere becomes a glass sphere with a proper refractive material.
2. Refraction and Fresnel are implemented in the kernel.
3. The camera now rotates with right mouse drag.
4. Accumulation tracks samples per pixel instead of raw frame count.
5. The renderer prints progress and timing while converging.

## Glass Enters the Scene

The center sphere changes from a Lambertian yellow ball to a transparent sphere:

```cpp
// Center Transparent sphere
RT::SceneObject centerSphere;
centerSphere.type = RT::SPHERE;
centerSphere.MaterialID = 0;
centerSphere.sphere.center = make_float3(0, 0, 0.35f);
centerSphere.sphere.radius = 0.5f;
```

And its material changes from:

```cpp
{RT::LAMBERTIAN, {0.8f, 0.8f, 0.0f}, 0.0f, 0.0f }
```

to:

```cpp
{RT::TRANSPARENT, {0.8f, 0.8f, 0.0f}, 0.0f, 1.5f }
```

The last value, `1.5f`, is the Index of Refraction (IoR). That is a physically reasonable value for glass.

## Snell's Law in the Kernel

The `TRANSPARENT` material case now computes refraction correctly using Snell's law:

$$
n_1 \sin\theta_1 = n_2 \sin\theta_2
$$

In vector form, the refracted direction is computed by the new `Refract()` function:

```cpp
__device__ bool Refract(const float3& V, const float3& N, float ni_over_nt, float3& refracted)
{
    const float3 uv = unit_vector(V);
    const float dt = dot(uv, N);
    const float discriminant = 1.0f - ni_over_nt * ni_over_nt * (1.0f - dt * dt);

    if (discriminant > 0.0f)
    {
        refracted = ni_over_nt * (uv - N * dt) - N * sqrtf(discriminant);
        return true;
    }

    return false; // Total internal reflection
}
```

The discriminant here is the key quantity:

$$
\Delta = 1 - \left(\frac{n_1}{n_2}\right)^2 (1 - \cos^2\theta_1)
$$

If 

$$
\Delta \leq 0\
$$ 

the angle of incidence is past the critical angle and total internal reflection occurs — the ray bounces back instead of passing through.

## Entering vs Exiting

A tricky but important part of glass rendering is knowing which way the ray is going through the surface. This is resolved by checking the sign of 

$$
\dot{r} \cdot N
$$

```cpp
if (dot(r.Direction, rec.Normal) > 0.0f)
{
    // Exiting the material
    outward_normal = -rec.Normal;
    ni_over_nt = material.IoR;
    cosine = material.IoR * dot(r.Direction, rec.Normal) / sqrtf(dot(r.Direction, r.Direction));
}
else
{
    // Entering the material
    outward_normal = rec.Normal;
    ni_over_nt = 1.0f / material.IoR;
    cosine = -dot(r.Direction, rec.Normal) / sqrtf(dot(r.Direction, r.Direction));
}
```

When entering, the ratio is 

$$
1 / \text{IoR}\
$$

When exiting, it flips to 

$$
\text{IoR}
$$ 

The normal is also flipped on exit so it always points against the incoming ray. A new unary negation operator was added to `RT_Common.cuh` to make this clean:

```cpp
__host__ __device__ inline float3 operator-(const float3& a)
{
    return make_float3(-a.x, -a.y, -a.z);
}
```

## Schlick Approximation for Fresnel

Real glass does not just refract — it also partially reflects, and how much it reflects depends on the viewing angle. The renderer now computes this with Schlick's approximation:

$$
R(\theta) = R_0 + (1 - R_0)(1 - \cos\theta)^5
$$

where

$$
R_0 = \left(\frac{n_1 - n_2}{n_1 + n_2}\right)^2
$$

In code:

```cpp
__device__ float Schlick(float cosine, float ref_idx)
{
    float r0 = (1.0f - ref_idx) / (1.0f + ref_idx);
    r0 = r0 * r0;
    return r0 + (1.0f - r0) * powf((1.0f - cosine), 5.0f);
}
```

The result is a probability. The renderer then randomly chooses reflection or refraction each sample using that probability:

```cpp
if (RandomFloat(&localState) < reflect_prob)
{
    r = RT::Ray(rec.P, reflected);
}
else
{
    r = RT::Ray(rec.P, refracted);
}
```

That stochastic split is exactly what Monte Carlo path tracers do to handle the Fresnel boundary. Averaged over many samples, the ratio of reflected to refracted rays naturally converges to the correct Fresnel curve. Since glass does not absorb light, the color throughput is multiplied by white:

```cpp
currentColor = currentColor * make_float3(1.0f, 1.0f, 1.0f);
```

Which is just a polite way of saying the material does not attenuate anything.

## Mouse Look Arrives

Separate from the glass work, the camera now rotates with right mouse drag. Right mouse button press captures the cursor and hides it. Mouse movement while held calls `gCamera.Rotate()`. Button release restores the cursor.

The movement delta is scaled by a sensitivity constant:

$$
\Delta\theta = \text{mouse delta} \times 0.003
$$

That is tiny on purpose. Nobody wants a camera that spins like it owes them money.

## Camera Rotation Becomes Yaw and Pitch

The camera now stores two angles:

```cpp
float yaw, pitch;
```

Initialized from the look direction as:

$$
\text{yaw} = \operatorname{atan2}(d_x, -d_z), \quad \text{pitch} = \arcsin(d_y)
$$

Pitch is clamped to 

$$
\pm 1.553343 \text{ radians } (\approx 89^\circ)
$$

to avoid gimbal lock at the poles:

```cpp
constexpr float max_pitch = 1.553343f;
```

After each rotation, the camera rebuilds its basis vectors and recomputes viewport corners so ray generation stays consistent.

## Samples Per Pixel Becomes the Real Counter

The accumulation loop switches from a raw frame counter to an explicit `currentSPP` variable. The kernel's RNG seed, accumulation blend, and progress tracking all use this instead of `frameCount`.

The code now tracks:

```cpp
bool accumulationComplete = false;
int currentSPP = 0;
constexpr int targetSPP = 100;
```

and only keeps running the kernel while accumulation is incomplete. That is a better model because what matters for image quality is:

$$
\bar{L} = \frac{1}{N} \sum_{i=1}^{N} L_i
$$

where \(N\) is the number of samples per pixel, not the number of times the window loop ticked.

## Progress and Timing

The renderer now prints progress at every tenth of the target sample count:

$$
\text{progress} = \frac{\text{currentSPP}}{\text{targetSPP}} \times 100, \quad \text{SPP/s} = \frac{\text{currentSPP}}{T}
$$

where \(T\) is elapsed time since accumulation started.

&nbsp;

When done, it prints total SPP, total render time, and average SPP/s. If the camera moves, the accumulation buffer is cleared, the SPP counter resets to zero, and the timer restarts.

So the renderer now behaves like a renderer, not like a frozen screenshot generator with occasional feelings.

## Commit

GitHub commit: [replace with actual commit URL](https://github.com/OWNER/REPO/commit/COMMIT_SHA)