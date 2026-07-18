+++
title = "BVH Debug Rendering"
date = 2026-02-01T18:03:00+05:30
tags = ["cuda", "rendering", "raytracing", "opengl"]
description = "BVH debug rendering using OpenGL"
math = true
+++

# Making the BVH Visible: A Wireframe Debug Overlay for the CUDA Tracer

A BVH is usually a behind-the-scenes structure: useful, essential, and about as visually expressive as a spreadsheet. This change set adds a way to draw its node bounds as OpenGL wireframes over the rendered image, while also carrying the BVH node count through the host and CUDA-facing interfaces.

&nbsp;

The patch does not change the visible shading model in a meaningful way; most CUDA material-switch edits are structural bracing and formatting. The substantive addition is a host-side BVH-to-line-geometry path and a conditional OpenGL overlay.

&nbsp;

{{< youtube App62kGye0U >}}

## What Changed

- A new `BVHDebugRenderer` class with OpenGL VAO, VBO, and shader-program ownership.
- Conversion of each selected `RT::BVHNode::bounds` AABB into wireframe line segments.
- A `B` key toggle for displaying the BVH overlay.

## A New Debug Renderer

The new renderer owns the small set of OpenGL objects needed to draw a colored line list:

```cpp
GLuint m_vao;
GLuint m_vbo;
GLuint m_shaderProgram;
int m_lineCount;

float m_lineWidth;
bool m_showInternal;
bool m_showLeaves;
bool m_initialized;
```

It begins in a state where both internal nodes and leaves are enabled:

```cpp
BVHDebugRenderer::BVHDebugRenderer()
    : m_vao(0)
    , m_vbo(0)
    , m_shaderProgram(0)
    , m_lineCount(0)
    , m_lineWidth(2.0f)
    , m_showInternal(true)
    , m_showLeaves(true)
    , m_initialized(false)
{
}
```

The public interface accepts an array of BVH nodes and a node count during initialization, then accepts a camera at render time:

```cpp
void Initialize(RT::BVHNode* nodes, int nodeCount);
void Render(const RT::Camera& camera);
```

The renderer also exposes setters for line width and for hiding internal or leaf nodes. In the supplied `Main.cpp`, only the line width is configured:

```cpp
gBVHRenderer->SetLineWidth(2.5f);
```

## Turning Boxes into Lines

Each BVH node contributes its axis-aligned bounding box:

```cpp
const RT::AABB box = nodes[i].bounds;
```

The renderer constructs the box’s eight corners from its minimum and maximum coordinates:

```cpp
const float corners = {[2][3]
    {box.min.x, box.min.y, box.min.z},
    {box.max.x, box.min.y, box.min.z},
    {box.max.x, box.max.y, box.min.z},
    {box.min.x, box.max.y, box.min.z},
    {box.min.x, box.min.y, box.max.z},
    {box.max.x, box.min.y, box.max.z},
    {box.max.x, box.max.y, box.max.z},
    {box.min.x, box.max.y, box.max.z}
};
```

It then connects those corners using 12 explicit edges:

```cpp
int edges = {[4][5]
    {0,1}, {1,2}, {2,3}, {3,0},
    {4,5}, {5,6}, {6,7}, {7,4},
    {0,4}, {1,5}, {2,6}, {3,7}
};
```

Each edge has two endpoints, and the code appends two `LineVertex` values per edge. Therefore, a visible node contributes:

$$
N_{\text{edges}} = 12
$$

$$
N_{\text{vertices per node}} = 2 \times 12 = 24
$$

For \(N\) nodes that pass the visibility filters, the line-vertex total is:

$$
N_{\text{vertices}} = 24N
$$

The renderer stores that result as `m_lineCount` and submits it with `GL_LINES`:

```cpp
glDrawArrays(GL_LINES, 0, m_lineCount);
```

No index buffer is used; each line endpoint is stored directly in the vertex buffer. The BVH boxes are taking the scenic route, but it is a very clear route.

## Coloring Leaf and Internal Nodes

Internal BVH nodes are assigned gray:

```cpp
color = 0.7f; color = 0.7f; color = 0.7f;[5][6]
```

Leaf nodes are assigned one of six RGB colors based on `left_or_leaf % 6`:

```cpp
const int leaf_id = nodes[i].left_or_leaf;
if (leaf_id % 6 == 0) { color = 1; color = 0; color = 0; }[6][5]
else if (leaf_id % 6 == 1) { color = 0; color = 1; color = 0; }[5][6]
else if (leaf_id % 6 == 2) { color = 0; color = 0; color = 1; }[6][5]
else if (leaf_id % 6 == 3) { color = 1; color = 1; color = 0; }[5][6]
else if (leaf_id % 6 == 4) { color = 1; color = 0; color = 1; }[6][5]
else { color = 0; color = 1; color = 1; }[5][6]
```

For leaf identifier \(l\), the palette index is:

$$
p = l \bmod 6
$$

This gives a repeating sequence of red, green, blue, yellow, magenta, and cyan. The supplied change does not establish that these colors represent depth, spatial location, traversal order, or primitive category. They are simply selected from six options by modulo arithmetic.

## Uploading Geometry

The generated vertices have a position and an RGB color:

```cpp
struct LineVertex
{
    float position;[3]
    float color;[3]
};
```

The vector is uploaded into a VBO using `GL_STATIC_DRAW`:

```cpp
glBindBuffer(GL_ARRAY_BUFFER, m_vbo);
glBufferData(GL_ARRAY_BUFFER, lines.size() * sizeof(LineVertex),
    lines.data(), GL_STATIC_DRAW);
```

The VAO maps the two fields onto shader attributes:

```cpp
glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(LineVertex), (void*)0);
glEnableVertexAttribArray(0);

glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, sizeof(LineVertex), (void*)(sizeof(float) * 3));
glEnableVertexAttribArray(1);
```

Attribute location 0 reads the three-float position at the start of `LineVertex`. Attribute location 1 reads the color after the first three floats.

## The Shader Path

The renderer embeds two GLSL shaders as source strings.

The vertex shader transforms the input position and forwards its color:

```glsl
layout(location = 0) in vec3 position;
layout(location = 1) in vec3 color;

uniform mat4 viewProjection;

out vec3 fragColor;

void main()
{
    gl_Position = viewProjection * vec4(position, 1.0);
    fragColor = color;
}
```

For a vertex position \(p = (x,y,z)\), this code forms the homogeneous vector:

$$
\tilde{p} =
\begin{bmatrix}
x \\
y \\
z \\
1
\end{bmatrix}
$$

It then computes clip-space position as:

$$
p_{\text{clip}} = M_{\text{viewProjection}}\tilde{p}
$$

The fragment shader writes that interpolated RGB value with alpha one:

```glsl
in vec3 fragColor;
out vec4 outColor;

void main()
{
    outColor = vec4(fragColor, 1.0);
}
```

The patch compiles both shaders, links them into a program, and writes compiler or linker logs to `std::cerr` if either stage reports failure. The diff does not establish a recovery path after failed shader compilation or linking.

## View and Projection

The renderer derives a view matrix from the camera’s basis vectors and origin:

```cpp
const float3 right = camera.u;
const float3 up = camera.v;
const float3 back = camera.w;  
const float3 pos = camera.Origin;
```

Its translation terms are constructed using negative dot products:

```cpp
view.m = right.x;  view.m = right.y;  view.m = right.z;  view.m = -dot(right, pos);[7][2][4]
view.m = up.x;     view.m = up.y;     view.m = up.z;     view.m = -dot(up, pos);[8][9][10][6]
view.m = back.x;   view.m = back.y;   view.m = back.z;   view.m = -dot(back, pos);[11][12][13][5]
```

For camera position \(\mathbf{c}\), these terms are:

$$
t_r = -\mathbf{right} \cdot \mathbf{c}
$$

$$
t_u = -\mathbf{up} \cdot \mathbf{c}
$$

$$
t_b = -\mathbf{back} \cdot \mathbf{c}
$$

The projection matrix uses the camera’s vertical FOV and aspect ratio, along with near and far values set to `0.1f` and `100.0f`:

```cpp
const Matrix4x4 projection = GetProjectionMatrix(camera.vFov, camera.Aspect_ratio, 0.1f, 100.0f);
```

The focal scale is calculated as:

```cpp
const float tanHalfFovy = tanf(fovY * 0.5f * 3.14159265f / 180.0f);
```

If \(\theta\) is `fovY` in degrees, then:

$$
f = \frac{1}{\tan\left(\frac{\theta\pi}{360}\right)}
$$

The diagonal perspective terms written by the code are:

$$
P_{00} = \frac{1}{\mathrm{aspect}\tan(\theta/2)}
$$

$$
P_{11} = \frac{1}{\tan(\theta/2)}
$$

Finally, the code computes:

```cpp
const Matrix4x4 viewProj = MultiplyMatrix(projection, view);
```

So the combined matrix is:

$$
M_{\text{VP}} = M_{\text{projection}}M_{\text{view}}
$$

## Overlay Order and State

The main render loop copies the FBO color buffer to the default framebuffer, then optionally renders the BVH overlay.

```cpp
glBindFramebuffer(GL_READ_FRAMEBUFFER, fbo);
glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
glBlitFramebuffer(0, 0, width, height, 0, 0, width, height, GL_COLOR_BUFFER_BIT, GL_NEAREST);

if(showBVH && gBVHRenderer)
{
gBVHRenderer->Render(gCamera);
}
```

The debug renderer configures OpenGL state immediately before drawing:

```cpp
glLineWidth(m_lineWidth);
glDisable(GL_DEPTH_TEST);
glEnable(GL_BLEND);
glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
glEnable(GL_LINE_SMOOTH);
glHint(GL_LINE_SMOOTH_HINT, GL_NICEST);
```

After drawing, it disables line smoothing and blending:

```cpp
glDisable(GL_LINE_SMOOTH);
glDisable(GL_BLEND);
```

It does not re-enable depth testing in `Render`. The supplied diff does not establish whether depth testing is intentionally left disabled or restored somewhere else later in the frame.

## Input Controls

Pressing `B` toggles BVH rendering:

```cpp
if (key == GLFW_KEY_B && action == GLFW_PRESS)
{
    showBVH = !showBVH;
    std::cout << "BVH Wireframe: " << (showBVH? "ON" : "OFF") << '\n';
}
```

The patch also introduces a `bvhDebugDepth` value, initialized to `3`, and updates it with `=` and `-` key state:

```cpp
if (glfwGetKey(window, GLFW_KEY_EQUAL) == GLFW_PRESS)
{
    bvhDebugDepth++;
}

if (glfwGetKey(window, GLFW_KEY_MINUS) == GLFW_PRESS)
{
    bvhDebugDepth = std::max(0, bvhDebugDepth - 1);
}
```

The lower bound is:

$$
\mathrm{bvhDebugDepth} \geq 0
$$

However, `bvhDebugDepth` is not passed into `BVHDebugRenderer`, does not appear in `GenerateLines`, and does not control any shown draw call. The patch establishes state modification, not depth-filtered rendering.

## BVH Leaf Construction

The BVH builder changes the leaf condition from:

```cpp
if (end - start <= 2)
```

to:

```cpp
if (end - start <= 1)
```

The new leaf branch computes its AABB from a single sphere:

```cpp
RT::AABB bounds = sphere_to_aabb(objects[start].sphere);

nodes[node_idx].bounds = bounds;
nodes[node_idx].left_or_leaf = start;
nodes[node_idx].right_or_count = end - start;
nodes[node_idx].is_leaf = 1;
return node_idx;
```

The prior code that iterated over objects from `start` to `end`, converted their bounds, and combined them is removed. The change therefore directly aligns the leaf branch with a single object at `objects[start]`.

## Sharing the Node Count

The node counter becomes the global `gBVHNodeCount` rather than a local `node_count` in `SetupScene`.

```cpp
int root = buildBVH_simple(h_nodes, sceneObjects, 0, gNumObjects, gBVHNodeCount);
printf("BVH built: %d nodes for %d objects\n", gBVHNodeCount, gNumObjects);
```

That same count is used for CUDA allocation and copy size:

```cpp
cudaMalloc(&d_nodes, gBVHNodeCount * sizeof(RT::BVHNode));

cudaMemcpy(d_nodes, h_nodes, gBVHNodeCount * sizeof(RT::BVHNode), cudaMemcpyHostToDevice);
```

It is also passed to the debug renderer:

```cpp
gBVHRenderer->Initialize(h_nodes, gBVHNodeCount);
```

And forwarded through the host wrapper into the CUDA kernel:

```cpp
RunRayTracingKernel(fbCudaResource, width, height, gCamera, gAccumulationBuffer, currentSPP, dSceneObject, gNumObjects, dMaterial, d_nodes, gBVHNodeCount, true, showHeatmap);
```

```cpp
RayTracer <<<blocksPerGrid, threadsPerBlock>>>(surface, cuWidth, cuHeight, camera, pAccumBuffer, currentSPP, pObjects, numObjects, pMaterials, pBVHNodes, bvhNodeCount, useBVH, showHeatmap);
```

Within the displayed CUDA kernel code, `bvhNodeCount` is added as a parameter but is not subsequently referenced. The diff demonstrates parameter plumbing only; it does not demonstrate a traversal bound, a CUDA-side validation check, or other device behavior using this value.

## A New Vector Operation

`RT_Common.cuh` gains component-wise `float3` division:

```cpp
__host__ __device__ inline float3 operator/(const float3& a, const float3& b)
{
    return make_float3(a.x / b.x, a.y / b.y, a.z / b.z);
}
```

For:

$$
\mathbf{a} = (a_x,a_y,a_z)
$$

and:

$$
\mathbf{b} = (b_x,b_y,b_z)
$$

the operation is:

$$
\mathbf{a} / \mathbf{b} =
\left(
\frac{a_x}{b_x},
\frac{a_y}{b_y},
\frac{a_z}{b_z}
\right)
$$

No use of this overload is shown in the supplied diff, so the patch does not establish its immediate role in the added BVH rendering path or CUDA kernel logic.

## What This Patch Does Not Establish

The changes demonstrate that host-side BVH bounds are converted into line geometry, uploaded to an OpenGL buffer, and conditionally drawn after the framebuffer blit. They also demonstrate the exact matrix and shader path used by the new overlay.

## Closing

This iteration gives the BVH a visible form: gray wireframes for internal nodes, six cycling colors for leaves, and a camera-aligned OpenGL overlay toggled with `B`. At the same time, it promotes the node count into shared state across host allocation, CUDA interface calls, and debug rendering—turning an otherwise private construction detail into a value the renderer can inspect.

## GitHub Link 
[Commit URL](https://github.com/TheOrestes/CUDA_Tracer/commit/7e77f8d0fb116db05e3a916906ccd901eeb55b04)

