+++
title = "A Triangle Is Two Questions"
date = 2026-08-18T00:00:00+05:30
tags = ["raytracing", "geometry", "math", "cpp"]
description = "The first primitive that isn't a sphere: a plane intersection, three cross products, and the abstraction from post 3 finally earning its keep."
+++

Spheres got me a long way. A sphere is a centre and a radius, its intersection test is a quadratic, and everything I've built so far — materials, threading, the whole renderer — works on nothing else.

&nbsp;

But almost nothing in the world is a sphere, and everything I'd eventually want to load is made of triangles. So this commit adds one.

## One more `Hitable`

```cpp
class Triangle : public Hitable
{
public:
	Triangle() {}
	Triangle(Vector3 _v0, Vector3 _v1, Vector3 _v2, Material* ptr_mat) :
		V0(_v0),
		V1(_v1),
		V2(_v2),
		mat_ptr(ptr_mat) {};

	virtual bool hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const;

private:
	Vector3 V0;
	Vector3 V1;
	Vector3 V2;
	Material* mat_ptr;
};
```

&nbsp;

Three vertices, a material, and the same single virtual function `Sphere` implements. That's the whole declaration.

&nbsp;

This is the moment the abstraction from post 3 pays for itself. Nothing else in the renderer changes to accommodate a completely different kind of geometry — `HitableList` doesn't know, `TraceColor` doesn't know, the materials don't know. I wrote a class that can answer a question about a line, put it in the list, and it renders. That's the whole integration.

&nbsp;

The intersection itself splits into two questions, and it's worth keeping them separate in your head because the code does.

## Where does the ray meet the plane?

A triangle sits in a plane. So before asking anything about the triangle, I work out where the ray crosses that plane.

&nbsp;

```cpp
Vector3 edge0 = V1 - V0;
Vector3 edge1 = V2 - V1;
Vector3 edge2 = V0 - V2;

Vector3 N = unit_vector(cross(edge0, edge1));
```

&nbsp;

The three edges as vectors, and the plane normal from the cross product of two of them. Which direction $\vec{N}$ points falls out of the winding order of the vertices — swap two of them and the normal flips.

&nbsp;

![The two halves of the test. First the ray meets the plane the triangle lies in, which is a single division. Then three cross products decide whether that point is inside the triangle or merely somewhere on its plane](/images/blog/raytracer/triangle_two_tests.svg)

&nbsp;

```cpp
float NdotRayDirection = dot(N, r.GetRayDirection());
if (fabs(NdotRayDirection) < 0.001f)
	return false;
```

&nbsp;

If the ray runs parallel to the plane there's no intersection to find, and $\vec{N} \cdot \vec{D}$ is what tells me — it goes to zero exactly when the direction lies in the plane. The $0.001$ is a floating point cushion. Testing against exact zero would technically be correct and would also mean a ray that misses by a rounding error produces a $t$ of several million.

&nbsp;

Then the plane itself:

&nbsp;

```cpp
float d = dot(V0, N);
float t = (d - dot(N, r.GetRayOrigin())) / NdotRayDirection;
```

&nbsp;

A plane is every point whose projection onto the normal is the same:

&nbsp;

$$
\vec{N} \cdot \vec{P} = d, \qquad d = \vec{N} \cdot \vec{V_0}
$$

&nbsp;

Substitute the ray, $\vec{P} = \vec{O} + t\vec{D}$, and solve:

&nbsp;

$$
\vec{N} \cdot (\vec{O} + t\vec{D}) = d
\quad\Longrightarrow\quad
t = \frac{d - \vec{N} \cdot \vec{O}}{\vec{N} \cdot \vec{D}}
$$

&nbsp;

One division. Compared to the sphere's quadratic this is cheap, which is a happy accident given how many more triangles than spheres I'm going to end up tracing.

## Is that point actually in the triangle?

The plane is infinite. The triangle is a small bounded piece of it, and so far I've only found a point on the plane.

&nbsp;

Skipping the second half makes that vivid. Here's the same scene with the inside test bypassed, accepting every hit on the plane:

&nbsp;

![The same render with the inside-outside test replaced by "yes". The triangle becomes the unbounded plane it was always a piece of — the green fills everything behind the spheres, and the ground plane's horizon cuts across it](/images/blog/raytracer/triangle_plane_only.png)

&nbsp;

So the second question:

&nbsp;

```cpp
Vector3 P0 = P - V0;	
Vector3 P1 = P - V1;
Vector3 P2 = P - V2;

if (dot(N, cross(edge0, P0)) >= 0 && dot(N, cross(edge1, P1)) >= 0 && dot(N, cross(edge2, P2)) >= 0)
```

&nbsp;

Three cross products, one per edge. For each one I take the edge vector and the vector from that edge's start vertex to the hit point, cross them, and check whether the result points the same way as the normal.

&nbsp;

$$
\vec{N} \cdot \left( \vec{e_i} \times (\vec{P} - \vec{V_i}) \right) \ge 0 \qquad \text{for } i = 0, 1, 2
$$

&nbsp;

The cross product of two vectors is perpendicular to both, and which of the two perpendicular directions you get depends on their handedness. Walk the triangle's edges in order and a point inside always sits on the same side of every edge — so all three cross products come out pointing along $\vec{N}$. Step outside any single edge and that one flips to point against it, and the dot product goes negative.

&nbsp;

It's the same trick as the discriminant in post 3: a sign carrying a geometric fact. Three of them here, and the point has to satisfy all three.

## The scene, adjusted to show it off

![The commit's own output. The green triangle stands behind the spheres, and both metal spheres pick it up in their reflections — nothing in the material code knows or cares that it's reflecting a different kind of primitive](/images/blog/raytracer/triangle_scene.png)

&nbsp;

I moved the camera for this one. It went from `lookFrom(0, 1.5, 6)` to `(0, 5, 5)` with the field of view widened from 20° to 40° — higher up and looking down, because a triangle standing upright behind the spheres isn't visible from the old angle. I also swapped the glass sphere for a plain red diffuse one and pushed the samples from 50 to 100.

&nbsp;

The detail I like is in the two metal spheres. They reflect the triangle, and not one line of `Metal::Scatter` knows that triangles exist. It asks the world what a ray hits and multiplies by albedo. Adding a primitive got reflections of that primitive for free, everywhere, immediately.

## Things I know about

A few of these are already bothering me.

&nbsp;

`N` is computed and normalized on every single intersection test, which is a cross product and a square root per ray per triangle — for vertices that never move. It belongs in the constructor. With one triangle in the scene I can't measure it; with a mesh I expect I'll be able to.

&nbsp;

Every point on the face gets the same normal, because there's only one. That's correct for a triangle and it's going to look wrong for a mesh, where a curved surface approximated by flat faces needs normals interpolated across each one to look smooth. That's a later problem and a good one.

&nbsp;

The test uses `>= 0` rather than `> 0`, so a point landing exactly on an edge counts as inside. Two triangles sharing that edge will both claim it. It's a measure-zero case and I doubt I'd ever see it, but it's there.

&nbsp;

There's also a second implementation of the whole thing sitting commented out at the bottom of the file — a version that checks whether the segment between $t_{min}$ and $t_{max}$ crosses the plane before doing the edge tests. I evidently wrote one, wrote the other, kept the one I preferred and couldn't bring myself to delete the loser.

&nbsp;

And one small piece of housekeeping in the same commit: `Vector3::MakeUnitVector` is gone. It had been defined `inline` inside `Vector3.cpp`, which means it was only ever usable from that one file — anything else that tried to call it would have failed to link. Removing it costs nothing, since `unit_vector` already does the job as a free function.

## Where this leaves us

One triangle. It renders, it reflects, and it took a new class and no changes anywhere else.

&nbsp;

The trouble is that one triangle is a shape and a model is tens of thousands of them, each needing a material pointer and a place to live. The way I'm building scenes right now — a raw `Hitable**` array with a hand-counted size, `new`ed and never freed — is not going to survive contact with that.

&nbsp;

---

**Commit:** [`06912d4` — Added Triangle primitive support](https://github.com/TheOrestes/Windows_RayTracer/commit/06912d4)

&nbsp;

*Next up: a Scene abstraction, and working out who actually owns all this geometry.*
