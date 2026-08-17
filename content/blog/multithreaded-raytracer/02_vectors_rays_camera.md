+++
title = "A Camera With No Matrices"
date = 2026-08-09T00:00:00+05:30
tags = ["raytracing", "math", "camera", "cpp"]
description = "Vector3, Ray, and a camera that builds an orthonormal basis instead of a projection matrix — plus why the sky is a lerp."
+++

Last post was about where I put the pixels. This one is about what I compute before they get there.

&nbsp;

Four files, all from that same first commit: `Vector3.h`, `Vector3.cpp`, `Ray.h`, and `Helper.h`, plus `Camera.h`. Together they're maybe 250 lines, and they're the entire mathematical foundation of the renderer. I pulled in no third-party math library for this — no GLM, nothing — and hand-rolled all of it, mostly because writing it myself was the point.

&nbsp;

`Vector3.h` and `Vector3.cpp` hold exactly what you'd expect — three public floats, the usual arithmetic operators, dot, cross, and length — and I use the same type as the renderer's colour type throughout.

&nbsp;

The part I find most interesting, coming from realtime rendering, is the camera. It has no view matrix. It has no projection matrix. It never transforms the world into camera space. Once I understood what it does instead, a lot of ray tracing clicked into place.

&nbsp;

![The camera as I actually model it: an origin, three perpendicular unit vectors, and a rectangle floating in space. `u` is camera-right, `v` is camera-up, and `w` points backward — from the target toward the eye, not the way the camera looks. Every ray starts at the origin and is aimed at a point on that rectangle](/images/blog/raytracer/camera_basis_diagram.svg)

## `Ray` is four lines of idea

```cpp
class Ray
{
public:
	Ray() {}
	Ray(const Vector3& A, const Vector3& B)
	{
		origin = A;
		direction = B;
	}

	Vector3 GetRayOrigin() const { return origin; }
	Vector3 GetRayDirection() const { return direction; }
	Vector3 GetPointAt(float t) const { return origin + t * direction; }

private:
	Vector3 origin;
	Vector3 direction;
};
```

&nbsp;

A ray is an origin and a direction, and `GetPointAt` is the only thing it really does:

&nbsp;

$$
P(t) = \vec{O} + t\,\vec{D}
$$

&nbsp;

That equation is the spine of the entire renderer. Every intersection test in every future post — spheres, triangles, bounding boxes, BVH nodes — works by substituting $P(t)$ into some surface's equation and solving for $t$. The smallest positive $t$ wins, because that's the nearest thing in front of you.

&nbsp;

If you're used to a depth buffer sorting visibility for you after the fact, this is the replacement: visibility is whichever $t$ is smallest, computed directly.

&nbsp;

One detail with consequences: **the constructor does not normalize the direction.** It just copies `B`. So $\|\vec{D}\|$ is whatever the caller passed in, and $t$ is measured in units of that length rather than in world units. Two rays pointing the same way but with different direction magnitudes will report different $t$ values for the same intersection point.

&nbsp;

That's fine as long as I stay consistent about it, and it saves a square root per ray. It's the kind of decision that stays completely invisible until it isn't.

## `Helper` is where the randomness lives

```cpp
const float PI = 3.14159265358f;

double GetRandom01()
{
	return ((double)rand() / (RAND_MAX + 1));
}
```

&nbsp;

`rand()` divided by `RAND_MAX + 1`. The `+ 1` is doing real work: it makes the result exclusive of $1.0$, giving $[0, 1)$ rather than $[0, 1]$. Half-open intervals are what you want for sampling — a sample landing exactly on the upper edge of a pixel belongs to the next pixel.

&nbsp;

Two things about `rand()` are worth flagging now, because they'll matter later. On MSVC, `RAND_MAX` is $32767$, so this generator produces just $32768$ distinct values — quite coarse when you're firing hundreds of samples through every pixel. And `rand()` draws from a single piece of global state, which is a detail that becomes considerably more interesting the moment more than one thread starts calling it.

### Rejection sampling, twice

```cpp
Vector3 GetRandomInUnitDisk()
{
	Vector3 p;
	do
	{
		p = 2.0f * Vector3(GetRandom01(), GetRandom01(), 0.0f) - Vector3(1, 1, 0);
	} while (dot(p, p) >= 1.0f);

	return p;
}
```

&nbsp;

If you need a uniformly random point inside a shape and you don't have a neat formula for it, there's a beautifully dumb technique: pick a random point in a box that contains the shape, and if it landed outside, throw it away and pick again.

&nbsp;

Here the box is the square $[-1,1]^2$ — that's what `2.0f * ... - Vector3(1,1,0)` does, remapping two numbers from $[0,1)$ to $[-1,1)$. The test `dot(p, p) >= 1.0f` rejects anything outside the unit circle.

&nbsp;

How wasteful is it? The acceptance rate is the ratio of areas:

&nbsp;

$$
\frac{\pi r^2}{(2r)^2} = \frac{\pi}{4} \approx 78.5\%
$$

&nbsp;

So roughly four attempts for every three points. Cheap.

&nbsp;

![Rejection sampling, drawn. Points are picked uniformly in the square — which is trivial, two independent numbers — and kept only if they land inside the inscribed disk, which is not trivial to sample directly. The crosses are the wasted draws. There are always some, and on average the loop runs 1.27 times](/images/blog/raytracer/rejection_sampling_disk.svg)

&nbsp;

The 3D version is the same idea one dimension up:

```cpp
Vector3 RandomInUnitSphere()
{
	Vector3 P;

	do
	{
		P = 2.0f * Vector3(GetRandom01(), GetRandom01(), GetRandom01()) - Vector3(1, 1, 1);
	} while (P.squaredLength() >= 1.0f);

	return P;
}
```

&nbsp;

And the acceptance rate drops, because a sphere fills less of its cube than a circle fills its square:

&nbsp;

$$
\frac{\frac{4}{3}\pi r^3}{(2r)^3} = \frac{\pi}{6} \approx 52.4\%
$$

&nbsp;

Just under half of all attempts get discarded. The loop still terminates quickly, but this is a genuinely hot path — it runs on every diffuse bounce of every ray — and "throw away half your random numbers" is the sort of thing I expect to find staring back at me from a profile later.

&nbsp;

`Helper.h` also contains `Reflect`, `Refract`, and `schlick`. Those are material behaviour rather than camera plumbing, so they belong with the materials post.

## The camera builds a basis, not a matrix

This is the part I want to slow down for, because it's where ray tracing stopped feeling like rasterization with extra steps.

```cpp
Camera(Vector3 lookFrom, Vector3 lookAt, Vector3 Up, float vfov, float aspect, float aperture, float focus_dist)
{
	lens_radius = aperture / 2.0f;

	float theta = vfov * PI / 180.0f;
	float half_height = tan(theta / 2);
	float half_width = aspect * half_height;

	origin = lookFrom;
	w = unit_vector(lookFrom - lookAt);
	u = unit_vector(cross(Up, w));
	v = cross(w, u);

	lower_left_corner = origin - half_width * focus_dist * u - half_height * focus_dist * v - focus_dist * w;
	horizontal = 2 * half_width * focus_dist * u;
	vertical = 2 * half_height * focus_dist * v;
}
```

&nbsp;

In a rasterizer, a camera is a pair of matrices. I'd build a view matrix to move the world into camera space and a projection matrix to squash that into clip space, then push every vertex through both. The camera is a *transform applied to geometry*.

&nbsp;

Here my geometry never moves at all. The camera is a **coordinate frame plus a rectangle floating in world space**, and its only job is to manufacture rays that start at the eye and pass through that rectangle.

### From field of view to a rectangle

```cpp
float theta = vfov * PI / 180.0f;
float half_height = tan(theta / 2);
float half_width = aspect * half_height;
```

&nbsp;

Degrees to radians, then straight trigonometry. At unit distance from the eye, a vertical field of view $\theta$ subtends a rectangle of half-height

&nbsp;

$$
h = \tan\!\left(\frac{\theta}{2}\right)
$$

&nbsp;

and the width follows from the aspect ratio, $w = \text{aspect} \cdot h$. This is the same relationship buried inside a perspective projection matrix — it's just sitting out in the open here instead of being packed into matrix entries.

### The orthonormal basis

```cpp
w = unit_vector(lookFrom - lookAt);
u = unit_vector(cross(Up, w));
v = cross(w, u);
```

&nbsp;

Three mutually perpendicular unit vectors, built with two cross products. That's the whole camera.

&nbsp;

Note the direction of $\vec{w}$: it's `lookFrom - lookAt`, which points **from the target back toward the eye** — the opposite of where the camera is looking. That's the standard right-handed convention, and it's why the image plane gets placed at $-\vec{w}$ later.

&nbsp;

$\vec{u}$ comes from crossing the world up vector with $\vec{w}$, giving camera-right. $\vec{v}$ is then $\vec{w} \times \vec{u}$, giving camera-up — and it needs no normalization, because the cross product of two perpendicular unit vectors is already unit length. Small thing, one square root saved, and I was quietly pleased with myself for noticing.

&nbsp;

If the world up vector were ever parallel to $\vec{w}$ — looking straight up or straight down — that first cross product would be the zero vector and the basis would collapse. That's the classic gimbal-ish failure of every `lookAt` ever written, and I don't guard against it yet — my camera never looks straight down, so it hasn't come up. It's on the list.

### The image plane

```cpp
lower_left_corner = origin - half_width * focus_dist * u - half_height * focus_dist * v - focus_dist * w;
horizontal = 2 * half_width * focus_dist * u;
vertical = 2 * half_height * focus_dist * v;
```

&nbsp;

A rectangle described by one corner and two edge vectors. Start at the eye, walk left by half the width, down by half the height, and forward by $-\vec{w}$ — everything scaled by `focus_dist`. `horizontal` and `vertical` then span the full rectangle, which is why they carry the factor of $2$.

&nbsp;

Any point on that rectangle is reachable by a simple weighted sum:

&nbsp;

$$
\vec{P}(s,t) = \text{LLC} + s\,\vec{h} + t\,\vec{v}, \qquad s,t \in [0,1]
$$

&nbsp;

And $s$ and $t$ are exactly the $u,v$ computed in last post's pixel loop. That's the whole handshake between the two files: the loop turns a pixel index into a pair of numbers in $[0,1]$, and the camera turns that pair into a point in space.

### Generating a ray, with a lens

```cpp
Ray get_ray(float s, float t)
{
	Vector3 rd = lens_radius * Helper::GetRandomInUnitDisk();
	Vector3 offset = rd.x * u + rd.y * v;
	return Ray(origin + offset, lower_left_corner + s * horizontal + t * vertical - origin - offset);
}
```

&nbsp;

Strip out the lens and it reads simply: origin at the eye, direction toward the point on the image plane, computed as target minus origin.

&nbsp;

The lens is what makes it interesting. A pinhole camera has everything in focus, always, because exactly one ray reaches each image point. A real camera has an aperture of nonzero size, and rays reaching one image point pass through *many* points on the lens.

&nbsp;

So I jitter the ray's starting point across a disk of radius `lens_radius`, then subtract that same `offset` from the direction so it still aims at the same target. Every ray for a given pixel starts somewhere slightly different but converges on the same point at `focus_dist`.

&nbsp;

Objects at that distance stay sharp, because all those rays agree. Objects nearer or farther get sampled from slightly different angles, so averaging the samples blurs them. That's depth of field — not a post-process, not a blur kernel, just geometry.

&nbsp;

![Rays leaving three different points on the lens, all aimed at the same point on the focus plane. There they agree exactly, and the average of agreeing samples is a sharp point. Nearer or further along, they have spread apart, and the average of disagreeing samples is a blur. Setting the aperture to zero collapses the lens to a single point, nothing can disagree, and the whole image is sharp](/images/blog/raytracer/thin_lens_dof.svg)

&nbsp;

This is why last post's scene setup had these two lines together:

```cpp
float dist_to_focus = 1.0f;	// set this to 1.0 & apertue to 0.0f to stop DOF effect!
float aperture = 0.0f;
```

&nbsp;

With `aperture = 0.0f`, `lens_radius` is zero, `offset` is the zero vector, and the whole lens calculation collapses back into a pinhole. So the feature is fully written and switched off — the same thing I did with `nSamples = 1` last post. I like building the machinery first with the knob at zero; it means turning it on later is one number rather than a rewrite.

&nbsp;

![With `aperture = 0.0f`, every ray leaves the same point and the lens code collapses to a pinhole — the yellow sphere three units behind the others is just as sharp as everything else](/images/blog/raytracer/dof_aperture_zero.png)

&nbsp;

![The same scene with `aperture = 0.35f` and `dist_to_focus` set to 6.185 — the distance from `lookFrom` to `lookAt`. The focus plane cuts through the glass sphere, and the yellow sphere behind it dissolves. Nothing changed but two floats](/images/blog/raytracer/dof_aperture_wide.png)

## The sky is a lerp

One last thing, and it's the function that made me want to write this post in the first place.

```cpp
Vector3 LerpVector(const Vector3& vec1, const Vector3& vec2, float t)
{
	return (1.0f - t) * vec1 + t * vec2;
}
```

&nbsp;

Standard linear interpolation, nothing surprising:

&nbsp;

$$
\text{lerp}(\vec{a}, \vec{b}, t) = (1-t)\,\vec{a} + t\,\vec{b}
$$

&nbsp;

But look at the one place it gets used — the `else` branch of `TraceColor`, back in `WindowsRayTracer.cpp`, the code path taken when a ray hits *nothing at all*:

```cpp
Vector3 unit_direction = unit_vector(r.GetRayDirection());
float t = 0.5 * (unit_direction.y + 1.0f);
return Helper::LerpVector(Vector3(1.0f, 1.0f, 1.0f), Vector3(0.5f, 0.7f, 1.0f), t);
```

&nbsp;

Normalize the direction, so $\hat{d}_y \in [-1, 1]$. Remap it to $[0, 1]$:

&nbsp;

$$
t = \tfrac{1}{2}\left(\hat{d}_y + 1\right)
$$

&nbsp;

Then blend white at the bottom to a pale blue $(0.5, 0.7, 1.0)$ at the top.

&nbsp;

There's no skybox. No cubemap, no environment texture, no sphere at infinity with a material on it. The background of every image I've rendered is a two-line function of the ray's $y$ component.

&nbsp;

And because it's a function rather than a texture, it's automatically correct from any angle, at any resolution, with no seams and no memory cost. Every ray that escapes the scene gets a plausible sky, and since diffuse surfaces bounce rays in all directions, that sky is also the renderer's only light source at this point. Everything you see lit in the first image is lit by this gradient.

&nbsp;

For four lines of code, I still think that's a wonderful deal.

&nbsp;

![The same renderer with an empty world: every ray misses, so every pixel is the sky lerp and nothing else. The lens is opened up here, because at the scene's usual 20° field of view you only catch a sliver of the gradient and it reads as flat colour. Watch the blue channel — it never moves. Both ends of the lerp have $b = 1.0$, so the entire gradient is red and green draining away](/images/blog/raytracer/sky_gradient_only.png)

## Where this leaves us

A ray that's really just $P(t) = \vec{O} + t\vec{D}$, a camera made of three perpendicular unit vectors and a floating rectangle, and a sky that's a lerp.

&nbsp;

No matrices, no math library, no external dependencies of any kind. About 250 lines, and everything I build after this sits on top of it.

&nbsp;

Next I need something for those rays to actually hit.

---

**Commit:** [`24e60c1` — GDI based ray tracer, First commit](https://github.com/TheOrestes/Windows_RayTracer/commit/24e60c1)

&nbsp;

*Next up: spheres, hit records, and the small quadratic that decides what you can see.*
