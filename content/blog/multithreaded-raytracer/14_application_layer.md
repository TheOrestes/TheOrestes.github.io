+++
title = "Everything That Wasn't Windows"
date = 2026-08-20T00:00:00+05:30
tags = ["raytracing", "architecture", "threading", "cpp"]
description = "Lifting the renderer out of the Win32 template it grew inside, and giving the ray counter somewhere to live that sixteen threads don't fight over."
+++

The last two posts have been full of `Application::Execute` and `Application::TraceColor` and `m_iRayCount`. This commit is where that class came from.

&nbsp;

Before it, there was no application layer. `WindowsRayTracer.cpp` — the file Visual Studio generates when you ask for a Win32 desktop app — was 534 lines, and the ray tracer lived inside it.

## The slab

Everything sat in a region marked off with a pragma:

&nbsp;

```cpp
#pragma region RayTracer

const int gBackbufferWidth = 480;
const int gBackbufferHeight = 270;
const int nSamples = 1;

unsigned long long int numRays = 0;

int maxNumThreads = 0;
double TotalRenderTime = 0;

Camera* gCam = nullptr;
```

&nbsp;

Then free functions — `TraceColor`, `Trace`, `ParallelTrace`, `Execute`, `SaveImage`, `ShowProgress` — reading and writing those globals, all sandwiched between the window class registration and the message pump.

&nbsp;

It worked. Posts 1 through 12 were all built on it, and for a project of one file's worth of ideas it was fine. What made it stop being fine is that there were now two subjects in the file and no line between them. Resolution belonged to the renderer, `hWnd` belonged to Windows, and both were globals two feet apart.

&nbsp;

This commit draws the line. `WindowsRayTracer.cpp` goes from 534 lines to 215, and `Application.cpp` and `Application.h` arrive with 314 between them. The Win32 file keeps registering the window class, creating the window, pumping messages and dispatching menu commands. It keeps nothing else.

## Globals become members

The mechanical part is a rename, but it's worth seeing what the renames encode:

&nbsp;

| was | becomes |
|---|---|
| `gBackbufferWidth`, `gBackbufferHeight` | `m_iBackbufferWidth`, `m_iBackbufferHeight` |
| `nSamples` | `m_iNumSamples` |
| `maxNumThreads` | `m_iMaxThreads` |
| `numRays` | `m_iRayCount` |
| `TotalRenderTime` | `m_dTotalRenderTime` |
| `gCam` | `m_pCamera` |

&nbsp;

Every one of those was reachable from any line of the file. Now they're reachable from one class, and `WindowsRayTracer.cpp` can only ask through the handful of methods that are public:

&nbsp;

```cpp
void			Initialize(HWND hwnd, bool _threaded);
void			Execute(HDC _hdc);
void			SaveImage();

inline int		GetBufferWidth() { return m_iBackbufferWidth; }
inline int		GetBufferHeight() { return m_iBackbufferHeight; }
inline double	GetTotalRenderTime() { return m_dTotalRenderTime; }
```

&nbsp;

Which immediately pays off at the window creation, where the size of the render now comes from the thing that does the rendering:

&nbsp;

```cpp
-   RECT rect = { 0,0,gBackbufferWidth,gBackbufferHeight };
+   RECT rect = { 0, 0, pApp->GetBufferWidth(), pApp->GetBufferHeight() };
```

&nbsp;

The other thing that disappears is a compile-time switch:

&nbsp;

```cpp
-#if defined C11_THREADS
-	maxNumThreads = std::thread::hardware_concurrency();
-#elif defined ENKITS
-	maxNumThreads = 4;
-#endif
```

&nbsp;

That was choosing a threading backend with the preprocessor — a decision baked at build time, with the alternative branch never compiled and free to rot. It becomes an argument:

&nbsp;

```cpp
void Application::Initialize(HWND hwnd, bool _threaded)
{
	m_bThreaded = _threaded;
	m_hWnd = hwnd;

	_threaded ? m_iMaxThreads = std::thread::hardware_concurrency() : 0;
	...
```

&nbsp;

Threaded or not is now a runtime flag, and `Trace()` branches on it. Both paths compile, so both keep working.

## Where the ray counter went

The more interesting half of the commit. The old counter was this:

&nbsp;

```cpp
unsigned long long int numRays = 0;
...
glm::vec3 TraceColor(const Ray& r, int depth)
{
	HitRecord rec;

	++numRays;
```

&nbsp;

One global, incremented once per ray, from every thread. Post 6 is where I measured what that costs: at 64 samples the same frame took 3.5 seconds with the shared counter and 1.5 without it. More than half the render time was sixteen cores queuing to add one to the same integer.

&nbsp;

The new version counts locally and reports once:

&nbsp;

```cpp
void Application::ParallelTrace(std::mutex * threadMutex, int i)
{
	...
	int rayCount = 0;
	...
	m_iRayCount += rayCount;
}
```

&nbsp;

`rayCount` is a plain `int` on the thread's own stack — no sharing, no cache line bouncing between cores. `m_iRayCount` is `std::atomic<int>`, touched once per thread per frame instead of once per ray. Sixteen atomic operations for a whole render, against several million.

&nbsp;

The cost is that `rayCount` has to reach the places where rays are actually created, and those are the materials. So it goes into the signature:

&nbsp;

```cpp
-	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, glm::vec3& attenuation, Ray& scattered) const = 0;
+	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& attenuation, Ray& scattered) const = 0;
```

&nbsp;

Every material changes to match, and so does `Scene::Trace`. A debug counter is now part of the material interface — the thing every future material will have to accept whether or not it cares.

&nbsp;

It's the right trade at this point, because the alternative was measured and it was slow. And it's the version of this problem that gets solved properly a week later: post 13's commits hang the counters off `HitRecord` instead, which was already being passed into every one of those functions. Same locality, same single atomic add, no new parameters. I like that the good answer was already sitting in the argument list.

## FlatColor, and a ray that means stop

The commit also adds a third material:

&nbsp;

```cpp
bool FlatColor::Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& attenuation, Ray& scatterd) const
{
	// Ray origin & Direction both are same, which means no further bounces
	// and processing of rays, useful for flat colors...!
	scatterd = Ray(rec.P, rec.P);

	attenuation = Albedo->value(rec.uv);
	return true;
}
```

&nbsp;

A surface that shows its texture and nothing else — no lighting, no bounce. Useful for checking that a model's UVs are right without the answer being confused by everything else in the scene, which is exactly what post 10 needed.

&nbsp;

The way it stops the recursion is the part worth pausing on. `Scatter` has to return `true` or the caller treats the surface as absorbing all light and returns black. So it returns true with a ray whose origin and direction are the same point, and `TraceColor` looks for that:

&nbsp;

```cpp
if (glm::distance(scatteredRay.GetRayOrigin(), scatteredRay.GetRayDirection()) < 0.0000001f)
	return attenuation;
else
	return attenuation * TraceColor(scatteredRay, depth + 1, rayCount);
```

&nbsp;

**A correction to post 12.** I flagged that line there as comparing a point against a vector and concluded that whatever it was meant to catch, it wasn't catching it. That was wrong. It catches this, deliberately — `FlatColor` sets both to `rec.P` so the distance is zero, and the comment above it says so. The material signals "don't bounce" by handing back a degenerate ray, and this is the receiving end.

&nbsp;

It's still a flag smuggled through geometry rather than sent as a flag, and it's fragile in the way sentinels are: any material that happened to produce a scattered ray whose direction landed near its origin would stop early by accident. A `bool` on the way out would say the same thing without the coincidence. `FlatColor` and, as the commit message for its removal puts it, the *"temporary fixes related to it"* both come out of the renderer later on.

## What it looks like

The visible result of the commit is in the caption:

&nbsp;

![The window at 849e03f. Title bar from the new `Application::Execute`; the File menu still holds Render Time, which post 13's commits replace with a Profiler popup](/images/blog/raytracer/app_layer_window.png)

&nbsp;

```cpp
swprintf(buffer, L"[Time : %0.2f seconds!] [Ray Count : %d rays]", m_dTotalRenderTime, rayCount);
SetWindowText(m_hWnd, buffer);
```

&nbsp;

7,640,906 rays for that frame at 640 × 480 and 8 samples. It's the first number this renderer ever reported about itself, and everything in post 13 grew out of wanting more of them.

## Rough edges I know about

Two, both in the new class, both harmless today.

&nbsp;

```cpp
Application::~Application()
{
	delete m_pCamera;
}
```

&nbsp;

`m_pCamera` points at `Camera::getInstance()`, which is a function-local static:

&nbsp;

```cpp
static Camera& getInstance()
{
	static Camera instance;
	return instance;
}
```

&nbsp;

So that's `delete` on something that was never allocated with `new`. It doesn't bite because the destructor never runs — the process exits with the `Application` still alive — but it's a crash waiting for the day something tidies up properly. The camera stops being a singleton a few commits later, which is the real fix.

&nbsp;

And `m_iMaxThreads` isn't initialised in the constructor. It only gets a value when `Initialize` is called with `_threaded` true, so in single-threaded mode it holds whatever was on the stack. Nothing reads it on that path, so nothing goes wrong — but the ternary that sets it is an `if` wearing a disguise, and writing it as an `if` with an `else` would have made the gap obvious.

## Where this leaves us

The renderer is a class. The Win32 file is a Win32 file. Two things that were tangled in one translation unit now have a border, and the border is six public methods wide.

&nbsp;

What hasn't changed at all is *when* any of it runs:

&nbsp;

```cpp
case WM_PAINT:
{
	PAINTSTRUCT ps;
	HDC hdc = BeginPaint(hWnd, &ps);

	pApp->Execute(hdc);
```

&nbsp;

Post 1 opened with the whole renderer inside `WM_PAINT`, blocking the message pump until the last pixel was down. It's still inside `WM_PAINT`. All that moved is which file the code is written in — which is worth doing on its own, and is nowhere near the end of that story.

&nbsp;

---

**Commit:** [`849e03f` — Added Application Layer, Ray Counter, FlatColor material](https://github.com/TheOrestes/Windows_RayTracer/commit/849e03f)

&nbsp;

*Next up: the window finally stops being drawn one pixel at a time.*
