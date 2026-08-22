+++
title = "Where the Samples Land"
date = 2026-08-22T00:00:00+05:30
tags = ["raytracing", "sampling", "threading", "cpp"]
description = "Three ways to place sixteen points inside a pixel, turning the render inside out so it refines instead of finishing, and what moving one square root does to the picture."
+++

Every post so far has picked sample positions the same way:

&nbsp;

```cpp
float u = float(i + Helper::GetRandom01());
float v = float(j + Helper::GetRandom01());
```

&nbsp;

Two uniform randoms, once per sample. It's the obvious choice and it's the weakest of the three this commit introduces.

## A sampler is one virtual function

`Sampler.h` follows the shape everything else in this renderer follows — `Hitable`, `Material`, `Texture` — a base class with one thing to override:

&nbsp;

```cpp
class Sampler
{
public:
	// pure virtual function to be implemented by derived class!
	virtual void					GenerateSamples(uint32_t _numSamples) = 0;

	virtual void					MapSamplesToDisk();
	virtual void					MapSamplesToHemisphere(const float e);

	virtual std::vector<glm::vec2>  GetSamples()			{ return m_vecSamples; };
	...
};
```

&nbsp;

Three subclasses arrive with it: `RandomSampler`, `RegularSampler`, `JitteredSampler`. All three fill the same unit square; they differ only in where they put the points.

&nbsp;

![Sixteen samples in one pixel, the three ways this commit can place them](/images/blog/raytracer/sampler_patterns.svg)

&nbsp;

**Random** is the old behaviour, moved into a class:

&nbsp;

```cpp
glm::vec2 sample = glm::vec2(Helper::GetRandom01(), Helper::GetRandom01());
```

&nbsp;

Nothing coordinates the points, so they clump. In the set I generated above, six of the sixteen cells got nothing at all while others took two or three. Those empty regions are parts of the pixel that simply don't contribute, and the clumps are parts that count twice.

&nbsp;

**Regular** divides the pixel into a grid and takes the centre of each cell:

&nbsp;

```cpp
numSets = (m_uiNumSamples < 4) ? 1 : sqrt(m_uiNumSamples);

float x = (i + 0.5f) / numSets;
float y = (j + 0.5f) / numSets;
```

&nbsp;

Perfectly even coverage, and worse than random in a way that isn't obvious until you render with it. The positions are identical for every pixel in the image, so the sampling error is identical too — it stops being noise and becomes a pattern, and eyes are far better at spotting patterns than noise.

&nbsp;

**Jittered** is the same grid with one random point inside each cell:

&nbsp;

```cpp
float x = (i + Helper::GetRandom01()) / numSets;
float y = (j + Helper::GetRandom01()) / numSets;
```

&nbsp;

Every cell contributes exactly once, so coverage is guaranteed, and the position within the cell is random, so the error stays noise-like. Stratification, which is one of those ideas that costs nothing and is strictly better than the thing it replaces. It's the one `Initialize` builds:

&nbsp;

```cpp
m_pSampler = new JitteredSampler();
m_pSampler->GenerateSamples(m_iNumSamples);
```

&nbsp;

One thing to be careful of: `numSets` is the square root of the requested count, and `numSamplesPerGrid` is an integer division by `numSets²`. Ask for a perfect square and you get exactly what you asked for. Ask for 5 and you get 4 — the sampler quietly rounds down to the largest square that fits.

## Reading them back

The samples are generated once and read per thread:

&nbsp;

```cpp
std::vector<glm::vec2> samples = m_pSampler->GetSamples();
...
float u = float(i + samples[s].x);
float v = float(j + samples[s].y);
```

&nbsp;

Worth noting that `GetSamples()` returns by value — a full copy of the vector every call. Hoisting it out of the pixel loop is doing real work here; the same line inside the loop would copy that vector a quarter of a million times per frame.

&nbsp;

The known limit is on the line above it: there's **one** sample set, generated once, shared by every pixel in the image. Stratification fixes the coverage within a pixel but every pixel now jitters identically, which brings back a milder version of the problem `RegularSampler` has. The usual answer is to generate a few dozen sets up front and have each pixel pick one at random, and that's the next thing to do here.

## Turning the render inside out

The other half of this post is a loop swap. Before, each pixel was finished before moving to the next:

&nbsp;

```cpp
for each pixel
    for s in 0..ns
        trace
    average
    write
```

&nbsp;

After, each pass does the whole image once:

&nbsp;

```cpp
for (int s = 0; s < ns; ++s)
{
	for each pixel
	{
		trace one sample

		//!-- Accumulative buffer
		// So instead of running all the samples in each iteration, we run one sample
		// in each iteration & acumulate the result in final buffer!
		m_vecSrcPixels[j * endWidth + i] += (color / (float)ns);
	}
}
```

&nbsp;

Identical total work, completely different shape. After the first pass there is a whole image at one sample per pixel — grainy, but complete and correctly framed. After the tenth there's a whole image at ten. The picture converges rather than sweeping into existence, and you can stop whenever it looks good enough.

&nbsp;

Which is presumably why the sample count in the same commit goes from 16 to **1024**. That number only makes sense if you're no longer committing to it up front.

&nbsp;

![The scene these commits render: an earth-textured sphere on a diffuse ground, lit by the sky colour alone](/images/blog/raytracer/progressive_scene.png)

## One square root in the wrong place

Turning the loop inside out moved something that shouldn't have moved. Here is the accumulation again, in full:

&nbsp;

```cpp
color = color + TraceColor(r, 0, rayCount);

//color = color / float(ns);
color = glm::vec3(sqrt(color.x), sqrt(color.y), sqrt(color.z));

m_vecSrcPixels[j * endWidth + i] += (color / (float)ns);
```

&nbsp;

That `sqrt` is the gamma curve, and it now runs **per sample**, before the samples are averaged. It used to run once, on the average. Those are not the same operation:

&nbsp;

$$\frac{1}{n}\sum_{s} \sqrt{L_s} \;\neq\; \sqrt{\frac{1}{n}\sum_{s} L_s}$$

&nbsp;

Square root is concave, so the average of the roots is always the smaller of the two. Averaging gamma-encoded samples darkens the result, and by an amount that grows with how much the samples disagree.

&nbsp;

Rendering the same frame both ways, at 500 × 500 with 64 samples:

&nbsp;

| | mean level |
|---|---|
| gamma per sample, as committed | 143.67 |
| gamma applied once, at the end | 144.70 |

&nbsp;

Which looks like nothing — 0.7% across the image, and the two renders are indistinguishable side by side. The average is the wrong statistic, though, because the error is zero wherever the samples agree. Flat sky is flat sky no matter what order you apply the curve in.

&nbsp;

Where the samples *disagree*, it bites. The largest single-channel difference is **75 out of 255**:

&nbsp;

![Difference between the two, amplified four times. Black is where the two agree exactly](/images/blog/raytracer/gamma_placement_diff.png)

&nbsp;

The map is the variance of the render. Every bright pixel is somewhere rays landed on different things from one sample to the next — the horizon, the silhouette of the sphere, and most of all the soft shadow underneath it, which is exactly the region where some samples reach the sky and some don't. 4.2% of the image is off by more than 8 levels.

&nbsp;

The fix is to keep the buffer linear and apply the curve when the pixel is written out, which is where it wants to be anyway once there's a denoiser in the pipeline — that expects radiance, not gamma-encoded values.

## The threads are never joined

One more thing in the same function, and it's the reason my first attempt at those measurements produced a half-black image:

&nbsp;

```cpp
std::vector<std::thread*>::iterator iter = ThreadGroup.begin();
for (; iter != ThreadGroup.end(); iter++)
{
	(*iter)->detach();
}
```

&nbsp;

`detach`, not `join`. `Trace()` starts sixteen threads and returns immediately, so `Execute()` stops its clock while the image is still being written, and `main()` goes straight on to display, save and denoise a buffer that other threads are actively filling.

&nbsp;

It follows from the progressive change rather than contradicting it — if the buffer improves continuously then the main thread *should* be free to draw it while the workers run, and detaching is how you get that. What's missing is the other half: something on the main thread to keep drawing, and something to know when the workers are done. `main()` calls `UpdateGL` exactly once:

&nbsp;

```cpp
pApp->Execute(window);
pApp->UpdateGL(window);

pApp->SaveImage();
```

&nbsp;

So the buffer refines beautifully and nobody watches. It's the same gap as last post, where the threaded renderer showed nothing until it finished — the restructuring that makes live display possible keeps landing before the display does. For the measurements above I joined the threads, which is a change to my harness and not to the commit.

## Two functions waiting for the next post

`Sampler` ships with two mappings that nothing calls yet. The first takes the square of samples and warps it onto a disk, using Shirley's concentric mapping — sector arithmetic that keeps the points evenly spread rather than bunching them at the centre the way naive polar coordinates do. That's the right tool for the camera lens, and it would replace the rejection loop from post 2, which spins in a `while` until it happens to land inside the circle.

&nbsp;

The second maps them onto a hemisphere with a cosine power:

&nbsp;

```cpp
float cos_theta = pow((1.0f - m_vecSamples[i].y), 1.0f / (e + 1.0f));
float sin_theta = sqrt(1.0f - cos_theta * cos_theta);
```

&nbsp;

That `e` is the exponent that decides how tightly the directions cluster around the surface normal, and it is the whole machinery of importance sampling, sitting in the file a couple of commits before anything uses it.

&nbsp;

There's a bug waiting in the disk one:

&nbsp;

```cpp
m_vecDiskSamples.reserve(size);
...
m_vecDiskSamples[i].x = r * cos(phi);
```

&nbsp;

`reserve` sets capacity, not size — the vector is still empty, so those writes are out of bounds and `GetDiskSamples()` hands back nothing. The hemisphere function two definitions below gets it right with `push_back`. Nothing calls either yet, so it costs nothing today, and it's precisely the sort of thing that surfaces the moment the lens code is wired up.

## Where this leaves us

Samples are placed deliberately instead of randomly, the image refines instead of arriving, and there's a hemisphere mapping in the codebase looking for a use.

&nbsp;

---

**Commits:** [`ffc606d` — Added Samplers](https://github.com/TheOrestes/Windows_RayTracer/commit/ffc606d) · [`f8aea40` — Samplers, disk samples, hemisphere samples](https://github.com/TheOrestes/Windows_RayTracer/commit/f8aea40) · [`93d09c4` — Progressive rendering based on sample count](https://github.com/TheOrestes/Windows_RayTracer/commit/93d09c4)

&nbsp;

*Next up: pointing those hemisphere samples at the light, and the attempt that didn't work first.*
