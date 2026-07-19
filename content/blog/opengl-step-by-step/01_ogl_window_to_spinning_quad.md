+++
title = "Empty Window and First Quad"
date = 2019-10-23T18:03:00+05:30
tags = ["opengl", "rendering"]
description = "Uploading a first mesh, compiling shaders, and transforming a quad through the OpenGL pipeline."
math = true
+++

This series aims to provide step by step guide to build your very own, simple to understand Graphics Rendering framework with OpenGL as backend. 

![OpenGL rendering pipeline](https://user-images.githubusercontent.com/5098227/150499027-039c9a48-c2d1-4f0c-a765-9217e213c463.png)

&nbsp;

In this post, we will learn basics about GLFW, GLEW library & windows creation. Then we take care of few key presses, and clear the screen. That is the correct first step, but it is also a remarkably efficient way to ask a GPU to draw nothing at all. 

&nbsp;

Post that, we will take a leap towards understanding how vertex and index data is sent to the GPU to draw the geometry on the screen. I assume that reader understands basics of Rendering pipeline and this commit gives the GPU its first actual job: render two quads with vertex data, index data, GLSL shaders, and matrices.

&nbsp;

Before the new rendering code arrives, `main.cpp` carries the usual OpenGL survival kit. GLFW initializes the windowing layer, requests an OpenGL core-profile context, creates a window, and makes that context current. Then GLEW is initialized so the application can access modern OpenGL entry points. This is boilerplate, but it is *load-bearing* boilerplate: no context, no OpenGL; no function loading, no modern API calls.

&nbsp;

The existing loop is equally foundational. It polls operating-system events, chooses a clear color, clears the framebuffer, swaps buffers, and repeats until the window closes. The previous code also registers a callback so pressing \(R\), \(G\), or \(B\) changes the background color. It is not a renderer yet, but it has already learned how to breathe.

```cpp
while (!glfwWindowShouldClose(window))
{
    glfwPollEvents();

    glClearColor(red, green, blue, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    glfwSwapBuffers(window);
}
```

This commit keeps that structure and inserts actual drawing work between clearing and presentation. The broad per-frame shape becomes

$$
\text{poll events}
\rightarrow
\text{clear buffers}
\rightarrow
\text{update scene}
\rightarrow
\text{draw scene}
\rightarrow
\text{swap buffers}.
$$

## Overview

Here are the names of major classes and headers used for building the codebase:

- `GLQuad`, which owns quad geometry and rendering state
- `GLSLShader`, which loads, compiles, links, and activates shaders
- `VertexStructures.h`, which defines vertex layouts
- `Globals.h`, which provides shared window dimensions
- A vertex shader and a fragment shader

The window dimensions move into globals and become \(480 x 270\):

```cpp
const unsigned int gWindowWidth = 480;
const unsigned int gWindowHeight = 270;
```

The clear color also changes from white to dark gray:

```cpp
float red   = 0.1f;
float green = 0.1f;
float blue  = 0.1f;
```

That is a sensible stage for brightly colored geometry. White-on-white debugging is a very advanced rendering technique, best avoided here.

## Two Quads Enter

`main()` now creates two `GLQuad` instances, initializes them, updates them, and renders them every frame. The depth buffer is cleared along with the color buffer.

```cpp
GLQuad quad;
quad.Init();

GLQuad cube2;
cube2.Init();

while (!glfwWindowShouldClose(window))
{
    glfwPollEvents();

    glClearColor(red, green, blue, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    quad.Update(0.016f);
    cube2.Update(0.016f);

    quad.Render();
    cube2.Render();

    glfwSwapBuffers(window);
}
```

The supplied step uses a fixed update interval,

$$
dt = 0.016\ \text{seconds},
$$

which corresponds to approximately

$$
\frac{1}{0.016} = 62.5\ \text{updates per second}.
$$

This is a fixed value, not measured elapsed time, so it is a first animation mechanism rather than a fully frame-rate-independent timing system.

## A Quad Is Two Triangles

OpenGL rasterizes triangles. Therefore, this rectangular quad is described using four vertices and six indices: two triangles that share an edge.

```text
1 ---- 2
|    / |
|  /   |
0 ---- 3
```

The quad is built in local space from these positions:

$$
\begin{aligned}
\mathbf{p}_0 &= (0,0,0), & \mathbf{p}_1 &= (0,1,0), \\
\mathbf{p}_2 &= (1,1,0), & \mathbf{p}_3 &= (1,0,0).
\end{aligned}
$$

The index buffer stores:

```cpp
0, 1, 2,
0, 2, 3
```

The draw call therefore asks OpenGL to render six indexed vertices as triangles:

```cpp
glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, 0);
```

The last argument, `0`, is the byte offset into the currently bound index buffer. It means “start at the beginning,” not “draw nothing.” OpenGL has plenty of ways to draw nothing, but this is not one of them.

## A Vertex Has Data

The new `VertexPC` type stores a position and a color for each vertex:

```cpp
struct VertexPC
{
    glm::vec3 position;
    glm::vec4 color;
};
```

Mathematically, a vertex can be written as

$$
V_i = (\mathbf{p}_i, \mathbf{c}_i)
= \left((x_i,y_i,z_i),(r_i,g_i,b_i,a_i)\right).
$$

The default `GLQuad` constructor supplies red, green, blue, and yellow to the four corners. The color-taking constructor assigns one supplied `glm::vec4` color to every corner. Since the GPU interpolates the colors between vertices, the multicolored version produces gradients across its triangles without any CPU-side pixel painting.

&nbsp;

The default constructor places its quad at \((-1.5, 0, 0)\), scales it by \((3,3,3)\), and records a \(45^\circ\) rotation around the \(y\)-axis. The color-taking constructor uses the origin and unit scale. These are the values introduced in this commit; no external scene system is involved yet.

## Buffers and the VAO

`GLQuad::Init()` creates a vertex array object (VAO), a vertex buffer object (VBO), and an index buffer object (IBO).

```cpp
glGenVertexArrays(1, &vao);
glBindVertexArray(vao);

glGenBuffers(1, &vbo);
glBindBuffer(GL_ARRAY_BUFFER, vbo);

glGenBuffers(1, &ibo);
glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo);
```

The VBO receives the four `VertexPC` structures, while the IBO receives the six indices.

```cpp
glBufferData(GL_ARRAY_BUFFER, 4 * sizeof(VertexPC), vertices, GL_STATIC_DRAW);
glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(indices), indices, GL_STATIC_DRAW);
```

`GL_STATIC_DRAW` communicates that the geometry is uploaded once and reused. The mesh stays put in GPU memory while matrices make it appear to move; that is usually much cheaper than sending a fresh quad across the bus every frame just because it feels spinny.

&nbsp;

The VAO remembers how the VBO should be decoded. A buffer is bytes; a VAO supplies the explanation for those bytes.

## Mapping Memory to Attributes

The vertex shader expects `inPosition` and `inColor`. The initialization code finds those attributes by name, enables them, and describes their layout.

```cpp
posAttrib = glGetAttribLocation(shader, "inPosition");
glEnableVertexAttribArray(posAttrib);
glVertexAttribPointer(
    posAttrib,
    3,
    GL_FLOAT,
    false,
    sizeof(VertexPC),
    (void*)0
);
```

Position begins at offset \(0\), has three `float` components, and has a stride of `sizeof(VertexPC)`. The stride is the number of bytes from one vertex record to the next.

```cpp
colAttrib = glGetAttribLocation(shader, "inColor");
glEnableVertexAttribArray(colAttrib);
glVertexAttribPointer(
    colAttrib,
    4,
    GL_FLOAT,
    false,
    sizeof(VertexPC),
    (void*)offsetof(VertexPC, color)
);
```

Color begins at the offset reported by `offsetof(VertexPC, color)` and contains four `float` components. Conceptually, each vertex is laid out as

$$
\underbrace{x, y, z}_{\text{position}}
\quad
\underbrace{r, g, b, a}_{\text{color}}.
$$

Using `offsetof` avoids guessing the compiler’s structure layout. The compiler knows where it put `color`; there is no reason to turn that fact into a personality test.

## Loading GLSL

The new `GLSLShader` class reads shader files, checks that the source strings are not empty, compiles one vertex shader and one fragment shader, checks compilation errors, links both into a shader program, and provides `Use()` to activate that program.

```cpp
GLuint vertexShaderID = glCreateShader(GL_VERTEX_SHADER);
GLuint fragmentShaderID = glCreateShader(GL_FRAGMENT_SHADER);

// Set source and compile each shader.

GLuint shaderProgramID = glCreateProgram();
glAttachShader(shaderProgramID, vertexShaderID);
glAttachShader(shaderProgramID, fragmentShaderID);
glLinkProgram(shaderProgramID);

glDeleteShader(vertexShaderID);
glDeleteShader(fragmentShaderID);
```

The individual shader objects are deleted after linking, while the linked program remains alive. The class destructor later releases that program with `glDeleteProgram`.

## The Vertex Shader

The vertex shader receives the two attributes, forwards the color, and calculates the final clip-space position:

```glsl
#version 400

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec4 inColor;

out vec4 color;

uniform mat4 matWorld;
uniform mat4 matView;
uniform mat4 matProj;

void main()
{
    color = inColor;

    mat4 WVP = matProj * matView * matWorld;
    gl_Position = WVP * vec4(inPosition, 1.0);
}
```

The coordinate transformation is

$$
\mathbf{p}_{clip} = \mathbf{P}\mathbf{V}\mathbf{W}
\begin{bmatrix}
x \\ y \\ z \\ 1
\end{bmatrix}
$$

The order is read right to left: start in the quad’s local space, move into world space, express the world from the camera’s point of view, then project it into clip space. Matrices are polite enough to write left-to-right and mischievous enough to execute the other way around.

## Building the Matrices

`GLQuad::Update()` builds a world matrix from translation, rotation, and scale:

```cpp
glm::mat4 T = glm::translate(glm::mat4(1), vecPosition);
glm::mat4 TR = glm::rotate(T, angle, glm::vec3(0.0f, 1.0f, 0.0f));
glm::mat4 TRS = glm::scale(TR, vecScale);

matWorld = TRS;
```

In matrix form:

$$
\mathbf{W} = \mathbf{T}\mathbf{R}\mathbf{S}.
$$

For a column-vector position, scaling occurs first, followed by rotation and then translation:

$$
\mathbf{p}_{world}
= \mathbf{T}\mathbf{R}\mathbf{S}\mathbf{p}_{local}.
$$

The code then applies another incremental rotation around the \(y\)-axis using \(0.1 \cdot dt\). That makes the quad rotate during successive updates.

The view matrix places a camera at \((0,0,5)\), looking toward the origin with \(+y\) as its up direction:

```cpp
matView = glm::lookAt(
    glm::vec3(0, 0, 5),
    glm::vec3(0, 0, 0),
    glm::vec3(0, 1, 0)
);
```

The perspective projection uses a 45° field of view, the new shared window dimensions, a near plane of \(0.1\), and a far plane of \(1000.0\):

```cpp
matProj = glm::perspectiveFov(
    45.0f,
    float(gWindowWidth),
    float(gWindowHeight),
    0.1f,
    1000.0f
);
```

## The Fragment Shader

The fragment shader receives the interpolated color and writes it to output location \(0\):

```glsl
#version 400

in vec4 color;

layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 brightColor;

void main()
{
    outColor = color;
}
```

`brightColor` is declared at location \(1\), but this commit does not assign to it or configure a second render target. It is a guest at the party who has not been given a job yet.

## Depth and Cleanup

The quad initialization enables depth testing:

```cpp
glEnable(GL_DEPTH_TEST);
```

The main loop now clears both the color and depth buffers every frame:

```cpp
glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
```

Depth testing decides which overlapping fragments are visible according to depth. With two renderable objects and transforms entering the scene, enabling this state establishes the expected foundation for 3D rendering.

&nbsp;

Finally, `GLQuad::Kill()` releases its resources:

```cpp
delete mpShader;

glDeleteBuffers(1, &vbo);
glDeleteBuffers(1, &ibo);
glDeleteVertexArrays(1, &vao);
```

This commit has now completed the first full programmable rendering path:

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

The window is no longer just open. It is finally doing graphics.
