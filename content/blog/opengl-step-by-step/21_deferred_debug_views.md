+++
title = "Deferred Debug Views: Finally Seeing What's Inside the G-Buffer"
date = 2020-02-18T18:03:00+05:30
tags = ["opengl", "rendering"]
description = "Tiling the G-buffer's position, normal, albedo, emission, brightness, and shadow-depth textures onto screen as small debug thumbnails, extracting the fullscreen quad into its own reusable class, and finally deleting the point lights that have been sitting unregistered since last post."
math = true
+++

# Deferred Debug Views: Finally Seeing What's Inside the G-Buffer

Every post since deferred rendering arrived has talked about position, normal, albedo, emission, and shadow-depth textures in the abstract, numbers packed into channels nobody could actually look at. This commit puts all six on screen at once, small tiled thumbnails layered over the final render, so the G-buffer stops being something you have to take on faith.

&nbsp;

{{< youtube 7r3g9BYLx5E >}}

&nbsp;

$$
\text{G-buffer, invisible} \;\longrightarrow\; \text{6 debug thumbnails, tiled on screen}
$$

## A Reusable Screen-Aligned Quad

The fullscreen quad that's been hardcoded directly into `PostProcess` since the very first post-processing pass finally moves into its own class:

```cpp
enum QuadDesc
{
    MAIN,
    POSITION,
    NORMAL,
    ALBEDO,
    EMISSION,
    BRIGHTNESS,
    SHADOW_DEPTH
};
```

`ScreenAlignedQuad::CreateScreenAlignedQuad(int id)` builds a different-sized quad depending on which of these it's asked for, `MAIN` still covers the whole screen, `-1` to `1` on both axes, but the other six each occupy a small third-of-the-screen tile instead. `PostProcess::Initialize()` now creates seven of them, one full-screen quad for the actual rendered image, and six small ones tiled across a `3×2` grid for debugging.

## Six Small Windows Into the G-Buffer

`PostProcess::DrawDebugBuffers()` runs after the normal render and draws each of the six textures into its own tile:

```cpp
glActiveTexture(GL_TEXTURE0);
glBindTexture(GL_TEXTURE_2D, m_PositionBuffer);
m_pDebugQuadPosition->RenderToScreenAlignedQuad();

glActiveTexture(GL_TEXTURE0);
glBindTexture(GL_TEXTURE_2D, m_NormalBuffer);
m_pDebugQuadNormal->RenderToScreenAlignedQuad();
```

Position, normal, albedo, emission, brightness, and shadow depth, all six get the same treatment, one after another. The shader doing the drawing, `psDeferredDebug.glsl`, does nothing clever at all:

```glsl
vec3 debugColor = texture2D(debugBuffer, vs_outTexcoord).rgb;
outColor = vec4(debugColor, 1.0f);
```

Sample the texture, show it, that's the entire shader. After every post since deferred rendering arrived describing what's supposed to be in these buffers, this is the first one where you can actually look at them.

## A General-Purpose Cleanup Helper

`Helper.h` is new, and small: a single templated function.

```cpp
template<typename T> void SAFE_DELETE(T*& a)
{
    delete a;
    a = nullptr;
}
```

`PostProcess`'s destructor, which used to repeat the same `if (ptr) { delete ptr; ptr = nullptr; }` block for every shader pointer, collapses down to one line each:

```cpp
SAFE_DELETE(m_pDeferredShader);
SAFE_DELETE(m_pBloomShader);
SAFE_DELETE(m_pPostFXShader);
```

With seven new `ScreenAlignedQuad` pointers added this same commit, that repetition would only have gotten worse without it.

## The Point Lights Are Actually Gone Now

Last post stopped registering the three point lights with `LightsManager` but still allocated them. This post removes them entirely, the members, the constructors, the destructor cleanup, all deleted from `Scene.h` and `Scene.cpp`. The scene also swaps its model, the Barbarian character is replaced with a metallic spaceship:

```cpp
data.path = "../Assets/models/Spaceship/Spaceship_Metallic.fbx";
```

A metal ship with actual emissive panels gives the position, normal, and emission debug tiles something more interesting to show than a plain character mesh would.

## Turning Up the Glow

Speaking of emission, `psNormalMapWSDeferred.glsl` multiplies it by `25.0f` on the way into the G-buffer this commit:

```glsl
gEmission = 25.0f * emissiveColor.rgb;
```

Combined with last post's `brightColor = Emission * 3.0f` in the lighting pass, the emissive channel is now boosted by a combined `75×` compared to two posts ago, enough to make sure whatever the spaceship's emissive texture marks as glowing actually reads as bright once bloom picks it up. Shadow darkness also eases up a little, `0.8` becomes `0.5` in `readShadowMap()`, a lighter shadow than last post's.

## Camera Rotation Behind a Right-Click

With six debug tiles now covering a good chunk of the screen, `MouseHandler()` stops rotating the camera on every mouse movement:

```cpp
if (glfwGetMouseButton(window, GLFW_MOUSE_BUTTON_RIGHT) == GLFW_PRESS)
{
    Camera::getInstance().ProcessMouseMovement(xoffset, yoffset);
}
```

Since the camera post, moving the mouse anywhere on screen spun the view. Now that a third of the screen is debug thumbnails rather than scene, camera rotation only happens while the right mouse button is held, so the cursor can pass over those tiles without the whole view spinning underneath it.

## What We Have Now

$$
\text{position, normal, albedo, emission, brightness, shadow depth} \;\rightarrow\; \text{6 tiles, drawn every frame}.
$$

Every buffer this series has built up since deferred rendering started is finally something you can point at on screen instead of something you have to trust the code is doing correctly. The point lights that lingered, unregistered, for a whole post are gone outright, and the one light left, the sun, now has a shinier subject to light.
