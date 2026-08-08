+++
title = "Building a Skybox: Cubemaps, a Resurrected TextureManager, and a Depth-Test Trick"
date = 2019-11-14T18:03:00+05:30
tags = ["opengl", "rendering"]
description = "Wrapping the scene in a cubemap skybox, finally putting LoadCubemapFromFile() to use, and learning the GL_LEQUAL trick that keeps the sky pinned behind everything else."
math = true
+++

By the end of this post, the flat gray clear color behind our cube is gone, replaced by an actual sky: a cubemap wrapped around the whole scene, always centered on the camera, always infinitely far away. That matters for more than looks. Once there's an environment worth existing inside, the obvious next step is giving the scene something more interesting than a colored cube to put in it, and `assimp` and `stb` were already quietly wired into the project two posts ago in anticipation of exactly that. This is also the commit where `LoadCubemapFromFile()`, sitting unused in `TextureManager` since it was written all the way back in the texturing post, finally gets called.

&nbsp;

{{< youtube tdbA8SLA8L0 >}}

&nbsp;

$$
\text{flat clear color} \;\longrightarrow\; \text{cubemap skybox}
$$

## Same Cube, Different Job

`GLSkybox`'s vertex and index data is the exact same eight corners and thirty-six indices as `GLCube` from a few posts back, just stripped down to `VertexP` (position only, no color):

```cpp
vertices[0] = VertexP(glm::vec3(-1,-1,1));
vertices[1] = VertexP(glm::vec3(1,-1,1));
vertices[2] = VertexP(glm::vec3(1,1,1));
vertices[3] = VertexP(glm::vec3(-1,1,1));
vertices[4] = VertexP(glm::vec3(-1,-1,-1));
vertices[5] = VertexP(glm::vec3(1,-1,-1));
vertices[6] = VertexP(glm::vec3(1,1,-1));
vertices[7] = VertexP(glm::vec3(-1,1,-1));
```

A skybox doesn't need per-vertex color; it's about to sample a texture instead. Reusing the same eight corners and six faces makes sense once you notice the actual trick: a skybox is just a cube, drawn from the inside, with a cubemap texture pasted across its interior faces instead of flat colors.

## TextureManager, Resurrected

`TextureManager` was deleted, wholesale, back when `GLQuad` became `GLCube`. It returns in this commit, unchanged, specifically so `GLSkybox::Init()` can call the one function that's been sitting in it unused since the texturing post: `LoadCubemapFromFile()`.

```cpp
tbo = TextureManager::getInstannce().LoadCubemapFromFile("../Assets/cubemaps/Yokohama2");
```

That function loads six specifically named images, `posx.jpg`, `negx.jpg`, `posy.jpg`, `negy.jpg`, `posz.jpg`, `negz.jpg`, one per cube face, into a single `GL_TEXTURE_CUBE_MAP` object. It was written two posts before there was anything in the codebase that could use it. Now there is.

## Sampling Six Faces from One Direction

The vertex shader forwards each vertex's local-space position straight through as a sampling direction:

```glsl
vs_outTex = in_Position;
```

Since the skybox cube is centered on the origin, the vector from the center to any point on its surface already points in exactly the direction that vertex sits in, which is exactly what a cubemap sampler wants: a direction, not a UV coordinate. The fragment shader hands that straight to `texture()`:

```glsl
outColor = texture(cubeMap, -vs_outTex);
```

The more interesting line is how the vertex shader positions things on screen:

```glsl
mat4 wvp = matProj * matView * matWorld;
vec4 Pos = wvp * vec4(in_Position, 1.0f);
gl_Position = Pos.xyww;
```

Swapping the clip-space `z` component for `w` is deliberate. After the GPU's perspective divide, every coordinate gets divided by `w`:

$$
z_{ndc} = \frac{Pos_z}{Pos_w} \;\;\longrightarrow\;\; \frac{Pos_w}{Pos_w} = 1.
$$

Forcing `z` to equal `w` before that divide guarantees the skybox always lands at depth \(1.0\), the farthest possible value, no matter how close or far the camera actually is from the cube's geometry. It's a cheap way to pin the sky behind everything else without needing a real "infinitely large" mesh.

## The GL_LEQUAL Trick

A depth of exactly \(1.0\) creates a problem: the default depth test, `GL_LESS`, only lets a fragment through if it's strictly closer than what's already there. The screen starts out cleared to depth \(1.0\) too, so a `GL_LESS` test would reject the skybox everywhere, including empty background it should be filling. `GLSkybox::Render()` works around this with a comment that explains itself better than a paraphrase would:

```cpp
// So based on shader for skybox, we have made sure that third component equal to w,
// perspective divide always returns 1. This way depth value is always 1 which is at
// back of all the geometries rendered.
// The depth buffer will be filled with values of 1.0 for the skybox, so we need to
// make sure the skybox passes the depth tests with values less than or equal to the
// depth buffer instead of less than.
glDepthFunc(GL_LEQUAL);
```

`GL_LEQUAL` lets equal depths through, so the skybox's constant \(1.0\) passes against the cleared background (also \(1.0\)) but still loses to anything already drawn closer. That only works correctly if the skybox is drawn after everything else, which it is: `Source.cpp` renders `cube.Render()` first and `GLSkybox::getInstance().Render()` second. After drawing, the function sets the depth function back to `GL_LESS`, so nothing rendered afterward inherits the relaxed test.

## Following the Camera Without Following It

`GLSkybox::Update()` builds its matrices a little differently than `GLCube` does:

```cpp
matWorld = glm::translate(glm::mat4(1), vecPosition);
matView = glm::mat4(glm::mat3(Camera::getInstance().getViewMatrix()));
matProj = Camera::getInstance().getProjectionMatrix();
```

`vecPosition` is fixed at the origin and never changes, so `matWorld` stays put. The interesting part is the view matrix:

$$
V_{sky} = \text{mat4}\big(\text{mat3}(V_{camera})\big).
$$

Truncating the camera's view matrix to its rotation-only \(3\times3\) block and expanding it back to \(4\times4\) throws away translation while keeping orientation. The skybox rotates however the camera looks, but never moves away as the camera walks around the scene, which is exactly the illusion a sky needs: it should always feel infinitely far away, in every direction, no matter where you stand.

## A New Vantage Point

The camera's default position moves from \((0,5,8)\) to \((0,11,22)\), pulled back and lifted higher, and mouse sensitivity doubles from \(0.05\) to \(0.1\). `getViewMatrix()` and `getProjectionMatrix()` also start caching their results into `m_matView` and `m_matProjection` instead of only returning a local value, and two new public setters, `SetViewMatrix()` and `SetProjectionMatrix()`, arrive alongside them.

&nbsp;

Neither setter gets called anywhere in this commit. Like `brightColor`'s bloom math last post, they're wired in ahead of the feature that will actually need them.

## Down to One Cube Again

Last post's scene had three cubes, yellow, red, and green, scattered around so the new free camera would have something worth flying between. This commit removes two of them:

```cpp
GLCube cube(glm::vec4(1,1,0,1));
cube.Init();

// initialize skybox
GLSkybox::getInstance().Init();
```

Just the yellow cube remains, now standing inside an actual sky instead of a gray void. The extra cubes did their job for one post, proving the camera could move, and now that there's an environment worth looking at, the scene trades width for atmosphere.

## What We Have Now

The render loop gained a second citizen with its own update and draw calls, sharing the same camera the cube already uses:

$$
\text{cube.Render()} \;\longrightarrow\; \text{skybox.Render() (GL\_LEQUAL, drawn last)}.
$$

A few pieces are still sitting unused on purpose: `GLSkybox::BindCubemap()` and `UnbindCubemap()` are declared and never called outside `Render()`'s own internal binding, and the camera's new matrix setters are wired in with nothing yet driving them. `assimp`, on the other hand, actually gets removed from the project again this commit, its include and library paths pulled back out now that a skybox turned out not to need it; `stb` stays, since `TextureManager` does. The sky is real now; the next thing this series needs is something worth standing under it.
