+++
title = "Building a Cube: Losing a Texture, Gaining a Dimension"
date = 2019-11-02T18:03:00+05:30
tags = ["opengl", "rendering"]
description = "Retiring the textured quad and TextureManager in favor of an eight-vertex, thirty-six-index color cube, and finding out why depth testing finally has something to do."
math = true
+++

# Building a Cube: Losing a Texture, Gaining a Dimension

By the end of this post, our flat textured rectangle is gone, replaced by a solid, per-vertex-colored cube: eight vertices, thirty-six indices, and — for the first time in this series — geometry with a back side. That last part matters beyond this one commit. Every step from here on, camera movement, lighting, reflections, shadows, needs something three-dimensional to act on, and a quad facing the camera head-on was never going to cut it. This is the commit where the series trades its last flat surface for a shape worth building the rest of the pipeline around.

&nbsp;

{{< youtube jOOWaa0-QJc >}}

&nbsp;

$$
\text{textured quad } (4\ \text{verts})
\;\longrightarrow\;
\text{colored cube } (8\ \text{verts})
$$

## Out With the Texture Manager

`TextureManager`, with its `Load2DTextureFromFile()` and the still-unused `LoadCubemapFromFile()`, is gone — not refactored, not commented out, just deleted, along with the `stb_image` dependency path in the `.vcxproj`. This commit doesn't sample a single pixel from an image. Color, for now, goes back to being something you assign per vertex in C++, the way it was two posts ago.

## The Vertex Gets a Different Passenger

`VertexPT` had a texture coordinate riding alongside position. `VertexPC` swaps that out for a color:

```cpp
struct VertexPC
{
    VertexPC() :
        position(0.0f),
        color(1.0f) {}

    VertexPC(const glm::vec3& _p, const glm::vec4& _c) :
        position(_p),
        color(_c) {}

    glm::vec3 position;
    glm::vec4 color;
};
```

Same shape as the `VertexPC` from the very first post, just now living in a cube instead of a quad:

$$
V_i = (\mathbf{p}_i, \mathbf{c}_i) = \left((x_i,y_i,z_i),\ (r_i,g_i,b_i,a_i)\right).
$$

## Eight Vertices, Six Faces, Thirty-Six Indices

`GLCube`'s default constructor places eight vertices at the corners of a unit cube centered on the origin, spanning \([-1,1]\) on every axis:

```cpp
vertices[0] = VertexPC(glm::vec3(-1,-1, 1), glm::vec4(1,0,0,1));
vertices[1] = VertexPC(glm::vec3( 1,-1, 1), glm::vec4(0,1,0,1));
vertices[2] = VertexPC(glm::vec3( 1, 1, 1), glm::vec4(0,0,1,1));
vertices[3] = VertexPC(glm::vec3(-1, 1, 1), glm::vec4(1,1,0,1));
vertices[4] = VertexPC(glm::vec3(-1,-1,-1), glm::vec4(1,1,0,1));
vertices[5] = VertexPC(glm::vec3( 1,-1,-1), glm::vec4(0,0,1,1));
vertices[6] = VertexPC(glm::vec3( 1, 1,-1), glm::vec4(0,1,0,1));
vertices[7] = VertexPC(glm::vec3(-1, 1,-1), glm::vec4(1,0,0,1));
```

Eight corners is fine for storage, but a GPU only knows how to rasterize triangles, and a cube has six square faces. Each face is two triangles, so:

$$
6\ \text{faces} \times 2\ \text{triangles} \times 3\ \text{indices} = 36\ \text{indices}.
$$

The index buffer spells out exactly which three corners make each triangle, face by face:

| Face | Corners | Triangle indices |
|---|---|---|
| Front (\(z=1\)) | 0,1,2,3 | `0,1,2` / `2,3,0` |
| Top (\(y=1\)) | 3,2,6,7 | `3,2,6` / `6,7,3` |
| Back (\(z=-1\)) | 7,6,5,4 | `7,6,5` / `5,4,7` |
| Bottom (\(y=-1\)) | 4,5,1,0 | `4,5,1` / `1,0,4` |
| Left (\(x=-1\)) | 4,0,3,7 | `4,0,3` / `3,7,4` |
| Right (\(x=1\)) | 1,5,6,2 | `1,5,6` / `6,2,1` |

Twelve triangles, thirty-six numbers, one cube. No new geometric ideas here beyond the quad's — just six quads glued together and pointed outward.

## Two Ways to Build the Same Cube

`GLCube` ships two constructors. The default one hand-picks a different color per corner, which is how you get that classic "someone spilled a box of crayons on a cube" debug look, useful for eyeballing orientation and face winding at a glance. The second constructor takes a single `glm::vec4` and paints every corner the same color:

```cpp
GLCube(const glm::vec4& color);
```

Both constructors set the same default transform: position at the origin, unit scale, and a rotation of \(45^\circ\) around the \(y\)-axis via `SetRotation(glm::vec3(0,1,0), 45.0f)`.

&nbsp;

Here's a small wrinkle worth flagging for fidelity's sake: that stored rotation axis and angle are never actually read back. `Update()` builds its own rotation independently, using a locally accumulated `angle` and a hardcoded \(y\)-axis:

```cpp
static float angle = 0.0f;
angle += dt;

glm::mat4 T   = glm::translate(glm::mat4(1), vecPosition);
glm::mat4 TR  = glm::rotate(T, angle, glm::vec3(0.0f, 1.0f, 0.0f));
glm::mat4 TRS = glm::scale(TR, vecScale);

matWorld = TRS;
```

So `SetRotation()`'s \(45^\circ\) is set, stored in `vecRotationAxis` and `m_fAngle`, and then never consulted again this commit. The cube's actual on-screen spin comes entirely from `angle` accumulating `dt` every frame — continuous rotation around \(y\), not a fixed \(45^\circ\) pose.

## Buffers: Same Recipe, Bigger Portions

`GLCube::Init()` follows the exact VAO/VBO/IBO pattern from the earlier posts, just sized for eight vertices and thirty-six indices instead of four and six:

```cpp
glBufferData(GL_ARRAY_BUFFER, 8 * sizeof(VertexPC), vertices, GL_STATIC_DRAW);
glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(indices), indices, GL_STATIC_DRAW);
```

Attribute wiring is also the same shape as before, just renamed to match the shader's new attribute names and the `VertexPC` layout:

```cpp
posAttrib = glGetAttribLocation(shader, "in_Position");
glEnableVertexAttribArray(posAttrib);
glVertexAttribPointer(posAttrib, 3, GL_FLOAT, false, sizeof(VertexPC), (void*)0);

colAttrib = glGetAttribLocation(shader, "in_Color");
glEnableVertexAttribArray(colAttrib);
glVertexAttribPointer(colAttrib, 4, GL_FLOAT, false, sizeof(VertexPC), (void*)offsetof(VertexPC, color));
```

The memory layout per vertex is, once again,

$$
\underbrace{x,y,z}_{\text{position, 12 bytes}}
\quad
\underbrace{r,g,b,a}_{\text{color, 16 bytes}}.
$$

## The Shaders, Renamed and Slimmed Down

`vs.glsl` drops the texture-coordinate output entirely and forwards a color instead:

```glsl
#version 400

layout(location=0) in vec3 in_Position;
layout(location=1) in vec4 in_Color;

out vec4 color;

uniform mat4 matWorld;
uniform mat4 matView;
uniform mat4 matProj;

void main()
{
    color = in_Color;

    mat4 WVP = matProj * matView * matWorld;

    gl_Position = WVP * vec4(in_Position, 1.0);
}
```

Same clip-space transform as ever,

$$
\mathbf{p}_{clip} = \mathbf{P}\mathbf{V}\mathbf{W}
\begin{bmatrix} x \\ y \\ z \\ 1 \end{bmatrix},
$$

just no more UV along for the ride. `ps.glsl` is equally direct:

```glsl
#version 400

in vec4 color;

layout (location = 0) out vec4 outColor;
layout (location = 1) out vec4 brightColor;

void main()
{
    outColor = color;
}
```

`brightColor` shows up at output location \(1\) again, still unassigned, still unused — the same guest from the first post's fragment shader, still waiting for an invitation to do something. This commit doesn't configure a second render target or write to it, so treat its presence as scaffolding, not functionality.

## Why Depth Testing Finally Matters

`glEnable(GL_DEPTH_TEST)` was already present before, but with a flat quad facing the camera it was doing very little. A cube is the first shape in this series with faces that can occlude each other: the back faces exist, and without depth testing they'd happily draw on top of the front ones depending on draw order. Now that we're rendering actual 3D geometry, depth testing goes from "reasonable default" to "the thing keeping the cube from looking inside-out."

## Cleanup, Because Someone Had To

A few small things ride along in this commit that don't change behavior but are worth a one-line mention for completeness: `Source.cpp` deletes the long-idle, commented-out `cube2.Init()` / `cube2.Update()` / `cube2.Render()` lines that had been sitting there since the two-quad days, and `GLCube.h` collapses a duplicated `#pragma once` down to one. Neither changes what runs, both make the file slightly less embarrassing to scroll past.

## What We Have Now

The rendering pipeline itself hasn't changed shape:

$$
\text{vertex data}
\rightarrow
\text{GPU buffers}
\rightarrow
\text{vertex shader}
\rightarrow
\text{triangles}
\rightarrow
\text{fragment shader}
\rightarrow
\text{framebuffer}.
$$

What changed is the payload flowing through it: four vertices became eight, six indices became thirty-six, a texture coordinate became a color, and a flat rectangle became a solid whose faces can finally get in each other's way. We gave up the ability to wear an image so that we could stand up in three dimensions instead — a fair trade, and the last time this series will be satisfied with something that doesn't have a back side.
