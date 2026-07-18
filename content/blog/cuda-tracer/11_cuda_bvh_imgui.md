+++
title = "BVH Fine tuning & ImGUI Integration"
date = 2026-02-22T18:03:00+05:30
tags = ["cuda", "rendering", "raytracing", "opengl"]
description = "BVH Fine tuning & ImGUI Integration"
math = true
+++

# Depth-Aware Wireframes, an ImGui Control Panel, and a Much Busier Scene

The tracer now makes its bounding-volume hierarchy visible in a more structured way: BVH boxes are grouped by depth, colored by depth, and drawn thick-to-thin from root to leaves. The update also adds an ImGui control surface, increases the rendering resolution and random-scene density, and records a `depth` value in every BVH node.

&nbsp;

{{< youtube VI2Wm4_LGcc >}}

## The BVH Gets Layers

Previously, the debug renderer built one large list of wireframe vertices and drew it in a single OpenGL call. The updated renderer first finds the deepest node in the BVH, then stores a separate line-vertex list for every depth from \(0\) to `m_treeMaxDepth`.

&nbsp;

For every BVH depth \(d\), it generates only nodes satisfying:

$$
\text{node.depth} = d
$$

Each selected node still contributes the twelve edges of its AABB. Since each edge has two endpoints, one box produces:

$$
12 \times 2 = 24
$$

line vertices. The full total across all layers remains:

$$
N_{\text{vertices}} = 24N_{\text{nodes}}
$$

The renderer now uploads each depth layer into the VBO immediately before drawing it:

```cpp
glBufferData(
    GL_ARRAY_BUFFER,
    m_linesByDepth[depth].size() * sizeof(LineVertex),
    m_linesByDepth[depth].data(),
    GL_DYNAMIC_DRAW
);

glDrawArrays(GL_LINES, 0, static_cast<GLsizei>(m_linesByDepth[depth].size()));
```

So the VBO is no longer filled once at initialization with every BVH line. Instead, it is reused once per depth during rendering. The hierarchy is effectively drawn as a series of depth passes, because apparently even acceleration structures deserve staging.

## Depth Becomes Data

`buildBVH_simple` now accepts a `depth` argument, initialized to zero at the root:

```cpp
int buildBVH_simple(
    RT::BVHNode* nodes,
    std::vector<RT::SceneObject>& objects,
    int start,
    int end,
    int& node_count,
    int depth = 0
)
```

The recursive calls increment it:

```cpp
const int left = buildBVH_simple(nodes, objects, start, mid, node_count, depth + 1);
const int right = buildBVH_simple(nodes, objects, mid, end, node_count, depth + 1);
```

Both leaves and internal nodes store their resulting level:

```cpp
nodes[node_idx].depth = depth;
```

That makes the root node depth \(0\), its children depth \(1\), and so on:

$$
d_{\text{child}} = d_{\text{parent}} + 1
$$

The debug renderer scans these values to calculate `m_treeMaxDepth`, then allocates exactly:

$$
m_{\text{treeMaxDepth}} + 1
$$

per-depth vertex collections.

## From Thick Roots to Thin Leaves

The renderer gives each depth a different line width. With base width \(w\), current depth \(d\), and maximum tree depth \(D\), it calculates:

$$
r = \frac{d}{D}
$$

$$
w_d = w(1 - 0.8r)
$$

and clamps the result to at least one pixel:

$$
w_{\text{final}} = \max(1.0, w_d)
$$

The application configures the base width as:

```cpp
gBVHRenderer->SetBaseLineWidth(8.0f);
```

At the root, where \(d = 0\), the line width is \(8.0\). At the deepest layer, where \(d = D\), the unclamped width is:

$$
8.0(1 - 0.8) = 1.6
$$

So the root is deliberately chunky while deeper levels become progressively slimmer. This does not hide layers or limit traversal depth; it only changes how thick each rendered layer appears.

## A Palette for Tree Depth

BVH line colors are no longer based on whether a node is a leaf or on a leaf identifier. Instead, color comes directly from the node depth.

&nbsp;

The renderer uses a ten-color palette:

| Depth palette entry | Color |
|---|---|
| 0 | Red |
| 1 | Orange |
| 2 | Yellow |
| 3 | Green |
| 4 | Cyan |
| 5 | Light blue |
| 6 | Blue |
| 7 | Purple |
| 8 | Magenta |
| 9 | Pink |

For depth \(d\), the chosen palette index is:

$$
i = d \bmod 10
$$

That means the palette repeats after ten levels. A hierarchy deeper than ten is not left colorless; it simply loops back around and starts the chromatic tour again.

The application enables this mode during scene setup:

```cpp
gBVHRenderer->EnableDepthColorMode(true);
```

The shown `GenerateLinesForDepth` implementation directly calls `GetDepthColor(targetDepth, color)`. The change list does not show `m_colorByDepth` being tested before color selection, so the flag is configured but not shown controlling a branch in the supplied renderer code.

## ImGui Joins the Frame

The project now includes Dear ImGui source files, GLFW and OpenGL3 backend files, and corresponding Visual Studio project entries. `Main.cpp` initializes ImGui with keyboard navigation and docking enabled, then uses the OpenGL3 backend with GLSL version `#version 460`.

```cpp
io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
io.ConfigFlags |= ImGuiConfigFlags_DockingEnable;

ImGuiImplGlfwInitForOpenGL(window, false);
ImGuiImplOpenGL3Init("#version 460");
```

## The New Control Window

Every frame, the program creates a dockspace and an auto-resizing window titled **Ray Tracer Controls**. It displays mouse position and click state, then exposes several collapsible sections.

### Render Statistics

The UI displays:

- FPS
- Frame time in milliseconds
- Current samples per pixel and target SPP
- Total render time
- A progress bar based on:

$$
p = \min\left(1,\frac{\text{currentSPP}}{\text{targetSPP}}\right)
$$

The per-frame loop calculates FPS from the number of frames observed over roughly one second.

### Camera Information

The UI displays the camera origin and offers a slider for camera speed:

$$
0.1 \leq \text{cameraSpeed} \leq 10.0
$$

The value directly updates the existing `cameraSpeed` variable.

### Debug Visualization

The UI provides two checkboxes:

```cpp
ImGui::Checkbox("Show BVH Wireframe", &showBVH);
ImGui::Checkbox("Show Heatmap", &showHeatmap);
```

Changing the heatmap toggle clears the CUDA accumulation buffer and restarts accumulation:

```cpp
currentSPP = 0;
accumulationComplete = false;
cudaMemset(gAccumulationBuffer, 0, bufferSize);
```

The supplied code explicitly treats BVH wireframe display differently: toggling it does not reset accumulation.

### Render Settings

The UI adds controls for:

$$
1 \leq \text{targetSPP} \leq 500
$$

and:

$$
1 \leq \text{maxRayDepth} \leq 50
$$

Changing `targetSPP` marks accumulation incomplete. The shown change list does not show `maxRayDepth` being passed into the CUDA kernel or otherwise consumed by rendering code, so the patch establishes the UI variable and slider but not a ray-tracing behavior tied to it.

### Manual Reset

A **Reset Accumulation** button sets the current sample count to zero, marks accumulation incomplete, and clears the CUDA accumulation buffer.

## Input Now Goes Through ImGui Too

The GLFW callbacks now forward events to the ImGui GLFW backend:

```cpp
ImGuiImplGlfwKeyCallback(window, key, scancode, action, mode);
ImGuiImplGlfwMouseButtonCallback(window, button, action, mods);
ImGuiImplGlfwCursorPosCallback(window, xpos, ypos);
ImGuiImplGlfwScrollCallback(window, xoffset, yoffset);
ImGuiImplGlfwCharCallback(window, c);
```

The patch retains the application’s own input handling around these calls. It also adds registration for scroll and character callbacks:

```cpp
glfwSetScrollCallback(window, ScrollCallback);
glfwSetCharCallback(window, CharCallback);
```

At shutdown, the ImGui OpenGL backend, GLFW backend, and ImGui context are shut down before the CUDA/OpenGL resources are released.

## More Spheres

The random scene’s grid dimension changes from `3` to `10`. Since the loops run inclusively from \(-\text{objDims}\) to \(+\text{objDims}\), the number of grid positions changes from:

$$
(2 \cdot 3 + 1)^2 = 7^2 = 49
$$

to:

$$
(2 \cdot 10 + 1)^2 = 21^2 = 441
$$

The change list also shows that both `InitSimpleScene` and `InitRandomScene` are called during scene setup.

## Frame Ordering

The BVH renderer still runs after the CUDA-generated framebuffer is copied to the default framebuffer. The ImGui control rendering now follows the BVH overlay:

```cpp
gBVHRenderer->Render(gCamera);
RenderImGuiControls(fps, deltaTime, progress);
glfwSwapBuffers(window);
```

The visible ordering is therefore:

$$
\text{CUDA ray-traced image}
\rightarrow
\text{BVH wireframe overlay}
\rightarrow
\text{ImGui controls}
\rightarrow
\text{swap buffers}
$$

The debug boxes are drawn without depth testing and with blending and line smoothing enabled, as in the earlier renderer path.

## GitHub Link
[Commit URL](https://github.com/TheOrestes/CUDA_Tracer/commit/bdfbf937fda6fd5aee370d5783b0d0ee4f83132b)
