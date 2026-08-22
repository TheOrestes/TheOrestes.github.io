+++
title = "Drawing a Ray Tracer With SetPixel (Yes, Really)"
date = 2026-08-08T09:00:00+05:30
tags = ["raytracing", "win32", "gdi", "cpp"]
description = "Where I started: a Win32 window, a message loop, and the slowest canvas Windows will sell you."
+++

Every ray tracer starts the same way: you need somewhere to put the pixels.

&nbsp;

Coming from realtime rendering, this is the part my API had been quietly doing for me my whole career. Bind a swapchain, clear a render target, present. Somebody at Khronos or Microsoft solved "where do the pixels go" a long time ago and I had never once had to think about it.

&nbsp;

Writing my own tracer, I had to. What I reached for was `SetPixel()`, which is roughly the graphics equivalent of moving house by carrying one sock at a time.

![My first render, running in its Win32 window: three spheres and a ground plane, drawn one SetPixel call at a time. The heavy speckling is not a compression artifact — it is what one sample per pixel looks like](/images/blog/raytracer/gdi_first_render.jpg)

## First, the part where everything is backwards

Before the plumbing, the one idea worth having if you've never written a ray tracer.

&nbsp;

In the rasterization pipeline I knew, geometry is the thing that moves. You take triangles, run them through a vertex shader, project them into screen space, and the hardware figures out which pixels each triangle lands on. Geometry is the loop. Pixels are the result.

&nbsp;

Ray tracing runs that backwards. **Pixels are the loop.** For each pixel on screen, I fire a ray out into the world and ask what it hits. There's no projection matrix mapping triangles onto the screen, no rasterizer deciding coverage, no depth buffer resolving who won. There's a nested `for` loop over the framebuffer, and inside it, a geometry query.

&nbsp;

That single inversion is the whole reason this file looks the way it does. I didn't need a GPU pipeline. I needed a 2D array I could write colours into, one at a time.

&nbsp;

So that's what I went and got.

## The window is a Visual Studio template with ambitions

`wWinMain`, `MyRegisterClass`, `InitInstance`, `WndProc`, and an `About` dialog — this is the stock "Windows Desktop Application" template, unmodified, right down to the accelerator table nobody will ever press. I wanted a window on screen, not a Win32 education, so I took what the wizard gave me.

```cpp
BOOL InitInstance(HINSTANCE hInstance, int nCmdShow)
{
   hInst = hInstance; // Store instance handle in our global variable

   hWnd = CreateWindow (szWindowClass, szTitle, WS_OVERLAPPEDWINDOW,
      0, 0, gBackbufferWidth, gBackbufferHeight, nullptr, nullptr, hInstance, nullptr);

   if (!hWnd)
   {
      return FALSE;
   }

   ShowWindow(hWnd, nCmdShow);
   UpdateWindow(hWnd);

   return TRUE;
}
```

&nbsp;

One wrinkle I know about and haven't fixed yet: `CreateWindow` is being handed `gBackbufferWidth` and `gBackbufferHeight` — 480 and 270 — as the **window** size rather than the client area. A `WS_OVERLAPPEDWINDOW` includes a title bar and a border, and those eat into the total, so the drawable region is a bit smaller than the 480×270 the renderer thinks it owns. The right answer is `AdjustWindowRect`, and it's on my list.

&nbsp;

Nothing catches fire. The image just quietly doesn't fit.

## I put the whole renderer inside `WM_PAINT`

Here's the entire render trigger:

```cpp
case WM_PAINT:
    {
        PAINTSTRUCT ps;
        HDC hdc = BeginPaint(hWnd, &ps);

        Execute(hdc);

        OutputDebugString(L"This is paint!");

        EndPaint(hWnd, &ps);
    }
    break;
```

&nbsp;

`Execute()` is the ray tracer. The *entire* ray tracer, called from inside a paint message.

&nbsp;

If you've done any Win32 you can see where this goes. `WM_PAINT` fires whenever Windows decides a region of the window has become invalid — I dragged another window over it, minimized and restored, resized, looked at it wrong. Every one of those is a full re-render of the scene from scratch.

&nbsp;

And the message loop is blocked for the whole render. `GetMessage` can't return until `DispatchMessage` finishes, and `DispatchMessage` can't finish until the last ray is traced. The window doesn't respond, and Windows offers to grey it out and ask whether I'd like to kill it.

&nbsp;

I'm fine with that for a first commit. The render happens and I can see it, which is the only thing I needed on day one. Everything after this is making it better.

## The canvas, such as it is

`Execute()` walks the framebuffer:

```cpp
for (int j = 0; j <= gBackbufferHeight; j++)
{
    for (int i = 0; i <= gBackbufferWidth; i++)
    {
        Vector3 color(0, 0, 0);

        for (int s = 0; s < nSamples; s++)
        {
            float u = float(i + Helper::GetRandom01()) / float(gBackbufferWidth);
            float v = float(j + Helper::GetRandom01()) / float(gBackbufferHeight);

            Ray r = cam.get_ray(u, v);

            color = color + TraceColor(r, world, 0);
        }

        color = color / float(nSamples);
        color = Vector3(sqrt(color.x), sqrt(color.y), sqrt(color.z));

        float ir = (255.99*color.x);
        float ig = (255.99*color.y);
        float ib = (255.99*color.z);

        SetPixel(hdc, gBackbufferWidth-i, gBackbufferHeight-j, RGB(ir, ig, ib));
        ++counter;
    }
}
```

&nbsp;

There's a surprising amount going on in twenty lines. Let me take it apart.

### Pixel to normalized coordinates

The camera doesn't want pixel indices, it wants a point on the image plane in $[0,1]$. So each pixel index gets divided by the resolution:

&nbsp;

$$
u = \frac{i + \xi}{W}, \qquad v = \frac{j + \xi}{H}
$$

&nbsp;

where $\xi \sim U[0,1)$ is `Helper::GetRandom01()`.

&nbsp;

That $\xi$ is the interesting part. Without it, every ray for a given pixel would go through the *exact* same point and I'd get hard aliased edges — the ray tracing equivalent of `MSAA` switched off. Jittering the sample within the pixel footprint and averaging is how you get antialiasing essentially for free.

&nbsp;

Except right now:

```cpp
const int nSamples = 1;
```

&nbsp;

One sample per pixel. The jitter is applied and then averaged over a set of size one, which is a mathematically elaborate way of applying jitter. The machinery is in place and turned all the way down — deliberately, because I wanted to see a picture quickly and I knew where the knob was.

### Gamma, approximately

```cpp
color = Vector3(sqrt(color.x), sqrt(color.y), sqrt(color.z));
```

&nbsp;

A square root on the way out. This is gamma correction, and it's worth being precise about why it's there.

&nbsp;

The renderer accumulates light in **linear** space, because that's the only space where adding light makes physical sense — two lights of intensity $0.5$ really should sum to $1.0$. Display hardware isn't linear. It expects values encoded with roughly

&nbsp;

$$
c_{\text{encoded}} = c_{\text{linear}}^{1/2.2}
$$

&nbsp;

Skip this and everything renders muddy and too dark, because you've handed linear values to a device expecting encoded ones. I used $c^{1/2}$ rather than $c^{1/2.2}$ — a square root is one instruction and $2.2$ is not — which is the standard cheap approximation. Slightly too bright, close enough, everybody does it.

### The 255.99 trick

```cpp
float ir = (255.99*color.x);
```

&nbsp;

Not `255.0`. This is a small, load-bearing piece of folklore.

&nbsp;

You have a float in $[0,1]$ and you want an integer in $[0,255]$. Multiply by $255$ and truncate, and the only input that ever produces $255$ is exactly $1.0$ — every other value in the top bucket rounds down to $254$. Your whites come out dingy.

&nbsp;

Multiply by $255.99$ and truncate instead, and the mapping

&nbsp;

$$
\left\lfloor 255.99 \cdot c \right\rfloor
$$

&nbsp;

distributes all $256$ buckets evenly across $[0,1]$. It's a hack. It's Peter Shirley's hack. It works.

### Why the coordinates are inside out

```cpp
SetPixel(hdc, gBackbufferWidth-i, gBackbufferHeight-j, RGB(ir, ig, ib));
```

&nbsp;

Both axes are flipped: $x' = W - i$ and $y' = H - j$.

&nbsp;

The $y$ flip is the classic one — GDI puts the origin at the **top**-left and counts down, while the camera's $v$ axis points up, so something has to invert. Every graphics programmer has written this line, and written it the wrong way round at least once.

&nbsp;

The $x$ flip is more of a choice. Together the two flips are a $180°$ rotation of the image.

### One sock at a time

```cpp
SetPixel(hdc, ...)
```

&nbsp;

This is the part that hurts.

&nbsp;

`SetPixel` is a GDI call that draws a single pixel to a device context. Not to a buffer I later blit — to the device context, right now. Every call goes through the GDI layer, does its own bounds checking and clipping, and touches the actual window surface.

&nbsp;

At 480×270 that's

&nbsp;

$$
480 \times 270 = 129{,}600
$$

&nbsp;

individual GDI calls per frame, each carrying the full overhead of a Windows API call for the privilege of setting three bytes. And with no double buffering, I get to watch it happen — the image builds line by line on screen like a JPEG on a 1998 dial-up connection.

&nbsp;

Honestly? As a debugging experience it's fantastic. I can *see* where the renderer is slow, because I can watch it crawl.

![The render filling in scanline by scanline, live, with no double buffering to hide it — 129,600 individual GDI calls arriving one at a time](/images/blog/raytracer/gdi_setpixel_crawl.gif)

## Timing, and a progress bar that isn't

```cpp
const clock_t begin_time = clock();
// ... render ...
const clock_t end_time = clock();
TotalRenderTime = (end_time - begin_time) / (double)CLOCKS_PER_SEC;
```

&nbsp;

`clock()` around the render loop, result stashed in a global. This matters more than it looks — I can't optimize what I don't measure, and measuring is now at least possible.

&nbsp;

Where it *goes*, though:

```cpp
//printf("Render Time : %.2f seconds\n", time);
```

&nbsp;

Commented out, along with the progress display:

```cpp
percentageDone = (counter / (gBackbufferWidth*gBackbufferHeight)) * 100.0f;
//ShowProgress(percentageDone);
```

&nbsp;

`ShowProgress` is fully written — it even calls `system("cls")` to clear the console between updates — and then never called, while `percentageDone` gets computed every scanline and thrown away. I think I wrote it, watched the image crawl down the window, and realised the render was already its own progress bar. There's also an `int percentageDone = 0.0f;` in there initializing an int from a float literal, which I'll tidy up when I next touch this function.

## Where this leaves us

A window that renders once per paint message, blocking the message pump, into a canvas that draws one pixel per API call, with no buffer anywhere in sight.

&nbsp;

And yet: **it produces an image.** Spheres, reflections, refraction, depth of field, gamma correction — all of it working, in the first commit. The rendering is correct. It's only the delivery that's absurd.

&nbsp;

Which is the right order to get things wrong in. Correct and slow is a problem I know how to work on.

---

**Commit:** [`24e60c1` — GDI based ray tracer, First commit](https://github.com/TheOrestes/Windows_RayTracer/commit/24e60c1)

&nbsp;

*Next up: the vector, ray, and camera types this whole thing is built on — and why the sky is a lerp.*
