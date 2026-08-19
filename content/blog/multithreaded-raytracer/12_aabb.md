+++
title = "The Deer With No Legs in the Mirror"
date = 2026-08-19T00:00:00+05:30
tags = ["raytracing", "performance", "debugging", "cpp"]
description = "A bounding box around every mesh, and the one-character bug that only ever showed up in a reflection."
+++

Every ray in my renderer still asks every triangle. A ray heading off into empty sky, nowhere near the deer, patiently tests all 1503 of its faces before concluding what was obvious from the start.

&nbsp;

The cheapest fix is a box.

## Two planes per axis

An axis-aligned bounding box is six numbers: the minimum and maximum of the geometry along each axis. Building one is a fold over the vertices as they're loaded:

&nbsp;

```cpp
void AABB::UpdateBB(const glm::vec3& _pos)
{
	if (_pos.x < minBound.x) { minBound.x = _pos.x; }
	if (_pos.y < minBound.y) { minBound.y = _pos.y; }
	if (_pos.z < minBound.z) { minBound.z = _pos.z; }

	if (_pos.x > maxBound.x) { maxBound.x = _pos.x; }
	...
}
```

&nbsp;

And testing one is the slab method — treat the box as three pairs of parallel planes, work out where the ray crosses each pair, and ask whether those three intervals have anything in common.

&nbsp;

![The ray enters and leaves each pair of planes, giving one interval of t per axis. It's inside the box wherever all of them overlap](/images/blog/raytracer/aabb_slab_test.svg)

&nbsp;

The whole test is a running maximum of the entry distances against a running minimum of the exits, bailing out the moment they cross:

&nbsp;

```cpp
tmin = (t0x > tmin) ? t0x : tmin;
tmax = (t1x < tmax) ? t1x : tmax;
if (tmax <= tmin)
	return false;
```

&nbsp;

Six divisions and some comparisons, no square roots, no cross products. Against 1503 triangle tests each of which does several of both, that's an enormous saving for any ray that misses — and most rays miss most things.

&nbsp;

The division is worth avoiding too, so `Ray` starts carrying its reciprocal:

&nbsp;

```cpp
invDirection = glm::vec3(1 / direction.x, 1/direction.y, 1/direction.z);
```

&nbsp;

Computed once per ray, used by every box test that ray performs. Multiplication instead of division, six times per box.

&nbsp;

Then the mesh gets a gate in front of its loop:

&nbsp;

```cpp
if (m_ptrAABB->hit(r, tmin, tmax))
{
	for (int i = 0; i < m_vecTriangles.size(); i++)
	{
		...
	}
}
```

&nbsp;

One box, one early out, and the deer stops charging every passing ray 1503 questions.

&nbsp;

![The scene with bounding boxes in. The orange sphere is a perfect mirror, and the deer's reflection in it is where this post is going](/images/blog/raytracer/aabb_scene.png)

## And then the reflections went wrong

The next commit is titled *"Fixed reflection bug, modified AABB hit function"*, and those two things are the same thing.

&nbsp;

Here is the Z slab from the original, verbatim:

&nbsp;

```cpp
// Z Direction
float t0z = (minBound[2] - rayOrigin[2]) * rayInvDirection[2];
float t1z = (maxBound[2] - rayOrigin[2]) * rayInvDirection[2];
if (rayInvDirection[1] < 0.0f)
	std::swap(t0z, t1z);
```

&nbsp;

Everything on those first two lines is indexed `[2]`. The condition on the third asks about `[1]`.

&nbsp;

That swap exists because which plane the ray reaches first depends on which way it's travelling along that axis. Point the other way and the two distances come out in the wrong order, and the interval has to be flipped. The X block checks X, the Y block checks Y, and the Z block — written third, after two correct ones — checks Y again.

&nbsp;

Here is what that looked like:

&nbsp;

![Same commit, same scene, same camera. The only difference is which version of `AABB::hit` is built](/images/blog/raytracer/aabb_reflection_ab.png)

&nbsp;

The deer loses its legs in the mirror.

## Why only there

This is the part I find genuinely interesting, and it's why the bug survived as long as it did.

&nbsp;

The interval only comes out backwards when the ray's Y and Z components disagree in sign. Camera rays all leave the same point heading into roughly the same region of the world, so they largely agree with each other — whatever the bug does to them, it does consistently, and the direct view looks correct.

&nbsp;

Scattered rays don't. A metal surface reflects into whatever direction the geometry dictates, and a diffuse one scatters into a hemisphere. Those rays go every which way, so a good fraction of them hit the disagreeing case, get told the box was missed, and return sky instead of deer.

&nbsp;

Which produces a very specific symptom: the model is fine when you look at it and partly absent when you look at it in something else. That reads like a materials problem. It is not a materials problem.

&nbsp;

There's a measurable side to it too. The broken version renders that scene in **14.1 seconds of CPU** against **31.9** for the fixed one, because rejecting geometry you should have hit is a marvellous optimisation right up until you look at the output.

## The fix is a loop

I didn't repair the condition. I replaced the whole thing:

&nbsp;

```cpp
for (int a = 0; a < 3; a++)
{
	float t0 = fminf((minBound[a] - r.GetRayOrigin()[a]) / r.GetRayDirection()[a],
					 (maxBound[a] - r.GetRayOrigin()[a]) / r.GetRayDirection()[a]);

	float t1 = fmaxf((minBound[a] - r.GetRayOrigin()[a]) / r.GetRayDirection()[a],
					 (maxBound[a] - r.GetRayOrigin()[a]) / r.GetRayDirection()[a]);

	tmin = fmaxf(t0, tmin);
	tmax = fminf(t1, tmax);

	if (tmax <= tmin)
		return false;
}
```

&nbsp;

One axis index, `a`, used everywhere. There is no second index to get wrong, and no swap to forget — `fminf` and `fmaxf` sort the pair without needing to know which way the ray points.

&nbsp;

That's the real lesson rather than "check your indices". The bug was possible because I'd written the same eight lines three times with a number changed, and code like that fails by copy-paste. Making the axis a loop variable didn't fix the bug so much as make it unrepresentable.

&nbsp;

It costs something. The rewrite divides by the direction rather than multiplying by the cached reciprocal, and computes both bounds twice to feed `fminf` and `fmaxf`. So the correct version is doing more arithmetic per box than the broken one — and I'll take that trade every time.

## Two more edits in the same commit

Both look like fixes and neither is:

&nbsp;

```cpp
-	cosine = glm::dot(-ray_direction, rec.N) / glm::length(ray_direction);
+	cosine = -glm::dot(ray_direction, rec.N) / glm::length(ray_direction);
```

&nbsp;

```cpp
-	if (glm::length(scatteredRay.GetRayOrigin() - scatteredRay.GetRayDirection()) < 0.0000001f)
+	if (glm::distance(scatteredRay.GetRayOrigin(), scatteredRay.GetRayDirection()) < 0.0000001f)
```

&nbsp;

Negating a dot product is the same as dotting the negation, and `distance(a, b)` is defined as `length(a - b)`. Both rewrites compute exactly what they computed before. I was hunting — changing anything that looked suspicious while trying to find the real culprit, which is what debugging actually looks like when you don't know where to aim.

&nbsp;

The second one is worth a look regardless, because it compares a ray's *origin* against its *direction*. Those are a point and a vector; the distance between them isn't a meaningful quantity. Whatever that condition was supposed to catch, it isn't catching it.

## Where this leaves us

Every mesh has a box, most rays that miss now find out cheaply, and the bug that came with it took months to notice because it only ever appeared in a reflection.

&nbsp;

One box per mesh is a start. Inside the box, a ray that does hit still asks all 1503 triangles.

&nbsp;

---

**Commits:** [`da1081d` — Added AABB support for triangle meshes](https://github.com/TheOrestes/Windows_RayTracer/commit/da1081d) · [`5770d79` — Fixed reflection bug, modified AABB hit function](https://github.com/TheOrestes/Windows_RayTracer/commit/5770d79)

&nbsp;

*Next up: a tree of those boxes, and a profiler to find out whether it helped.*
