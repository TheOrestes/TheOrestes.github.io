+++
title = "Absorb, Bounce, or Bend"
date = 2026-08-17T00:00:00+05:30
tags = ["raytracing", "materials", "math", "cpp"]
description = "Lambertian, Metal and a dielectric — three surfaces, one virtual function, and a piece of glass that flips a coin."
+++

Last post ended with a `HitRecord` carrying a `Material*` pointed at a class I hadn't written yet. Here it is, and it turned out to be the smallest of the three abstractions in the whole renderer.

&nbsp;

Geometry answers *where*. Materials answer *what happens next*. And "what happens next" is my entire lighting model — I wrote no shading equation, no light loop, no BRDF evaluation. Just one function that takes an incoming ray and produces an outgoing one.

## `Material` is one virtual function too

```cpp
class Material
{
public:
	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, Vector3& attenuation, Ray& scattered) const = 0;
};
```

&nbsp;

Structurally identical to `Hitable` from last post: a single pure virtual returning `bool`, with the interesting results handed back through out-parameters. My whole renderer is two of these interfaces pointed at each other.

&nbsp;

The `bool` means *did the ray survive*. `scattered` is where it goes next. `attenuation` is what happens to its colour on the way — and I chose that word carefully, because it's a multiplier, not a colour.

&nbsp;

You can see why in the recursion, which post 1 showed the top of:

&nbsp;

```cpp
if (depth < 50 && rec.mat_ptr->Scatter(r, rec, attenuation, scatteredRay))
{
	return attenuation * TraceColor(scatteredRay, world, depth + 1);
}
else
{
	return Vector3(0, 0, 0);
}
```

&nbsp;

Every bounce multiplies. A ray that survives $k$ bounces before escaping to the sky comes back as

&nbsp;

$$
C = a_1 \, a_2 \cdots a_k \cdot C_{\text{sky}}
$$

&nbsp;

componentwise, with each $a_i$ the albedo of a surface it touched. Nothing in my renderer emits light. **The sky is the only light source**, and every pixel is sky light that survived some number of multiplications on the way to the eye.

&nbsp;

Which also explains where black comes from. Not from a shadow test — I never wrote one — but from a product of numbers below 1, and from that `depth < 50` cutoff returning `Vector3(0, 0, 0)` outright for rays that never escape.

## Lambertian: aim at a random point in a tangent sphere

```cpp
virtual bool Scatter(const Ray& r_in, const HitRecord& rec, Vector3& attenuation, Ray& scatterd) const
{
	Vector3 target = rec.P + rec.N + Helper::RandomInUnitSphere();
	scatterd = Ray(rec.P, target - rec.P);
	attenuation = Albedo;
	return true;
}
```

&nbsp;

Three lines, and the first one is my whole diffuse lighting model.

&nbsp;

`rec.P + rec.N` is the centre of a unit sphere sitting exactly on top of the surface, tangent at the hit point — the normal is unit length, so stepping one unit along it from $P$ lands you one radius above the surface. Add a random point from inside that sphere and I have a target. Aim there.

&nbsp;

![The one line that is the whole diffuse model. Step one unit along the normal and you are at the centre of a sphere resting on the surface, touching it at exactly the hit point. Pick any point inside that sphere, aim there, and the ray necessarily leaves the surface — while landing near the normal more often than near the horizon](/images/blog/raytracer/lambertian_scatter.svg)

&nbsp;

The scattered direction is therefore

&nbsp;

$$
\vec{d} = (\vec{P} + \vec{N} + \vec{s}) - \vec{P} = \vec{N} + \vec{s}, \qquad \vec{s} \in \text{unit ball}
$$

&nbsp;

which is why the sphere has to be tangent rather than centred at $P$. A sphere centred on the hit point would scatter rays *into* the surface half the time. Offsetting it by $\vec{N}$ biases every direction outward, and biases them toward the normal — directions near $\vec{N}$ have more of the sphere behind them than directions near the horizon. That bias is the cosine falloff I knew from `N · L`, arrived at without ever computing a dot product.

&nbsp;

Note what *isn't* here. No light position. No `N · L`. No shadow ray. A Lambertian surface never asks where the light is; it throws the ray somewhere plausible and lets the recursion find out. That still strikes me as a lovely trade.

&nbsp;

Two smaller things. `attenuation = Albedo` unconditionally and the function always returns `true`, so a Lambertian surface here never absorbs a ray outright, it only dims it. And `Ray(rec.P, target - rec.P)` hands over an unnormalized direction again — third post running where that's true and still fine, because every intersection test computes $a = \vec{D} \cdot \vec{D}$ rather than assuming it is 1.

## Metal: reflect, then rough it up

```cpp
Vector3 target = Helper::Reflect(unit_vector(r_in.GetRayDirection()), rec.N);
scatterd = Ray(rec.P, target + fuzz * Helper::RandomInUnitSphere());
attenuation = Albedo;
return (dot(scatterd.GetRayDirection(), rec.N) > 0);
```

&nbsp;

`Reflect` is one line, and worth writing out because it's the same trick as the tangent sphere — geometry standing in for a formula:

&nbsp;

```cpp
Vector3 Reflect(const Vector3& v, const Vector3& n)
{
	return v - 2 * dot(v, n) * n;
}
```

&nbsp;

$$
\vec{r} = \vec{v} - 2(\vec{v} \cdot \vec{n})\,\vec{n}
$$

&nbsp;

$(\vec{v} \cdot \vec{n})\,\vec{n}$ is the part of the incoming direction that runs along the normal. Subtract it once and you flatten the ray into the surface plane; subtract it twice and you flip it to the other side. Mirror reflection, no trigonometry.

&nbsp;

Then `fuzz` perturbs the result — a random offset from the unit sphere, scaled. At `fuzz = 0` I get a perfect mirror. Larger values smear the reflection into something brushed. The constructor clamps it:

&nbsp;

```cpp
Metal (const Vector3& _albedo, float f) : Albedo(_albedo) 
{
	if (f < 1)
		fuzz = f;
	else
		fuzz = 1;
}
```

&nbsp;

![The mirror direction, then a sphere of radius `fuzz` around it to pick the actual scattered ray from. At a grazing angle like this one the mirror direction already lies close to the surface, so part of that sphere is *under* it — and any sample landing there produces a ray pointing into the solid, which `Scatter` reports as dead](/images/blog/raytracer/metal_reflect_fuzz.svg)

&nbsp;

That clamp matters because of the last line. Unlike Lambertian, `Metal::Scatter` can return `false`:

&nbsp;

$$
\vec{d} \cdot \vec{N} > 0
$$

&nbsp;

If the fuzz offset is large enough to push the scattered ray *below* the surface it just bounced off, the material gives up and reports the ray as dead — and `TraceColor` turns that into black. So fuzz doesn't only blur a metal, it darkens it, most visibly at grazing angles where the reflected direction already lies close to the surface and a small nudge is enough to bury it. That's why the clamp is there: unclamped above 1, the offset could exceed the reflected vector's own length and I'd be burying rays constantly.

## Transparent: the one that flips a coin

This is the longest of the three, and the only one where I left a question mark in the code for myself. Worth taking in pieces.

&nbsp;

First, which way am I going through the surface?

&nbsp;

```cpp
if (dot(ray_direction, rec.N) > 0)
{
	outward_normal = -1 * rec.N;
	ni_over_nt = refr_index;
	cosine = refr_index * dot(ray_direction, rec.N) / ray_direction.length();
}
else
{
	outward_normal = rec.N;
	ni_over_nt = 1 / refr_index;
	cosine = -dot(ray_direction, rec.N) / ray_direction.length();
}
```

&nbsp;

`Sphere::hit` from last post always returns the outward normal, $(\vec{P} - \vec{C})/r$, with no idea whether I was inside or outside. So the material works it out from the sign of $\vec{d} \cdot \vec{N}$: positive means the ray is travelling *with* the normal, which can only happen on the way out. Then I flip the normal and invert the index ratio, because glass-to-air is the reciprocal of air-to-glass.

&nbsp;

Then the refraction itself, from `Helper.h`:

&nbsp;

```cpp
bool Refract(const Vector3& v, const Vector3& n, float ni_over_nt, Vector3& refracted)
{
	Vector3 unit_v = unit_vector(v);
	float NdotV = dot(unit_v, n);
	float discriminant = 1.0 - ni_over_nt * ni_over_nt * (1 - NdotV * NdotV);

	if (discriminant > 0)
	{
		refracted = ni_over_nt * (unit_v - NdotV * n) - sqrt(discriminant) * n;
		return true;
	}
	else
		return false;
}
```

&nbsp;

That's Snell's law,

&nbsp;

$$
n_1 \sin\theta_1 = n_2 \sin\theta_2
$$

&nbsp;

rearranged into vectors. And there's a discriminant again, doing the same job it did for the sphere — telling you whether a solution exists at all:

&nbsp;

$$
1 - \left(\frac{n_1}{n_2}\right)^{2}\left(1 - (\hat{v} \cdot \vec{n})^{2}\right)
$$

&nbsp;

When it goes negative there's no angle that satisfies Snell, and physically that's **total internal reflection** — light trying to leave a dense medium at too shallow an angle can't escape and turns back inside. `Refract` returns `false` and I set `reflect_prob = 1.0f`. It's the same "is there a real root" question the ray-sphere test asks, answering something completely different, which I enjoyed more than I probably should have.

&nbsp;

![Left: entering glass, the ray bends toward the normal and a few percent reflects off the surface. Right: the same boundary from inside, approached too shallowly. There is no angle that satisfies Snell's law, the discriminant goes negative, and every bit of the light turns back into the glass](/images/blog/raytracer/refraction_tir.svg)

&nbsp;

Then Fresnel, approximated:

&nbsp;

```cpp
float schlick(float cosine, float ref_idx)
{
	float r0 = (1 - ref_idx) / (1 + ref_idx);
	r0 = r0 * r0;
	return r0 + (1 - r0)*pow((1 - cosine), 5);
}
```

&nbsp;

$$
R(\theta) = R_0 + (1 - R_0)(1 - \cos\theta)^{5}, \qquad R_0 = \left(\frac{1 - n}{1 + n}\right)^{2}
$$

&nbsp;

Schlick's approximation, and the reason glass looks like glass. $R_0$ is the reflectance looking straight at the surface — for $n = 1.5$ that's about 4%, which is why a window facing you is mostly transparent. The $(1 - \cos\theta)^5$ term drives it toward 1 at grazing angles, which is why the same window becomes a mirror when you look along it. One number and one power for the effect that makes rendered glass convincing.

&nbsp;

And then the part with the comment:

&nbsp;

```cpp
// this logic is not clear? 
if (Helper::GetRandom01() < reflect_prob)
{
	scattered = Ray(rec.P, reflected);
}
else
{
	scattered = Ray(rec.P, refracted);
}
```

&nbsp;

A real surface does both at once: some light reflects, the rest transmits. My code does one or the other, chosen at random, weighted by `reflect_prob`. I genuinely wasn't sure this was right when I wrote it — hence the comment.

&nbsp;

It works because of the sampling loop from post 1. A single ray gives a coin flip, which is meaningless. Average enough of them and the fraction that reflected converges on $R(\theta)$ — the split I wanted in the first place. It's Monte Carlo integration, and I'd written it before I could name it. It's also why glass is the first thing to look wrong at low sample counts while the diffuse surfaces already look fine.

&nbsp;

One last line worth noticing:

&nbsp;

```cpp
attenuation = Vector3(1, 1, 1);
```

&nbsp;

Glass takes nothing. Every other material dims the ray by its albedo; this one multiplies by 1 and passes the light through untouched. I have no coloured glass and no absorption with distance yet — a ray crosses the sphere and comes out exactly as bright as it went in. Both are things I'd like to add.

## Where this leaves us

And that's the entire renderer. Rays from a camera with no matrices, a quadratic deciding what they meet, and three materials deciding what happens next — all of it recursive, all of it converging by averaging noise, and all of it inside that one 852-line first commit.

&nbsp;

From here it stops being about what my renderer computes and starts being about how long it makes me wait.

&nbsp;

---

**Commit:** [`24e60c1` — GDI based ray tracer, First commit](https://github.com/TheOrestes/Windows_RayTracer/commit/24e60c1)

&nbsp;

*Next up: the first attempt at threading — `std::thread`, horizontal bands, and a shared device context that does not appreciate it.*
