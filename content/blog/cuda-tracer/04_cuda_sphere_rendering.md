+++
title= "Spheres, Hits, and a Sky"
date= 2025-12-12T00:00:00+05:30
tags= ["cuda", "ray-tracing", "rendering", "cpp"]
+++

Up until now the renderer shot rays into the void and got back a noisy mess of random colors. Useful for testing accumulation — not exactly a scene. This commit changes that. We now have actual geometry, actual intersection logic, and a sky gradient that doesn't look like TV static.

{{< youtube X0IHPbAKP8c >}}

## The Sky Was Lying to You

The very first bug — and it was a quiet one — was in `GetMissColor`. The "white to blue" sky lerp was using *random floats* for both the white and the blue end of the gradient:

```cpp
// Before — this is not a sky, this is noise wearing a sky costume
float3 white = make_float3(rand_float(&state), rand_float(&state), rand_float(&state));
float3 blue  = make_float3(rand_float(&state), rand_float(&state), rand_float(&state));
```

Every pixel, every frame, both endpoints of the lerp were randomized. The accumulation buffer was averaging out random gradients and producing a smeared grey-ish nothing. Fixing it is embarrassingly simple:

```cpp
const float3 white = make_float3(1, 1, 1);
const float3 blue  = make_float3(0.5f, 0.7f, 1.0f);
```

Now the sky is a clean gradient — bright white near the horizon, pale blue at the top — driven purely by the ray's Y direction. The accumulation buffer is now averaging the *same* sky every frame, which is exactly what it should be doing.

## Enter: The Sphere

The main addition is a proper `Sphere` struct that lives on the GPU and knows how to test ray intersections. The math is the classic quadratic derivation — substitute the ray equation $$P(t) = O + t·D$$ into the sphere equation $$|P - C|² = r²$$ expand, and you get:

$$
at^2 + bt + c = 0
$$

where 

$$a = dot(D, D)$$
$$b = 2·dot(oc, D)$$
$$c = dot(oc, oc)$$
$$oc = O - C$$

The discriminant `b² - 4ac` tells you whether the ray missed (negative), grazed (zero), or punched through (positive). When it's positive, you get two `t` values — entry and exit points of the sphere. The code checks the smaller `t` first (the closer hit), then falls back to the larger one. Both are clamped to `[t_min, t_max]` to avoid hits behind the camera or self-intersections.

```cpp
__device__ bool hit(const Ray& r, float t_min, float t_max, HitRecord& rec) const
{
    const float3 oc = r.Origin - center;
    const float a = dot(r.Direction, r.Direction);
    const float b = 2.0f * dot(oc, r.Direction);
    const float c = dot(oc, oc) - radius * radius;
    const float discriminant = b * b - 4 * a * c;

    if (discriminant > 0)
    {
        float temp = (-b - sqrtf(discriminant)) / a;
        if (temp < t_max && temp > t_min)
        {
            rec.t = temp;
            rec.P = r.GetAt(rec.t);
            rec.Normal = (rec.P - center) / radius;
            return true;
        }
        // ... check the other root too
    }
    return false;
}
```

The result gets written into a `HitRecord` — a small struct holding the hit distance `t`, the world-space hit point `P`, and the outward surface normal at that point.

## The Scene and How It's Colored

`HitWorld` defines the scene inline as a fixed array of two spheres: a red ball at `(0, 0, -1)` and a giant green sphere at `(0, -100.5, -1)` that acts as the floor. The loop walks every sphere, tracks the closest hit so far, and returns the winning color.

Two coloring strategies are available in the code:

- **Flat color** — use the sphere's assigned color directly. Red ball, green floor. Simple and readable. This is the active path.
- **Normal visualization** — maps the surface normal from `[-1, 1]` to `[0, 1]` per channel, giving a rainbow-ish shading that makes the curvature of the sphere immediately visible. One uncomment away, great for debugging geometry.

The closest-hit tracking (`closest_so_far = temp_rec.t` on each iteration) ensures that if two spheres overlap in screen space, the one physically in front wins — no accidental bleed-through.

## The Kernel Ties It Together

The main `RayTracer` kernel now branches on geometry:

```cpp
RT::HitRecord rec;
float3 hitColor;
float3 currentColor;

if (HitWorld(r, 0.001f, 1000.0f, rec, hitColor))
    currentColor = hitColor;
else
    currentColor = GetMissColor(r, localState);
```

Miss? You get sky. Hit? You get the sphere's color. The `0.001f` lower bound on `t` is a small but important detail — it prevents a reflected or secondary ray from immediately re-intersecting the surface it just left, which would show up as dark speckles (shadow acne). There are no secondary rays yet, but it's a good habit to guard against it from the start.


## Next up

The normals are computed and stored in `HitRecord`, but right now they only feed the (commented-out) normal visualization path. Once diffuse scattering comes in, they'll actually earn their place.

## Commit

GitHub commit: [Link](https://github.com/OWNER/REPO/commit/COMMIT_SHA)