+++
title = "Getting the Drawing Out of the Way"
date = 2026-08-17T00:00:00+05:30
tags = ["raytracing", "multithreading", "performance", "cpp"]
description = "Three commits that stop the renderer drawing from inside the tracing loop — and the second bottleneck I only found by measuring."
+++

Last post ended with a diagnosis I was fairly pleased with and slightly annoyed by: sixteen threads, five percent faster, because every one of them was queueing behind GDI to draw a pixel at a time. The tracing parallelised beautifully. The drawing didn't parallelise at all, and I'd put the two in the same loop.

&nbsp;

This post is the fix. It took three commits, and measuring it turned up a second bottleneck I hadn't suspected.

&nbsp;

One note before the code. The series follows themes rather than dates, so by this point the renderer has been reorganised into an `Application` class and, on the OpenGL branch, draws through a screen-aligned quad instead of GDI. Both of those get their own posts later. Here I only care about the threading.

## Stop passing the device context around

`55d3021` is a small commit with a clear intent — the message is "Removing dependency on passing HDC":

&nbsp;

```cpp
-void Application::Execute(HDC _hdc)
+void Application::Execute()
```

&nbsp;

The device context stops being a parameter. It had been threaded through the renderer's API from the window all the way down to the pixel loop, which meant every layer of the thing knew it was drawing to a Win32 window. Cutting it from the signature is the first move toward the renderer not caring where its output goes.

&nbsp;

There's a commented-out block in the same commit that tells you where my head was:

&nbsp;

```cpp
//while (msg.message != WM_QUIT)
//{
//	if (PeekMessage(&msg, NULL, 0U, 0U, PM_REMOVE))
//	{
//		TranslateMessage(&msg);
//		DispatchMessage(&msg);
//	}
//	else
//	{
//		pApp->Execute();
//	}
//}
```

&nbsp;

That's the game loop shape — pump messages if there are any, otherwise render — instead of rendering inside `WM_PAINT`. I didn't switch to it here, but I'd clearly started thinking about the render as something that happens continuously rather than something Windows asks for.

## Write to memory instead

`c36fae0` is the one that matters, and the commit message says it plainly: "Fixed multithreaded rendering by deteaching thread execution."

&nbsp;

The threads now write here:

&nbsp;

```cpp
vecBuffer[j * endWidth + i] = color;
```

&nbsp;

A `std::vector<glm::vec3>`, indexed by pixel. No device context, no GDI, no API call — a store to memory that each thread reaches on its own rows and nobody else touches.

&nbsp;

Which means all of this can go:

&nbsp;

```cpp
-	threadMutex->lock();
+	//threadMutex->lock();
...
-				threadMutex->lock();
+				//threadMutex->lock();
 				vecBuffer[j * endWidth + i] = color;
-				threadMutex->unlock();
+				//threadMutex->unlock();
```

&nbsp;

Every lock in `ParallelTrace`, commented out. That looks alarming written down and it's correct: the bands partition the image, so thread $i$ writes rows no other thread writes. There's nothing to protect. The lock in the previous version was guarding a copy of some integers, which was never the risk, and the thing that *was* shared has stopped being shared.

&nbsp;

Then the join becomes a detach:

&nbsp;

```cpp
-			//if((*iter)->joinable())
-			(*iter)->join();
+			(*iter)->detach();
```

&nbsp;

`Trace` now returns immediately while the workers carry on filling the buffer, and the display loop draws whatever is in it each frame. That's progressive display arriving as a side effect — I get to watch the image resolve without writing anything to make that happen.

&nbsp;

Those two changes turn out to be load-bearing together, which I only worked out by trying to reproduce this on the older commit and crashing instantly. The mutex is a local variable inside `Trace`. With `join()` it outlives the workers, because `Trace` sits there waiting for them. Detach them and `Trace` returns straight away, destroying the mutex while sixteen threads are still calling `lock()` through a pointer to it.

&nbsp;

So dropping the locks isn't tidying that happens to share a commit with the detach — detaching without dropping them doesn't run at all. I doubt I reasoned it out in that order at the time. More likely I detached the threads, watched it fall over, and took the locks out because they were the obvious thing in the way.

&nbsp;

Two smaller things in the same commit. A `copyBuffer` that had been duplicating the entire framebuffer every frame is gone. And debug builds drop to a single thread:

&nbsp;

```cpp
#ifdef NDEBUG
	pApp->Initialize(true);
#else
	pApp->Initialize(false);
#endif
```

&nbsp;

which is one of those changes that costs nothing and saves an hour the first time you step through a render.

## So did it work?

I could have taken my own word for it. Instead I ran post 5's sweep again, on post 5's commit, changing exactly one thing: where the pixel lands. `SetPixel` into the device context becomes a write into a `std::vector`, plus a single `SetDIBitsToDevice` once every thread has joined. Same scene, same bands, same thread counts, same sample counts.

&nbsp;

![Four configurations of the same commit. With `SetPixel`, one thread and sixteen threads sit almost on top of each other — that was last post. Writing into a buffer instead drops both lines and, more importantly, separates them: sixteen threads finally beats one by a real margin at every sample count](/images/blog/raytracer/buffer_vs_setpixel_chart.svg)

&nbsp;

| samples | `SetPixel` 16t | buffer 16t | buffer 1t |
|---|---|---|---|
| 2 | 7.3s | 0.3s | 0.4s |
| 8 | 7.3s | 0.5s | 1.2s |
| 32 | 8.5s | 1.7s | 4.2s |
| 64 | 10.1s | 3.5s | 8.5s |

&nbsp;

At 64 samples that's 10.1 seconds down to 3.5, and sixteen threads are now genuinely ahead of one — about 2.4× rather than the 1.1× I measured last time. One line moved, and the parallelism I thought I'd written in the previous commit actually showed up.

## The one I hadn't spotted

Except look at the CPU time. At 64 samples the sixteen-thread run burned **33.1 seconds of CPU** to do work that costs **8.4 seconds** on one thread. Four times the total work for a 2.4× speedup. Something was still eating cores.

&nbsp;

It was this, from `TraceColor`:

&nbsp;

```cpp
++numRays;
```

&nbsp;

One `unsigned long long` at file scope, incremented once per ray by every thread. I mentioned it in the last post as something I knew about and would tidy up, and I filed it as a correctness wart — the count comes out low because increments get lost. What I hadn't thought about is what sixteen cores hammering one cache line does to everything *else*. Every increment pulls that line away from fifteen other cores, and they all stall waiting to pull it back.

&nbsp;

Commenting out that single line, changing nothing else:

&nbsp;

| at 64 samples, 16 threads | wall | CPU |
|---|---|---|
| `SetPixel`, shared counter | 10.1s | — |
| buffer, shared counter | 3.5s | 33.1s |
| buffer, no shared counter | **1.5s** | **13.1s** |

&nbsp;

Twenty seconds of CPU were going into contention over a statistic. The render is now 5.7× faster than a single thread, and CPU is 1.6× the single-threaded cost rather than 4×, which is about what I'd expect from real parallel work.

&nbsp;

The satisfying part is that the actual commits already do the right thing here. `ParallelTrace` keeps a plain local `int rayCount`, and adds it once at the end:

&nbsp;

```cpp
m_iRayCount += rayCount;
```

&nbsp;

One atomic add per thread per render instead of one per ray. I don't think I reasoned my way to that — it reads more like something I tidied because it was neater — but it's the same fix, and it's worth a lot more than tidiness.

## A real scheduler

`a911dbe` is a big commit that does several unrelated things — projections, HDRI, the denoiser. The part that belongs here is that it adds [marl](https://github.com/google/marl), a task scheduler, as a second implementation sitting beside the threads:

&nbsp;

```cpp
#define CPLUSPLUS_THREADING 1
//#define MARL_SCHEDULING 1
```

&nbsp;

Two switches, one active, both kept. And the marl path is shaped quite differently:

&nbsp;

```cpp
marl::Scheduler scheduler;
scheduler.setWorkerThreadCount(marl::Thread::numLogicalCPUs());
scheduler.bind();
defer(scheduler.unbind());

marl::WaitGroup wg(m_iBackbufferHeight);

for (uint32_t y = 0; y < m_iBackbufferHeight; y++)
{
	marl::schedule([=] {
		defer(wg.done());

		for (uint32_t x = 0; x < m_iBackbufferWidth; x++)
		{
			RenderPixel(y, x);
		}
	});
}

wg.wait();
```

&nbsp;

The important difference isn't the library. It's the granularity. My own version cuts the image into as many bands as there are cores and hands each thread one — so a thread that draws the empty sky finishes early and then does nothing, while the thread holding the glass sphere is still going. Post 5's video shows exactly that: sixteen bands filling at visibly different rates.

&nbsp;

Marl gets **one task per row**, 540 of them, against a pool of workers. A worker that finishes a cheap row immediately takes another. The work finds the idle cores instead of being assigned up front and hoping.

&nbsp;

![The same total work, distributed two ways. On the left my version: five bands handed out before anyone knows what they cost, so the thread holding the cheap sky finishes and then sits there while the thread holding the glass grinds on. On the right the scheduler's version: many small tasks and a pool of workers, where finishing early just means picking up the next row](/images/blog/raytracer/bands_vs_tasks.svg)

&nbsp;

That also needed a smaller unit of work, which is why `RenderPixel(row, column)` gets extracted in the same commit — a function that renders exactly one pixel, so a task can be as small as I want.

&nbsp;

I left both implementations in. Partly because I wanted to compare them, and partly because a dependency you can `#define` away is easier to justify than one you can't.

## Where this leaves us

At 64 samples per pixel, the same scene went from 10.1 seconds to 1.5. Neither change was clever: stop drawing from inside the tracing loop, and stop sharing a counter between sixteen threads. Both are one line.

&nbsp;

What I take from it is that I couldn't have found either by reading the code. The threads looked right. They *were* right. Everything that was wrong lived in what the inner loop touched, and the only way that showed up was putting a number on it.

&nbsp;

---

**Commits:** [`55d3021` — Removing dependency on passing HDC](https://github.com/TheOrestes/Windows_RayTracer/commit/55d3021) · [`c36fae0` — Fixed multithreaded rendering by detaching thread execution](https://github.com/TheOrestes/Windows_RayTracer/commit/c36fae0) · [`a911dbe` — Added Marl Scheduler (Optional)](https://github.com/TheOrestes/Windows_RayTracer/commit/a911dbe)

&nbsp;

*Next up: triangles — and the moment a sphere stops being enough.*
