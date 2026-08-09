+++
title = "Drawing a Ray Tracer With SetPixel (Yes, Really)"
date = 2026-08-08T00:00:00+05:30
tags = ["raytracing", "win32", "gdi", "cpp"]
description = "The first commit: a Win32 window, a message loop, and the slowest canvas Windows will sell you."
+++

Every ray tracer starts the same way: you need somewhere to put the pixels.

If you come from realtime rendering, this is the part your API has been quietly doing for you your whole life. You bind a swapchain, you clear a render target, you present. Somebody at Khronos or Microsoft solved "where do the pixels go" a long time ago and you have never had to think about it again.

This commit thinks about it. The answer it arrives at is `SetPixel()`, which is roughly the graphics equivalent of moving house by carrying one sock at a time.

![The ray tracer running in its Win32 window: three spheres and a ground plane, rendered one SetPixel call at a time. The heavy speckling is not a compression artifact — it is what one sample per pixel looks like](/images/blog/raytracer/gdi_first_render.jpg)

## First, the part where everything is backwards

Before the plumbing, the one idea you need if you have never written a ray tracer.

In the rasterization pipeline you know, geometry is the thing that moves. You take triangles, run them through a vertex shader, project them into screen space, and the hardware figures out which pixels each triangle lands on. Geometry is the loop. Pixels are the result.

Ray tracing runs that backwards. **Pixels are the loop.** For each pixel on screen, you fire a ray out into the world and ask what it hits. There is no projection matrix mapping triangles onto the screen, no rasterizer deciding coverage, no depth buffer resolving who won. There is a nested `for` loop over the framebuffer, and inside it, a geometry query.

That single inversion is the whole reason this file looks the way it does. The renderer does not need a GPU pipeline. It needs a 2D array it can write colors into, one at a time.

Which brings us to the crime scene.

## The window is a Visual Studio template with ambitions

`wWinMain`, `MyRegisterClass`, `InitInstance`, `WndProc`, and an `About` dialog box — this is the stock "Windows Desktop Application" template, unmodified, right down to the accelerator table nobody will ever press.

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

One wrinkle worth noting, because it will matter later. `CreateWindow` is being handed `gBackbufferWidth` and `gBackbufferHeight` — 480 and 270 — as the **window** size. Not the client area. A `WS_OVERLAPPEDWINDOW` includes a title bar and a border, and those eat into the total. So the actual drawable region is somewhat smaller than the 480×270 the renderer thinks it owns.

Nothing catches fire. The image just quietly doesn't fit.

## `WM_PAINT` is doing something it should not be doing

Here is the entire render trigger:

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

`Execute()` is the ray tracer. The *entire* ray tracer. It is being called from inside a paint message.

If you have done any Win32, you already know why this is funny. `WM_PAINT` fires whenever Windows decides a region of your window has become invalid — you dragged another window over it, you minimized and restored, you resized, you looked at it wrong. Each one of those is now a full re-render of the scene from scratch.

Also: the message loop is blocked for the entire duration. `GetMessage` cannot return until `DispatchMessage` finishes, and `DispatchMessage` cannot finish until every last ray has been traced. The window will not respond. Windows will offer to helpfully grey it out and ask if you would like to kill it.

That is a genuinely reasonable place to be on commit one, though. The render happens, and you see it. Everything else is optimization.

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

There is a surprising amount going on in twenty lines. Let's take it apart.

### Pixel to normalized coordinates

The camera does not want pixel indices, it wants a point on the image plane in $[0,1]$. So each pixel index gets divided by the resolution:

$$
u = \frac{i + \xi}{W}, \qquad v = \frac{j + \xi}{H}
$$

where $\xi \sim U[0,1)$ is `Helper::GetRandom01()`.

That $\xi$ is the interesting part. Without it, every ray for a given pixel would go through the *exact* same point, and you would get hard aliased edges — the ray tracing equivalent of `MSAA` being switched off. Jittering the sample within the pixel footprint and averaging is how you get antialiasing essentially for free.

Except right now:

```cpp
const int nSamples = 1;
```

One sample per pixel. So the jitter is applied, then averaged over a set of size one, which is a mathematically elaborate way of applying jitter. The antialiasing machinery is in place and doing nothing. The knob exists; it is turned to zero.

### Gamma, approximately

```cpp
color = Vector3(sqrt(color.x), sqrt(color.y), sqrt(color.z));
```

A square root on the way out. This is gamma correction, and it's worth being precise about why it's here.

The renderer accumulates light in **linear** space, because that is the only space where adding light makes physical sense — two lights of intensity $0.5$ really should sum to $1.0$. But display hardware is not linear. It expects values encoded with roughly

$$
c_{\text{encoded}} = c_{\text{linear}}^{1/2.2}
$$

Skip this step and everything renders muddy and too dark, because you handed linear values to a device expecting encoded ones. The code uses $c^{1/2}$ rather than $c^{1/2.2}$ — a square root is one instruction and $2.2$ is not — which is the standard cheap approximation. Slightly too bright, close enough, everybody does it.

### The 255.99 trick

```cpp
float ir = (255.99*color.x);
```

Not `255.0`. This is a small, load-bearing piece of folklore.

You have a float in $[0,1]$ and you want an integer in $[0,255]$. Multiply by $255$ and truncate, and the only input that ever produces $255$ is exactly $1.0$ — every other value in the top bucket rounds down to $254$. Your whites are dingy.

Multiply by $255.99$ and truncate instead, and the mapping

$$
\left\lfloor 255.99 \cdot c \right\rfloor
$$

distributes all $256$ buckets evenly across $[0,1]$. It is a hack. It is Peter Shirley's hack. It works.

### Why the coordinates are inside out

```cpp
SetPixel(hdc, gBackbufferWidth-i, gBackbufferHeight-j, RGB(ir, ig, ib));
```

Both axes are flipped: $x' = W - i$ and $y' = H - j$.

The $y$ flip is the classic one — GDI puts the origin at the **top**-left and counts down, while the camera's $v$ axis points up, so somebody has to invert. Every graphics programmer has written this line and every graphics programmer has written it the wrong way round at least once.

The $x$ flip is more of a choice. Combined, the two flips are a $180°$ rotation of the image.

### One sock at a time

```cpp
SetPixel(hdc, ...)
```

This is the part that hurts.

`SetPixel` is a GDI call that draws a single pixel to a device context. Not to a buffer you later blit — to the device context, right now. Every call goes through the GDI layer, does its own bounds checking and clipping, and touches the actual window surface.

At 480×270 that is

$$
480 \times 270 = 129{,}600
$$

individual GDI calls per frame, each carrying the full overhead of a Windows API call for the privilege of setting three bytes. And because there is no double buffering, you get to watch it happen — the image builds up line by line on screen like a JPEG on a 1998 dial-up connection.

Honestly? As a debugging experience this is fantastic. You can *see* where the renderer is slow, because you can see it crawl.

![The render filling in scanline by scanline, live, with no double buffering to hide it — 129,600 individual GDI calls arriving one at a time](/images/blog/raytracer/gdi_setpixel_crawl.gif)

## Timing, and a progress bar that isn't

```cpp
const clock_t begin_time = clock();
// ... render ...
const clock_t end_time = clock();
TotalRenderTime = (end_time - begin_time) / (double)CLOCKS_PER_SEC;
```

`clock()` around the render loop, result stashed in a global. This will become important later — you cannot optimize what you do not measure, and measuring is now technically possible.

Where it *goes*, however:

```cpp
//printf("Render Time : %.2f seconds\n", time);
```

Commented out. As is the progress display:

```cpp
percentageDone = (counter / (gBackbufferWidth*gBackbufferHeight)) * 100.0f;
//ShowProgress(percentageDone);
```

`ShowProgress` is fully implemented — it even calls `system("cls")` to clear the console between updates, which is its own special kind of choice — and then never gets called. `percentageDone` is dutifully computed every scanline and thrown away.

Also `int percentageDone = 0.0f;`, which initializes an `int` from a `float` literal. The compiler will allow this. The compiler allows a lot of things.

## Where this leaves us

A window that renders once per paint message, blocking the message pump, into a canvas that draws one pixel per API call, with no buffer anywhere in sight.

And yet: **it produces an image.** Spheres, reflections, refraction, depth of field, gamma correction — all of it, working, in commit one. The rendering is correct. Only the delivery mechanism is absurd.

That's the right order to get things wrong in.

---

**Commit:** [`24e60c1` — GDI based ray tracer, First commit](https://github.com/TheOrestes/Windows_RayTracer/commit/24e60c1)

*Next up: the vector, ray, and camera types this whole thing is built on — and why the sky is a lerp.*
