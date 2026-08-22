+++
title = "Every Thread Draws to the Same Window"
date = 2026-08-17T10:00:00+05:30
tags = ["raytracing", "multithreading", "cpp", "win32"]
description = "My first go at threading the renderer: std::thread, horizontal bands, and a measurement that did not go the way I expected."
+++

By this point the renderer worked. Camera, geometry, materials, recursion — the picture came out correct, and the only thing wrong with it was how long I had to wait.

&nbsp;

So I went after that, in two commits. This post is about both of them, and about what happened when I finally sat down and measured whether any of it helped.

## Getting the loop ready to be shared

The first commit is preparation. I lifted the pixel loop out of `Execute` and gave it its own function:

&nbsp;

```cpp
void Trace(HDC hdc, Camera cam, Hitable* world)
```

&nbsp;

Same loop, same body. What I wanted was a loop I could *call*, because you can't hand a chunk of work to a thread while it's still buried inside the function that sets everything up. Setup stayed in `Execute`, the work moved into `Trace`.

&nbsp;

I doubled the resolution in the same commit, $480 \times 270$ up to $960 \times 540$, which is four times the pixels — partly because I wanted a better picture, and partly because I wanted the render slow enough that any improvement would be obvious.

&nbsp;

I also taught `SaveImage` to count:

&nbsp;

```cpp
static int count = 0;
...
count++;
char buf[32] = { 0 };
sprintf(buf, "RenderImage%d.bmp", count);
```

&nbsp;

Which tells you exactly what I was doing at the time: rendering the same scene over and over, comparing the results, and getting tired of every run overwriting the last one.

## Cutting the image into bands

The second commit is the actual attempt. The strategy is the obvious one, and I still think it's the right starting point: the image is a grid of independent pixels, nothing reads anything another pixel wrote, so I can cut it into horizontal strips and hand one to each thread.

&nbsp;

```cpp
maxNumThreads = std::thread::hardware_concurrency();
```

&nbsp;

```cpp
int quarterHeight = gBackbufferHeight / maxNumThreads;
int startHeight = i * quarterHeight; 
int endHeight = (i + 1) * quarterHeight;
```

&nbsp;

Thread $i$ takes rows

&nbsp;

$$
\left[\; i \left\lfloor \frac{H}{T} \right\rfloor,\;\; (i+1)\left\lfloor \frac{H}{T} \right\rfloor \;\right]
$$

&nbsp;

and the variable is still called `quarterHeight` from when I had it hardcoded to four of them.

&nbsp;

![One band per thread. Two details I know about and plan to tidy up: the row loop is inclusive at both ends, so the row between two bands belongs to both of them, and `H / T` is integer division, so on a machine whose thread count doesn't divide the height the remainder at the bottom never gets assigned to anyone. Mine reports 16 threads, and 540 rows split sixteen ways leaves twelve](/images/blog/raytracer/thread_bands.svg)

&nbsp;

Spawning is as direct as it looks:

&nbsp;

```cpp
std::vector<std::thread*> ThreadGroup;
std::mutex threadMutex;

for (int i = 0; i < maxNumThreads; i++)
{
	std::thread* t = new std::thread(&ParallelTrace, &threadMutex, i);
	ThreadGroup.push_back(t);
}

std::vector<std::thread*>::iterator iter = ThreadGroup.begin();
for (; iter != ThreadGroup.end(); iter++)
{
	(*iter)->join();
}
```

&nbsp;

Spawn all, join all. No pool, no queue, no work stealing. For a render measured in seconds the cost of creating a dozen threads is noise, and I wanted the simplest thing that could possibly work.

&nbsp;

To let every thread see the scene I hoisted the camera and the world to file scope, and `TraceColor` stopped taking `world` as a parameter and started reading the global. Both are genuinely read-only for the duration of a render, so sharing them is safe — it's the easiest kind of state to share and I took the easy option.

&nbsp;

Then each thread starts like this:

&nbsp;

```cpp
threadMutex->lock();

int backBufferHeight = gBackbufferHeight;
int quarterHeight = gBackbufferHeight / maxNumThreads;
int startHeight = i * quarterHeight; 
int endHeight = (i + 1) * quarterHeight;
int ns = nSamples;
HDC hdc = GetDC(hWnd);

threadMutex->unlock();
```

&nbsp;

and spends the rest of its life doing this, a few hundred thousand times:

&nbsp;

```cpp
SetPixel(hdc, backBufferWidth - i, backBufferHeight- j, RGB(ir, ig, ib));
```

&nbsp;

There's a handful of things in here I already know need cleaning up: the lock only covers the setup, not the drawing; the `GetDC` never gets a matching `ReleaseDC`; and the `numRays` counter I added is a plain `unsigned long long` that every thread increments, so the total it reports is going to be low. None of them break the picture, and they're on the list. Hold that thought about the lock, though — it comes back.

## Then I measured it

I had bumped the sample count to 50 in the same commit, so the render was doing a lot more work than before:

&nbsp;

$$
960 \times 540 \times 50 = 25{,}920{,}000
$$

&nbsp;

primary rays a frame, each spawning more on every bounce. With the threads in, it finished in about eight and a half seconds, and I was pleased with that.

&nbsp;

What I hadn't done was check it against *not* threading. So I went back and did, properly: same commit, same scene, same resolution, same sample count, changing nothing but `maxNumThreads`. And because the amount of work per pixel is the interesting variable here, I swept it — 2, 4, 8, 16, 32 and 64 samples, each one measured both ways.

&nbsp;

![Sixteen threads is slower than one at every sample count I tried until the mid-forties, where the two finally cross. The gap closes steadily rather than suddenly, which is the shape you get when a fixed cost is being paid up front and the variable part is what's parallelising](/images/blog/raytracer/thread_sweep_chart.svg)

&nbsp;

| samples | 1 thread | 16 threads |
|---|---|---|
| 2 | 3.1s | 7.3s |
| 4 | 3.4s | 7.3s |
| 8 | 4.0s | 7.3s |
| 16 | 5.2s | 7.7s |
| 32 | 7.4s | 8.5s |
| 64 | 11.3s | 10.1s |

&nbsp;

Sixteen threads is *slower* than one thread across almost the whole range. At two samples per pixel it takes more than twice as long. The lines only cross somewhere around forty-five samples, and even at sixty-four the win is about twelve percent — for two and a half times the CPU.

&nbsp;

Fitting a line through each set makes it clearer what's going on:

&nbsp;

$$
t_{1} \approx 2.84 + 0.132\,n \qquad t_{16} \approx 7.2 + 0.045\,n
$$

&nbsp;

The per-sample cost drops from 0.132 to 0.045 seconds — so the tracing *is* parallelising, by about a factor of three. That part works. But the fixed cost, the part that doesn't care how many samples I take, goes from 2.8 seconds to 7.2. Threading made the constant term two and a half times worse, and at low sample counts the constant term is the whole render.

&nbsp;

That constant is the drawing. `SetPixel` gets called once per pixel no matter how many rays went into deciding its colour — 520,000 calls either way. And this is where the lock comes back, because the mutex in `ParallelTrace` unlocks before any of that happens. Sixteen threads are calling `SetPixel` on a device context for the same window, all at once, and GDI is not going to allow that — it takes its own lock internally. So the drawing is serialised regardless of what my mutex does, and now with sixteen threads queuing for it instead of one thread walking straight through.

&nbsp;

The tracing and the drawing are interleaved, one `SetPixel` at the bottom of every pixel's inner loop. So the threads aren't computing in parallel and then drawing in sequence — they're stopping to queue, several hundred thousand times each.

&nbsp;

<!-- VIDEO: side-by-side real-time capture, same commit and sample count, maxNumThreads = 1 on the left and 16 on the right. Left fills as one top-to-bottom sweep; right fills as sixteen bands at once. They finish at roughly the same moment. Recorded, awaiting upload — replace this with the YouTube link. Masters in blog-videos/multithreaded-raytracer/ -->

&nbsp;

*Video coming soon...*

&nbsp;

The shape of the progress is worth watching even so. Single-threaded it fills top to bottom in one steady sweep; threaded, all sixteen bands start at once and fill at visibly different rates depending on how much geometry each one contains.

## What I take from this

I'm glad I measured it, and I should have measured it before I assumed it had worked.

&nbsp;

The lesson isn't that threading doesn't work — the per-sample number says it works fine. It's that I parallelised the wrong scope. Handing each thread a band of the image was right; leaving the drawing inside the per-pixel loop meant every thread spent its time contending for a resource that can only ever be used by one of them at a time. Sixteen workers, one door.

&nbsp;

The fix is to stop drawing from inside the tracing loop: render into memory I own, where threads genuinely don't interact, and put the pixels on screen once at the end. That's a different shape of program, and it's what I go after next.

&nbsp;

---

**Commits:** [`0114729` — Prep for multi-threading](https://github.com/TheOrestes/Windows_RayTracer/commit/0114729) · [`7d1cdb1` — Basic Multithreading support using C++11 Threads](https://github.com/TheOrestes/Windows_RayTracer/commit/7d1cdb1)

&nbsp;

*Next up: getting the drawing out of the way — detached threads, no shared device context, and a scheduler that hands out work properly.*
