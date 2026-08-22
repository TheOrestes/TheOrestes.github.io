+++
title = "The Estimator That Cancelled Itself"
date = 2026-08-22T10:00:00+05:30
tags = ["raytracing", "sampling", "pbr", "cpp"]
description = "Three commits to get importance sampling working, the first of which the commit message calls a failed attempt — and a refactor that was both correct and a no-op."
+++

Last post left two things lying around: a hemisphere mapping with a cosine exponent that nothing called, and a `TraceColor` that already divided by a PDF nothing meaningfully returned. These three commits close both, and the first one is labelled by its own commit message:

&nbsp;

> Failed attempt at Importance Sampling, added other minor tweaks.

## What the failed attempt actually did

Almost entirely a rename. Every `attenuation` in the material interface becomes `albedo`:

&nbsp;

```cpp
-	virtual bool	  Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& attenuation, Ray& scattered) const = 0;
+	virtual bool		Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& albedo, Ray& scattered) const = 0;
```

&nbsp;

and `TraceColor` follows:

&nbsp;

```cpp
-			traceColor = emitted + (attenuation * (TraceColor(scatteredRay, depth + 1, rayCount)));
+			traceColor = emitted + (albedo * TraceColor(scatteredRay, depth + 1, rayCount));
```

&nbsp;

The picture doesn't change, because nothing about the arithmetic changed. But the two words mean different things, and swapping them is the move that makes the next commit possible. *Attenuation* is a number you multiply by — it says how much light survives a bounce, and it belongs to no particular theory. *Albedo* is a property of the surface, and it only means something as one term in an equation that also has a BRDF and a probability density in it. You can't write the estimator until the thing in your hand has the right name.

&nbsp;

Calling that a failed attempt is fair — nothing got sampled importantly. It's also the necessary first step, and I'd rather have the honest commit message than a grander one.

## The framework

The next commit puts `PDF` on the interface as a pure virtual, so every material has to answer for the distribution it samples from:

&nbsp;

```cpp
class Material
{
public:
	virtual bool		Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& albedo, Ray& scattered) const = 0;
	virtual glm::vec3	Emitted(const glm::vec2& uv) const { return glm::vec3(0); }

	virtual float		PDF(const Ray& r_in, const HitRecord& rec, const Ray& scattered) const = 0;
};
```

&nbsp;

`Lambertian` gains the two functions the rendering equation asks for:

&nbsp;

```cpp
float Lambertian::PDF(const Ray& r_in, const HitRecord& rec, const Ray& scattered) const
{
	float NdotWi = glm::dot(r_in.direction, rec.N);
	return NdotWi * INV_PI;
}

glm::vec3 Lambertian::BRDF(const Ray& r_in, const HitRecord& rec, const Ray& scattered) const
{
	return glm::vec3(INV_PI);
}
```

&nbsp;

and `Scatter` assembles the numerator:

&nbsp;

```cpp
// Lambert BRDF = rho * (INV_PI)
glm::vec3 brdf = BRDF(r_in, rec, scatterd);

outColor = albedo * brdf * NdotWi;
```

&nbsp;

with `TraceColor` supplying the division:

&nbsp;

```cpp
float pdf = rec.mat_ptr->PDF(r, rec, scatteredRay);
traceColor = emitted + ((outColor * TraceColor(scatteredRay, depth + 1, rayCount))) / pdf;
```

&nbsp;

That is the Monte Carlo estimator, written out properly:

&nbsp;

$$L \;\approx\; \frac{\rho \cdot f_r(\omega_i, \omega_o) \cdot \cos\theta}{p(\omega_i)}$$

&nbsp;

Which is the right shape, and it is genuinely worth having as structure — every material now declares its own BRDF and its own density instead of the tracer assuming both.

## And it renders exactly what it replaced

Look at what those two functions compute. The BRDF is the constant `INV_PI`. The PDF is `NdotWi * INV_PI`. So the estimator is:

&nbsp;

$$\frac{\rho \cdot \frac{1}{\pi} \cdot \text{NdotWi}}{\text{NdotWi} \cdot \frac{1}{\pi}} \;=\; \rho$$

&nbsp;

Everything except the albedo divides out. Whatever `NdotWi` happens to be, it appears once above the line and once below it, so the code evaluates to `albedo * TraceColor(scattered)` — which is precisely the line the previous commit had.

&nbsp;

That includes the fact that `NdotWi` is wrong. It's built from `r_in.direction`, the ray arriving *at* the surface, where the cosine in the rendering equation is the angle of the ray leaving it, and the vector isn't normalised either. For a Lambertian sampled proportionally to the cosine, none of that matters, because the same wrong quantity cancels against itself.

&nbsp;

That's an easy claim to make and an easy one to check, so I rendered both commits — same scene, same camera, same 500 × 500 frame at 64 samples, threads joined so each one finishes:

&nbsp;

| | mean level | channels identical |
|---|---|---|
| before the framework | 144.6169 | — |
| with BRDF, PDF and the division | 144.6169 | 750,000 of 750,000 |

&nbsp;

Byte for byte. Every one of the 750,000 channels comes out the same value, and the largest difference anywhere in the image is zero.

&nbsp;

Two things had to be controlled to get that answer, and both caught me out first. The renders are deterministic — `rand()` is never seeded, so the same build twice produces an identical file — which is what made a bit-exact comparison possible at all. But the scene definition drifts between the two commits: the camera moves from `(0, 3.5, 7)` to `(0, 1.5, 4)`, and the emissive sphere is pushed into the scene in one and not the other. Comparing them as they ship compares the scenes, not the estimator, and it shows a difference of up to 162 levels that has nothing to do with importance sampling. Pin the camera and the object list and the difference vanishes entirely.

&nbsp;

I like this commit a lot for what it is. The estimator is now written where a reader can see it, each material owns its own distribution, and the next commit only has to change one function to make it real. It just doesn't do anything yet, and the render is the proof.

## The real one

The third commit replaces the sampling itself. Out goes the old trick of picking a point on a unit sphere offset by the normal:

&nbsp;

```cpp
-	glm::vec3 target = rec.P + rec.N + Helper::RandomUnitVector();
-	scatterd = Ray(rec.P, target - rec.P);
+	glm::vec3 direction = Helper::CosineSamplingUpperHemisphere(rec.N);
+	scatterd = Ray(rec.P, glm::normalize(direction));
```

&nbsp;

and in comes the thing itself:

&nbsp;

```cpp
inline glm::vec3 CosineSamplingUpperHemisphere(glm::vec3 Normal)
{
	float rand1 = GetRandom01();
	float rand2 = GetRandom01();

	float phi = TWO_PI * rand2;	// phi = 2PI * esp2
	float y = sqrtf(rand1);		// y = sqrt(eps1)

	float theta = acosf(y);
	...
```

&nbsp;

The square root is where the weighting lives. Draw a uniform number and take its arccosine and you get directions spread evenly over the dome; take the arccosine of its *square root* and they bunch toward the normal instead.

&nbsp;

![Sixty scattered directions from one hit point, drawn both ways](/images/blog/raytracer/cosine_hemisphere.svg)

&nbsp;

That's the whole idea behind the word "importance". The rendering equation already multiplies every incoming direction by the cosine of its angle to the normal, so a ray that leaves near the horizon is worth almost nothing before it has even been traced. Sampling uniformly spends a fixed fraction of the budget on those. Sampling proportionally to the cosine spends it where the answer is largest, and the PDF in the denominator corrects for the bias exactly.

&nbsp;

The generated direction points along the local Y axis, so it has to be rotated into the surface's own frame — an orthonormal basis built from the normal:

&nbsp;

```cpp
glm::vec3 v = glm::normalize(Normal);
glm::vec3 u = glm::normalize(glm::cross(Up, v));
glm::vec3 w = glm::cross(v, u);

return X * u + Y * v + Z * w;
```

## A material with two lobes

The same commit adds `Phong`, and this is where the framework earns itself. A Phong surface is part diffuse and part specular, so it has two BRDFs and two densities, weighted by `Kd` and `Ks`:

&nbsp;

```cpp
float Phong::PDF(const Ray& r_in, const HitRecord& rec, const Ray& scattered) const
{
	// Lambertian PDF
	float NdotWi = glm::clamp(glm::dot(r_in.direction, rec.N), 0.0f, 1.0f);
	float lambertPDF = Kd * INV_PI;

	// Specular PDF
	glm::vec3 PerfectReflDir = glm::normalize(Helper::Reflect(r_in.direction, rec.N));
	float alpha = glm::clamp(glm::dot(scattered.direction, PerfectReflDir), 0.0f, PI_OVER_TWO);
	float specularPDF = Ks * (SpecularPower + 1) / TWO_PI * powf(alpha, SpecularPower);

	return glm::clamp(lambertPDF + specularPDF, 0.0f, 1.0f);
}
```

&nbsp;

Sampling picks between the lobes and the PDF accounts for both, which is the point of making every material answer the same two questions. A single hardcoded scatter rule in the tracer could never have expressed this.

&nbsp;

![`77bad97`, 500 × 500 at 64 samples. The sphere on the left is the new Phong material — the room, the light panel and the yellow emitter are all in its reflection. The colour on the floor is light that bounced off the walls](/images/blog/raytracer/cornell_phong.png)

## What I'd fix next

Three, all known, none of them visible in the picture above.

&nbsp;

The cosine is still taken from the incoming ray rather than the scattered one. It cancels for `Lambertian` and so costs nothing there — but `Phong`'s BRDF and PDF are not proportional to each other, so nothing guarantees the cancellation, and that's the material where it starts to matter.

&nbsp;

There's a parenthesis in the wrong place in the basis construction:

&nbsp;

```cpp
if (fabsf(Normal.y > 0.9f))
```

&nbsp;

The comparison happens inside `fabsf`, so what gets its absolute value taken is a `bool`, and the guard reduces to `Normal.y > 0.9f`. It exists to avoid building a basis from a normal that is parallel to `Up`, and as written it only catches half of that — a normal pointing straight *down* is equally parallel and takes the other branch. Moving one bracket is the entire change.

&nbsp;

And in the specular BRDF, the modified Phong normalisation is `(n + 2) / 2π` where `n` is the exponent, but the code has `((alpha + 2) / TWO_PI)` — `alpha` is the cosine, not the exponent. It should be `SpecularPower`.

## Where this leaves the series

This is the last post. `77bad97` is the newest commit the renderer has, so there's nothing further to write up until there's something further to build.

&nbsp;

Seventeen posts, and the renderer at the end of them samples proportionally to how much each direction is worth, keeps its own profiler, sorts its triangles into a tree, reads models and materials out of an FBX, and hands its pixels to the GPU as a texture.

&nbsp;

Plenty is still open, and I'd rather list it than tidy it away. The display never did catch up with the render — the buffer refines continuously and nothing draws it until the workers stop, which is the one thing that would make this feel like a tool rather than a batch job. The sampler generates one set of offsets for the whole image. Leaf size is a fraction rather than a constant, so the tree bottoms out three levels down no matter how large the mesh. The threads are detached rather than joined. There's a bracket to move.

&nbsp;

The first post in this series was about putting every pixel on screen with an individual call to `SetPixel`, from inside `WM_PAINT`, one at a time. Everything since has been finding out what that cost and what to do instead — which is, more or less, what writing a renderer is.

## Picking it back up

Going through it commit by commit has been more useful than I expected. Some of it I remembered doing; a fair amount of it I'd forgotten entirely, and a few things I only properly understood while looking at the diff — that the ray counter and the profiler counters are the same problem solved twice, that the reflection bug and the bounding boxes were the same commit's doing, that a refactor can be completely correct and change nothing at all. Reading your own history is a slower way to learn something than writing it was, and a surprisingly effective one.

&nbsp;

I don't think this project is finished, and I hope it isn't. The list above is a good list — none of it is research, all of it is an afternoon or two, and the renderer is in far better shape to receive it than it was at any point in this series. Live display while the workers run is the one I'd start with, because everything else gets easier to judge once you can watch it happen. After that: a proper set of sampler sets, a leaf size that isn't a fraction, direct light sampling so the Cornell box stops being quite so noisy.

&nbsp;

If it does get picked up again, this series is what it should be picked up from — the code is public, every commit here builds today, and the numbers in these posts came from running them. And if someone else finds it first and takes it somewhere, that's a better outcome than it sitting still.

&nbsp;

---

**Commits:** [`44dd135` — Failed attempt at Importance Sampling](https://github.com/TheOrestes/Windows_RayTracer/commit/44dd135) · [`7e8263a` — Framework for importance sampling](https://github.com/TheOrestes/Windows_RayTracer/commit/7e8263a) · [`77bad97` — Cosine sampling for Lambertian, Phong with importance sampling](https://github.com/TheOrestes/Windows_RayTracer/commit/77bad97)

&nbsp;

*That's the series. The repository is [TheOrestes/Windows_RayTracer](https://github.com/TheOrestes/Windows_RayTracer) — it builds from a clean clone with `.\build.ps1 -Run`.*
