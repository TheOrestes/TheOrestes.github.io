+++
title = "Fixed SPP, Render Timing, and a Bounce Heatmap"
date = 2026-01-04T18:03:00+05:30
tags = ["cuda", "rendering", "raytracing", "opengl"]
description = "Fixed SPP, Render Timing, and a Bounce Heatmap."
math = true
+++

This follow-up update is all about making the progressive renderer a bit more self-aware: it now stops accumulating at a fixed sample target, reports how fast it is converging, and can switch into a bounce-count heatmap for debugging. The changes are small in surface area, but they make the render loop much more explicit about what it is doing.

&nbsp;

{{< youtube 5izVecfYNDA >}}

## `frameCount` becomes `currentSPP`

The first cleanup is a rename that actually matters. What used to be called `frameCount` is now `currentSPP`, which is a much more honest name for a variable that represents the current *samples per pixel* count.

&nbsp;

So instead of the renderer conceptually saying, “here is frame number \(n\),” it now says:

$$
\text{currentSPP} = n
$$

That value is threaded all the way through the pipeline:

- the main render loop,
- the CUDA launch wrapper,
- the `RayTracer(...)` kernel,
- the RNG seed setup via `curand_init(...)`,
- and the accumulation blend step.

The accumulation math itself does not change, but the naming now matches the algorithm. The running average still behaves like:

$$
C_n = C_{n-1} + \frac{S_n - C_{n-1}}{n}
$$

where \(C_n\) is the accumulated pixel color after \(n\) samples, and \(S_n\) is the newly traced sample. Same equation, fewer identity issues.

## Accumulation now has a finish line

Before this change, the render loop kept launching the kernel every frame. Now it has an explicit target:

$$
\text{targetSPP} = 100
$$

Two new globals drive this behavior:

- `currentSPP`
- `accumulationComplete`

The key addition is this little gatekeeper:

```cpp
bool accumulationComplete = false;
int currentSPP = 0;
constexpr int targetSPP = 100;
```

And in the main loop:

```cpp
if (cameraMoved)
{
    currentSPP = 0;
    accumulationComplete = false;
    cudaMemset(gAccumulationBuffer, 0, bufferSize);
}

if(!accumulationComplete)
{
    ++currentSPP;
    RunRayTracingKernel(fbCudaResource, width, height, gCamera,
        gAccumulationBuffer, currentSPP, dSceneObject, gNumObjects, dMaterial);

    if (currentSPP % (targetSPP / 10) == 0)
    {
        const float progress = static_cast<float>(currentSPP) / targetSPP * 100.0f;
        std::cout << "Progress: " << currentSPP << "/" << targetSPP
                  << " SPP (" << std::fixed << std::setprecision(1)
                  << progress << "%)\r";
    }

    if (currentSPP >= targetSPP)
    {
        accumulationComplete = true;
        std::cout << "Accumulation complete! (" << currentSPP << " SPP)\n";
    }
}
```

In plain English, the renderer keeps sampling until

$$
\text{currentSPP} \geq \text{targetSPP}
$$

and then it stops.

&nbsp;

That means once the image reaches 100 SPP, the GPU is no longer asked to keep re-solving the same already-converged frame. Which is nice. Even path tracers deserve boundaries.

If the camera moves, accumulation is reset immediately:

$$
\text{currentSPP} \leftarrow 0
$$

and the accumulation buffer is cleared with `cudaMemset(...)`. So the renderer starts a fresh convergence pass instead of blending new samples with stale ones from the previous view.

## Progress reporting grows up

The next change adds timing and progress output to the accumulation process. Two variables are introduced:

- `accumulationStartTime`
- `totalRenderTime`

The timer is reset when the camera moves, and also initialized on the first sample of a fresh accumulation pass.

```cpp
float accumulationStartTime = 0.0f;
float totalRenderTime = 0.0f;
```

```cpp
if (cameraMoved)
{
    currentSPP = 0;
    accumulationComplete = false;
    accumulationStartTime = currentTime;// reset timer!
    cudaMemset(gAccumulationBuffer, 0, bufferSize);
}

if(!accumulationComplete)
{
    if(currentSPP == 0)
    {
        accumulationStartTime = currentTime;
    }

    ++currentSPP;
    RunRayTracingKernel(...);
```

Every 10% of the target SPP, the renderer now prints a much more useful progress line. The displayed progress is computed as:

$$
\text{progress} = \frac{\text{currentSPP}}{\text{targetSPP}} \times 100
$$

and the throughput is reported as:

$$
\text{SPP/s} = \frac{\text{currentSPP}}{\text{totalRenderTime}}
$$

The console code now looks like this:

```cpp
if (currentSPP % (targetSPP / 10) == 0)
{
    totalRenderTime = currentTime - accumulationStartTime;

    const float progress = static_cast<float>(currentSPP) / targetSPP * 100.0f;
    const float sppPerSecond = static_cast<float>(currentSPP) / totalRenderTime;

    std::cout << "Progress: " << currentSPP << "/" << targetSPP
              << " SPP (" << std::fixed << std::setprecision(1)
              << progress << "%) - "
              << totalRenderTime << "s - "
              << std::setprecision(2) << sppPerSecond << " SPP/s"
              << '\n';
}
```

So the console output now includes:

- current SPP,
- percentage complete,
- elapsed time,
- and average samples per second.

At completion, the code also prints a formatted summary showing total SPP, total render time, and average SPP/s. In other words, the renderer has gone from “trust me bro” to at least showing its working.

## `H` toggles a heatmap mode

The third change introduces a debug visualization mode controlled by the keyboard. Pressing `H` toggles `showHeatmap`, prints the current state, and resets accumulation so the mode switch is visible immediately.

&nbsp;

The new flag is introduced here:

```cpp
bool showHeatmap = false;
```

And the keyboard handler gets this new toggle path:

```cpp
if (key == GLFW_KEY_H && action == GLFW_PRESS)
{
    showHeatmap = !showHeatmap;
    std::cout << "Heatmap mode: " << (showHeatmap ? "ON" : "OFF") << '\n';

    currentSPP = 0;
    accumulationComplete = false;

    constexpr size_t bufferSize = width * height * sizeof(float4);
    cudaMemset(gAccumulationBuffer, 0, bufferSize);
}
```

That reset is important because the visualization mode changes what the renderer writes per pixel, so accumulation needs to restart from a clean state instead of blending two different worlds together like a multiverse bug report.

## 5. The kernel can now visualize actual bounce count

The heatmap flag is passed from the main loop into `RunRayTracingKernel(...)`, then into the `RayTracer(...)` kernel itself.

```cpp
- RunRayTracingKernel(..., dMaterial);
+ RunRayTracingKernel(..., dMaterial, showHeatmap);
```

```cpp
- __global__ void RayTracer(..., RT::Material* pMaterials)
+ __global__ void RayTracer(..., RT::Material* pMaterials, bool showHeatmap)
```

Inside the kernel, a new counter is introduced:

$$
\text{actualBounces} = 0
$$

And it increments only on a successful hit:

```cpp
int actualBounces = 0;

for (int depth = 0 ; depth < 50 ; ++depth)
{
    if (HitWorld(r, 0.001f, 1000.0f, rec, pObjects, numObject))
    {
        ++actualBounces;
        RT::Material material = pMaterials[rec.MaterialID];
        // ... scattering logic continues
    }
}
```

So it is not just counting loop iterations for the sake of optimism; it is counting actual scene interactions while the ray bounces around the world. When heatmap mode is enabled, the renderer no longer writes the regular shaded pixel color. Instead, it normalizes the bounce count as:

$$
t = \frac{\text{actualBounces}}{50}
$$

because the maximum bounce depth in the loop is 50. That logic is written exactly where the final pixel color is chosen:

```cpp
float4 pixelColorRGBA;
if(showHeatmap)
{
    float t = static_cast<float>(actualBounces) / 50;
    float3 heatmapColor = GetHeatmapColor(t);
    pixelColorRGBA = make_float4(heatmapColor.x, heatmapColor.y, heatmapColor.z, 1.0f);
}
else
{
    pixelColorRGBA = make_float4(pixelColor.x, pixelColor.y, pixelColor.z, 1.0f);
}
```

So the image can now answer a handy debugging question visually: *how deep are rays actually bouncing in different parts of the scene?*

## 6. What this follow-up actually adds

Strictly speaking, these commits do **not** change the lighting model, material system, or bounce depth itself. They add four very specific things:

 - proper `currentSPP` naming pass for accumulation,
 - fixed 100-SPP accumulation target with completion detection,
 - progress and timing stats in the console,
 - and a toggleable heatmap that visualizes per-pixel bounce count.

So this update is less “new rendering algorithm” and more “the renderer now explains itself while working.” 