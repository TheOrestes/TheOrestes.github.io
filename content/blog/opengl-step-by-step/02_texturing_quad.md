+++
title = "Texturing a Quad: Giving Our First Mesh Some Pixels"
date = 2019-10-28T18:03:00+05:30
tags = ["opengl", "rendering"]
description = "Replacing vertex colors with texture coordinates and sampling a 2D image in a GLSL fragment shader."
math = true
+++

In the previous step, our OpenGL application could draw colored quads. That was a solid start: vertices entered the GPU, shaders transformed them, triangles appeared, and everyone went home mostly happy. But vertex colors are a little like painting a billboard with four paint buckets: useful, but not exactly the full visual buffet.

![Textured Quad](https://user-images.githubusercontent.com/5098227/150506409-1f163185-84f7-43a1-a80b-0341514656bb.png)

This commit replaces per-vertex color with a 2D texture. The quad now carries texture coordinates, loads `Randy.jpg` from `../Assets/textures`, uploads that image to an OpenGL texture object, and samples it in the fragment shader. The result is an image mapped across the quad.

&nbsp;

At a high level, the path is now

$$
\text{image file}
\rightarrow
\text{CPU pixel data}
\rightarrow
\text{GPU texture}
\rightarrow
\text{texture coordinates}
\rightarrow
\text{fragment shader}
\rightarrow
\text{screen}.
$$

## What Changed

We now have a dedicated TextureManager class for loading image data using stb_image & the Quad now uses different Vertex structure that supports texture co-ordinates. We also create new shaders for accessing the texture co-ords in the shader and passing them to the fragment shader. 

```cpp
mpShader = new GLSLShader("Shaders/vsTextureQuad.glsl", "Shaders/psTextureQuad.glsl");
```

The optional constructor that accepted one `glm::vec4` color is removed. That is faithful to the new direction: this commit no longer feeds vertex colors into the rendering path.

## Texture Coordinates

A textured vertex contains a position and a two-dimensional texture coordinate:

```cpp
struct VertexPT
{
    glm::vec3 position;
    glm::vec2 texcoord;
};
```

We can write this as

$$
V_i = \left(\mathbf{p}_i, \mathbf{u}_i\right),
$$

where

$$
\mathbf{p}_i = (x_i,y_i,z_i)
\quad\text{and}\quad
\mathbf{u}_i = (u_i,v_i).
$$

The quad geometry still uses four vertices and the same six indices. Only the data attached to each vertex changes.

```cpp
vertices[0] = VertexPT(glm::vec3(0, 0, 0), glm::vec2(0, 1));
vertices[1] = VertexPT(glm::vec3(0, 1, 0), glm::vec2(0, 0));
vertices[2] = VertexPT(glm::vec3(1, 1, 0), glm::vec2(1, 0));
vertices[3] = VertexPT(glm::vec3(1, 0, 0), glm::vec2(1, 1));
```

The \((u,v)\) values tell the shader which point in the image belongs to each corner of the quad. Here, the coordinates cover the familiar normalized range:

$$
0 \leq u \leq 1,
\qquad
0 \leq v \leq 1.
$$

One practical detail is already visible: the top vertices use \(v = 0\), while the bottom vertices use \(v = 1\). This matches the loader configuration discussed below, which flips the source image vertically during loading. Coordinate systems: the universal reminder that “up” is a social construct.

## Updating the VAO

The vertex buffer now uploads `VertexPT` records instead of `VertexPC` records:

```cpp
glBufferData(GL_ARRAY_BUFFER, 4 * sizeof(VertexPT), vertices, GL_STATIC_DRAW);
```

Position remains attribute `inPosition`, but its stride changes to the size of the new structure:

```cpp
glVertexAttribPointer(
    posAttrib,
    3,
    GL_FLOAT,
    false,
    sizeof(VertexPT),
    (void*)0
);
```

The old `inColor` attribute is removed. In its place, `inTexcoord` is enabled and configured as two floats at the `texcoord` member offset:

```cpp
texAttrib = glGetAttribLocation(shader, "inTexcoord");
glEnableVertexAttribArray(texAttrib);
glVertexAttribPointer(
    texAttrib,
    2,
    GL_FLOAT,
    false,
    sizeof(VertexPT),
    (void*)offsetof(VertexPT, texcoord)
);
```

The memory layout is conceptually

$$
\underbrace{x,y,z}_{\text{position}}
\quad
\underbrace{u,v}_{\text{texture coordinate}}.
$$

The VAO still performs the same essential duty: it tells OpenGL how to interpret the bytes in the currently associated vertex buffer.

## Loading an Image

`TextureManager` introduces `Load2DTextureFromFile()`. The quad loads `Randy.jpg` from `../Assets/textures` and stores the resulting texture object ID in `tbo`.

```cpp
tbo = TextureManager::getInstannce().Load2DTextureFromFile("Randy.jpg", "../Assets/textures");
```

The loader builds the filename, asks `stb_image` to flip the image vertically, and loads its pixels:

```cpp
stbi_set_flip_vertically_on_load(1);
data = stbi_load(filename.c_str(), &width, &height, &bpp, 0);
```

The vertical flip aligns the image data with the texture-coordinate convention used by this quad. The commit does not add error handling for a failed `stbi_load`, so this step assumes the image is found and successfully decoded.

&nbsp;

An OpenGL texture object is then generated and bound:

```cpp
GLuint textureID;
glGenTextures(1, &textureID);
glBindTexture(GL_TEXTURE_2D, textureID);
```

Depending on the reported bytes per pixel, the code uploads either an RGBA or RGB image:

```cpp
if (bpp == 3)
{
    glTexImage2D(GL_TEXTURE_2D, 0, GL_SRGB_ALPHA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, data);
}
else
{
    glTexImage2D(GL_TEXTURE_2D, 0, GL_SRGB, width, height, 0, GL_RGB, GL_UNSIGNED_BYTE, data);
}
```

This is the exact branch used in the commit: three bytes per pixel take the first branch, and every other `bpp` value takes the second. After uploading, the CPU-side image memory is released with `stbi_image_free(data)`.

## Sampling Rules

The loader generates mipmaps and sets wrapping and filtering parameters:

```cpp
glGenerateMipmap(GL_TEXTURE_2D);

glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
```

`GL_REPEAT` repeats an image if a texture coordinate moves beyond the \([0,1]\) interval. The current quad uses only the interval itself, so repetition is configured but not demonstrated yet.

&nbsp;

The minification filter is `GL_LINEAR_MIPMAP_LINEAR`, which selects and linearly blends mipmap levels while linearly filtering within them. The magnification filter is `GL_LINEAR`, so enlarged texels are smoothly interpolated rather than shown as nearest-neighbor blocks.

The texture manager also adds a cubemap-loading function that expects six specifically named files—`posx.jpg`, `negx.jpg`, `posy.jpg`, `negy.jpg`, `posz.jpg`, and `negz.jpg`. Nothing in this commit binds or samples a cubemap; it is utility code added alongside the 2D texture path.

## Vertex Shader Changes

The new vertex shader replaces `inColor` with `inTexcoord`:

```glsl
layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec2 inTexcoord;

out vec3 vsoutPosition;
out vec2 vsoutUV;
```

It calculates the world-space position and forwards the texture coordinate to the fragment shader:

```glsl
vsoutPosition = (matWorld * vec4(inPosition, 1.0)).xyz;
vsoutUV = inTexcoord;

gl_Position = matProj * matView * matWorld * vec4(inPosition, 1.0);
```

The clip-space transform still follows the familiar equation

$$
\mathbf{p}_{clip}=\mathbf{P}\mathbf{V}\mathbf{W}
\begin{bmatrix}
x \\ y \\ z \\ 1
\end{bmatrix}.
$$

The new `vsoutPosition` is produced in the vertex shader, but the fragment shader introduced here does not use it. It is simply passed along as part of this commit’s shader interface.

The projection call changes from `glm::perspectiveFov` to `glm::perspectiveFovRH`:

```cpp
matProj = glm::perspectiveFovRH(
    45.0f,
    float(gWindowWidth),
    float(gWindowHeight),
    0.1f,
    1000.0f
);
```

The supplied angle remains `45.0f`; the change is specifically to the right-handed projection helper.

## Fragment Shader Sampling

The fragment shader receives the interpolated UV coordinate and declares a `sampler2D` uniform named `texturediffuse`:

```glsl
layout(location = 0) out vec4 outColor;

in vec3 vsoutPosition;
in vec2 vsoutUV;

uniform mat4 matWorld;
uniform sampler2D texturediffuse;
```

Its entire visible shading operation is a texture lookup:

```glsl
vec4 Ambient = texture(texturediffuse, vsoutUV);
outColor = Ambient;
```

In shorthand:

$$
\mathbf{C}_{out} = T(u,v),
$$

where \(T\) is the 2D texture and \((u,v)\) is the interpolated coordinate at the current fragment. The variable is called `Ambient`, but this commit does not compute lighting; it simply samples and outputs the texture color.

## Binding Texture Unit Zero

Before drawing, `GLQuad::Render()` connects the sampler uniform to texture unit zero:

```cpp
glUniform1i(
    glGetUniformLocation(mpShader->GetShaderID(), "texturediffuse"),
    0);
```

Then it activates texture unit zero and binds the quad’s 2D texture object there:

```cpp
glActiveTexture(GL_TEXTURE0);
glBindTexture(GL_TEXTURE_2D, tbo);
```

The relationship is

$$
\texttt{texturediffuse} \rightarrow 0 \rightarrow \texttt{GL\_TEXTURE0} \rightarrow tbo.
$$

Finally, the usual indexed draw call renders the two triangles, after which the code unbinds the 2D texture:

```cpp
glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, 0);
glBindTexture(GL_TEXTURE_2D, 0);
```

## Small Shader-Wrapper Cleanup

`GLSLShader::LoadShader()` no longer explicitly rejects empty shader source strings before creating shader objects. The shader compilation check also changes from `if (result != GL_TRUE)` to `if (!result)`. These are code changes in the commit, but they do not alter the texture-rendering flow described above.

## What We Have Now

This step turns the quad from a color-interpolating primitive into an image-carrying primitive. Its triangles still come from the same index buffer and its transforms still move through world, view, and projection matrices. The new ingredient is the mapping

$$
\text{quad surface} \longleftrightarrow (u,v) \longleftrightarrow \text{image pixel}.
$$

That mapping is the foundation for textures in OpenGL. The quad has not become more geometrically complicated, it is still just two triangles, but it can now wear an image, which is the beginning of most game art pipelines and the end of the era of pretending four vertex colors are a wardrobe.
