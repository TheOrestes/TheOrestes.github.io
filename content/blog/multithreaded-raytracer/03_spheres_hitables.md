+++
title = "The Quadratic That Decides What You Can See"
date = 2026-08-16T00:00:00+05:30
tags = ["raytracing", "geometry", "math", "cpp"]
description = "Hitable, HitRecord, and a ray-sphere intersection that is just the quadratic formula wearing a trenchcoat."
+++

Last post ended with a camera that can turn any pixel into a ray. Which is lovely, and completely useless, because there is nothing out there for the ray to hit.

&nbsp;

This post fixes that. Three small headers — `Hitable.h`, `HitableList.h`, `Sphere.h` — and by the end of them the renderer can answer the only question it actually cares about: *given this ray, what is the nearest thing in front of it, and what does the surface look like there?*

&nbsp;

![A ray meets a sphere twice, and the quadratic returns both: `t₁` where it goes in, `t₂` where it comes out. The near root is tried first because it is the surface you can see. The normal falls out of the hit for free — the vector from centre to surface point, divided by a radius it already has. Below, the discriminant doing the geometry](/images/blog/raytracer/ray_sphere_roots.svg)

## Everything is a `Hitable`

The abstraction is one virtual function.

&nbsp;

```cpp
class Hitable
{
public:
	virtual bool hit(const Ray& r, float t_min, float t_max, HitRecord& rec) const = 0;
};
```

&nbsp;

That is the entire interface. Not "draw yourself", not "give me your vertices" — just *can this ray hit you, and if so, tell me about it.*

&nbsp;

Worth sitting with how different that is from the pipeline you know. In rasterization, geometry has to be expressible as triangles, because the hardware only knows how to fill triangles. A sphere is not a sphere; it is a few hundred triangles pretending, and the illusion gets worse the closer you look at the silhouette.

&nbsp;

Here a sphere is a centre and a radius, and its silhouette is exact at any zoom level, because nothing is ever tessellated. The only requirement to join the scene is being able to answer a question about a line. Triangles will show up eventually, and when they do they will be one implementation of `Hitable` among several, not the privileged primitive everything else has to imitate.

&nbsp;

The `t_min` and `t_max` parameters bound the search. A hit is only interesting if it lands inside that interval — which gives the caller a way to say "I only care about things between here and there" without every primitive inventing its own convention.

## The hit record is the surface, packaged

```cpp
struct HitRecord
{
	float t;
	Vector3 P;
	Vector3 N;
	Material* mat_ptr;
};
```

&nbsp;

Four fields: how far along the ray the hit happened, where that is in space, which way the surface faces, and what it's made of.

&nbsp;

`P` is redundant and stored anyway. Given $t$ you can always recover the point with $P(t) = \vec{O} + t\vec{D}$ from last post — but you'd be recomputing it at every stage that wants it, so it gets cached once at the moment of the hit. That is the entire justification, and it's a good one.

&nbsp;

`mat_ptr` is the interesting one, because **materials do not exist yet.** `Hitable.h` forward-declares `class Material;` and stores a pointer to a type that has no definition anywhere in this post. The hit record is built to carry information it has no way to use, because the author already knew what was coming.

&nbsp;

This is the same pattern as `nSamples = 1` and `aperture = 0.0f` from the last two posts — the shape of the thing arrives before the thing does.

## The sphere, or: the quadratic formula in disguise

Here is the part that made me want to write this post.

&nbsp;

A sphere is every point at distance $r$ from a centre $\vec{C}$:

&nbsp;

$$
\|\vec{P} - \vec{C}\|^2 = r^2
$$

&nbsp;

A ray is every point $\vec{O} + t\vec{D}$. So "does this ray hit this sphere" is just: is there a $t$ that satisfies both? Substitute one into the other:

&nbsp;

$$
(\vec{O} + t\vec{D} - \vec{C}) \cdot (\vec{O} + t\vec{D} - \vec{C}) = r^2
$$

&nbsp;

Write $\vec{oc} = \vec{O} - \vec{C}$, expand the dot product, and collect powers of $t$:

&nbsp;

$$
(\vec{D} \cdot \vec{D})\,t^2 + 2(\vec{oc} \cdot \vec{D})\,t + (\vec{oc} \cdot \vec{oc} - r^2) = 0
$$

&nbsp;

That is $at^2 + bt + c = 0$. A quadratic. The code says so without ceremony:

&nbsp;

```cpp
Vector3 oc = r.GetRayOrigin() - center;
float a = dot(r.GetRayDirection(), r.GetRayDirection());
float b = 2.0f * dot(oc, r.GetRayDirection());
float c = dot(oc, oc) - radius * radius;
float discriminant = b * b - 4 * a* c;
```

&nbsp;

Four dot products and some arithmetic. There is no ray-sphere algorithm to look up, no special-cased geometry routine — the intersection test *is* the quadratic formula, applied to an equation you can derive on a napkin.

&nbsp;

Note $a = \vec{D} \cdot \vec{D}$ rather than $1$. Last post flagged that `Ray` never normalizes its direction, and this is where that comes home: the code cannot assume $\|\vec{D}\| = 1$, so it computes $a$ honestly instead of dropping it.

### The discriminant is the geometry

$b^2 - 4ac$ is doing something more interesting than usual here. In the abstract it tells you how many real roots a quadratic has. In this context it tells you, literally, what the ray did:

&nbsp;

| Discriminant | Roots | What happened |
|---|---|---|
| $< 0$ | none | the ray missed |
| $= 0$ | one | the ray grazed the surface, exactly tangent |
| $> 0$ | two | the ray went in one side and out the other |

&nbsp;

A ray that hits a sphere hits it *twice*. Front and back. That is obvious once stated and easy to forget, and it's why the code has to decide which of the two answers it wants.

&nbsp;

```cpp
if (discriminant > 0)
```

&nbsp;

Strictly greater, so the tangent case counts as a miss. Mathematically that discards a real intersection; practically it's a set of measure zero and floating point was never going to land on it anyway. A tangent ray contributes nothing you'd notice.

### Two roots, nearest first

&nbsp;

```cpp
t = (-b - sqrt(discriminant)) / (2.0 * a);
if (t < tmax && t > tmin)
{
	rec.t = t;
	rec.P = r.GetPointAt(t);
	rec.N = (rec.P - center) / radius;
	rec.mat_ptr = mat_ptr;
	return true;
}

t = (-b + sqrt(discriminant)) / (2.0 * a);
```

&nbsp;

The quadratic formula with the minus sign first. Since $\sqrt{\text{disc}}$ and $2a$ are both positive, $(-b - \sqrt{\text{disc}})$ is the smaller root — the nearer of the two hits, the front surface. Try it, and only if it falls outside $[t_{min}, t_{max}]$ fall through to the far root.

&nbsp;

The far root is not a fallback for tidiness. It's what you get when the near hit is behind you — when the ray origin is *inside* the sphere. Then the entry point sits at negative $t$, fails the interval test, and the exit point is the one you actually want. A renderer that only ever computed the near root would work fine right up until something needed to see out from inside a piece of glass.

### The normal comes out free

&nbsp;

```cpp
rec.N = (rec.P - center) / radius;
```

&nbsp;

The direction from centre to surface point, which is the outward normal by definition. What's nice is the second half: that vector already has length exactly $r$, so dividing by `radius` normalizes it. No `sqrt`, no `normalize()` call — the geometry hands you a unit vector if you divide by the number you already have.

&nbsp;

Small thing. But it's the second time in three posts that this code has avoided a square root by noticing something true about the shape rather than reaching for the general-purpose function, and that adds up.

## The list is your depth buffer

One primitive is not a scene. `HitableList` is a `Hitable` that owns other `Hitable`s — the composite pattern, and the reason the renderer never needs to know how many kinds of geometry exist.

&nbsp;

```cpp
HitRecord temp_rec;
bool hit_anything = false;
double closest_so_far = tmax;

for (int i = 0; i < list_size; i++)
{
	if (hitable_list[i]->hit(r, tmin, closest_so_far, temp_rec))
	{
		hit_anything = true;
		closest_so_far = temp_rec.t;
		rec = temp_rec;
	}
}
```

&nbsp;

Six lines that replace a piece of dedicated hardware.

&nbsp;

`closest_so_far` starts at `tmax` and shrinks every time something is hit. It is passed *back in* as the `tmax` for the next object — so once you've found something at $t = 3$, every remaining primitive is asked a narrower question: "do you hit this ray closer than 3?" Anything behind fails its own interval test and never reaches the comparison.

&nbsp;

That is a depth buffer. Not an analogy — the same job, resolved the same way, by a running minimum instead of a per-pixel memory allocation. In rasterization you write depths into a buffer because triangles arrive in arbitrary order and you need somewhere to remember the winner. Here the loop *is* the ordering, one pixel at a time, so the winner fits in a local variable.

&nbsp;

![The scene as written: `closest_so_far` shrinking with every hit, so the nearest surface wins and the spheres occlude each other the way solid objects should](/images/blog/raytracer/depth_sorted.png)

&nbsp;

![The same scene with one line commented out — `closest_so_far` never updates, so every primitive is asked the same unbounded question and each hit simply overwrites the last. The list order becomes the draw order: the brown sphere disappears entirely (though its shadow does not, since shadow rays are a separate query), and the yellow sphere three units further back now floats in front of the glass. This is the picture a depth buffer exists to prevent](/images/blog/raytracer/no_depth_sort.png)

&nbsp;

Two details in those six lines are worth a raised eyebrow. `closest_so_far` is a `double` while `t`, `tmin` and `tmax` are all `float` — a lone widening in otherwise uniformly single-precision code, doing nothing that a `float` wouldn't. And `rec = temp_rec` copies the whole record every time a nearer hit is found, rather than at the end.

&nbsp;

The scan is linear. Every ray asks every object in the scene whether it was hit, which is $O(n)$ per ray, and with a ray per sample per pixel that multiplies out fast. For five spheres it is completely fine. It is going to stop being fine, and the fix — a bounding volume hierarchy — is a long way down this series.

## A note on the headers

Both `HitableList::hit` and `Sphere::hit` are *defined* in their headers, outside the class body and without `inline`. That's a one-definition-rule violation waiting for a second translation unit to include them.

&nbsp;

It doesn't bite here, because there is barely a second translation unit to speak of. It's the kind of thing that stays invisible for years and then surfaces the first time someone splits a file.

## Where this leaves us

There is now a scene. Rays go out, the quadratic decides what they meet, the list decides which answer wins, and a `HitRecord` comes back describing a point in space and the direction the surface faces there.

&nbsp;

What is still missing is any notion of what a surface *does* to a ray. `mat_ptr` is sitting in the hit record, pointing at a class that doesn't exist, waiting.

&nbsp;

---

**Commit:** [`24e60c1` — GDI based ray tracer, First commit](https://github.com/TheOrestes/Windows_RayTracer/commit/24e60c1)

&nbsp;

*Next up: Lambertian, Metal, and dielectrics — the three materials that turn a normal into a colour.*
