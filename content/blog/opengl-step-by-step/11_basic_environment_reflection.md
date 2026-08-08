+++
title = "Basic Environment Reflection: The Mesh Finally Samples the Sky"
date = 2019-12-20T18:03:00+05:30
tags = ["opengl", "rendering"]
description = "Adding a mirror-style reflection term sampled straight from the skybox cubemap, which finally puts GLSkybox's BindCubemap()/UnbindCubemap() and a long-idle texture-unit counter to work."
math = true
+++

By the end of this post, the mesh doesn't just sit inside the skybox, it reflects it: a faint mirror-like sheen that shows the surrounding environment on its surface, blended in on top of the existing diffuse and specular lighting. Getting there closes out two threads this series has been carrying since much earlier posts without ever quite finishing them.

&nbsp;

{{< youtube QiZUE3RSsyM >}}

&nbsp;

$$
\text{Ambient} \cdot \text{Diffuse} + \text{Specular} \;\longrightarrow\; \text{Ambient} \cdot \text{Diffuse} + \text{Specular} + \text{Reflection}
$$

## Two Loose Threads Finally Get Used

`GLSkybox::BindCubemap()` and `UnbindCubemap()` have existed since the skybox post, declared and never called by anything outside the skybox's own `Render()`. This commit calls them from `Mesh::Render()` instead:

```cpp
// Bind skybox texture
glActiveTexture(GL_TEXTURE0 + (i + 1));
GLSkybox::getInstance().BindCubemap();

// ... draw call happens here ...

// unbind skybox texture
glActiveTexture(GL_TEXTURE0 + (i + 1));
GLSkybox::getInstance().UnbindCubemap();
```

That `i + 1` is the other loose thread. `i` is the counter from the multi-texturing post, incremented once for each of the specular and normal textures a material actually has, and never read by anything, until now. It decides which texture unit the skybox lands on, one past whatever albedo, specular, and normal already claimed:

```cpp
GLuint hCubeMap = glGetUniformLocation(shaderID, "texture_skybox");
glUniform1i(hCubeMap, i + 1);
```

A variable that's been quietly counting something for three posts finally has a reason to.

## Reflecting the View, Not the Light

Every lighting term so far has started from the light's direction. `psReflection.glsl` adds one that starts from the camera's instead:

```glsl
vec3 viewReflection = normalize(reflect(viewDir, vs_outNormal));
Reflection = texture(texture_skybox, viewReflection);
```

$$
\hat{r}_{view} = \text{reflect}(\hat{v},\ \hat{n}).
$$

`reflect()` here bounces the direction from the surface to the camera off the normal, the same operation the specular term used on the light direction, just aimed the other way. The result points toward whatever the surface would show if it were a perfect mirror, and sampling the skybox cubemap in that direction is literally asking "what does the sky look like from here." It's the same trick a chrome sphere in any renderer uses, applied to a mesh that already has a camera, a normal, and a cubemap sitting around from earlier posts.

## Blending It In

A full mirror reflection would overpower the lighting underneath it, so the term gets scaled down before it's added in:

```glsl
Reflection *= 0.3;

// Final Accumulation
outColor = Ambient * Diffuse + Specular + Reflection;
```

$$
\text{outColor} = (\text{Ambient} \cdot \text{Diffuse}) + \text{Specular} + 0.3 \cdot \text{texture}_{skybox}(\hat{r}_{view}).
$$

`0.3` isn't derived from anything physical, it's a tuning constant, enough reflection to read as a sheen without turning the mesh into a mirror ball. The specular highlight also gets a little softer this commit, its exponent drops from `64` to `32`, spreading the same highlight over a slightly wider area.

## What We Have Now

The render loop now has four lighting ingredients accumulating per pixel instead of three, and two structures that were built posts ago, the skybox's bind/unbind pair and the texture-unit counter, are both doing real work for the first time. Every mesh drawn through this shader is quietly aware of its own environment now, which is the kind of thing a proper lighting system tends to want available everywhere, not just in one reflection shader.
