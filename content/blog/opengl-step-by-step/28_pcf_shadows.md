+++
title = "PCF Shadows: A Hardware Comparison Sampler Softens the Edge"
date = 2020-04-05T18:03:00+05:30
tags = ["opengl", "rendering"]
description = "The shadow map itself doesn't change, only how it's read: the depth texture becomes a hardware comparison sampler, and a single depth lookup per fragment becomes a nine-tap average that turns a hard binary shadow edge into something closer to soft."
math = true
+++

After several posts rebuilding the lighting equation from the ground up, this one is small and focused: the shadow map that's been part of this engine since the shadow-mapping post gets a better filter. Every fragment near a shadow edge used to get one depth comparison and a hard yes-or-no answer. This commit takes nine comparisons instead of one, letting the edge blend rather than snap.

&nbsp;

{{< youtube i7ufhNqm7mY >}}

&nbsp;

## A Shadow Map That Compares Itself

`PostProcess::CreateShadowMappingBuffers()` adds two texture parameters to the existing depth buffer:

```cpp
glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_COMPARE_MODE, GL_COMPARE_REF_TO_TEXTURE);
glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_COMPARE_FUNC, GL_LEQUAL);
```

That turns the plain depth texture into what GLSL calls a comparison sampler. `DeferredLighting.frag` declares it as one to match:

```glsl
uniform sampler2DShadow shadowDepthBuffer;
```

A `sampler2DShadow` doesn't return a depth value the way a normal `sampler2D` does. Sampling it takes a third coordinate, the depth to compare *against*, and returns how much of that comparison passed, `1.0` for fully lit, `0.0` for fully shadowed, and anything in between where the hardware's own bilinear filtering blends across a texel boundary. The depth test that used to happen by hand in the shader now happens on the texture unit itself.

## Nine Taps Instead of One

`readShadowMap()` used to take one sample and branch on it, a fragment was either in shadow or it wasn't. It now averages a 3×3 grid of samples around the fragment's shadow-map coordinate:

```glsl
float factor = 0.0f;
float bias = max(0.05f * (1.0f - dot(Normal, dirLights[0].direction)), 0.005f);

for(int y = -1 ; y <= 1 ; y++)
{
    for(int x = -1 ; x <= 1 ; x++)
    {
        vec2 offsets = vec2(x * xOffset, y * yOffset);
        vec3 UVC = vec3(projCoords.xy + offsets, currentDepth - bias);
        factor += texture(shadowDepthBuffer, UVC);
    }
}

return 1.0 - (factor / 18.0f);
```

$$
\text{shadow} = 1 - \frac{1}{18}\sum_{x=-1}^{1}\sum_{y=-1}^{1} \text{compare}\big(\text{depthMap}(uv + \text{offset}_{x,y}),\ d_{\text{frag}} - \text{bias}\big).
$$

This is percentage-closer filtering: instead of asking "is this one point in shadow," it asks the same question at nine nearby points and blends the answers. A fragment sitting exactly on a shadow boundary now gets a value somewhere between fully lit and fully shadowed, softening what used to be a single hard edge into a narrow gradient. `xOffset`/`yOffset` are both `1/512`, one shadow-map texel at the map's current resolution.

## One Casualty: the Shadow Depth Debug View

The "Shadow Depth" entry in the Debug Pass panel, channel 3, stops working this commit. `main()`'s `shadowDepth` variable is set to a flat black instead of an actual sample:

```glsl
vec3 shadowDepth = vec3(0.0f);//vec3(texture2D(shadowDepthBuffer, vs_outTexcoord).r);
```

A `sampler2DShadow` can't be read with a plain `texture2D()` the way the debug view expects, it always performs the depth comparison rather than returning a raw depth value, so the old debug tap no longer means anything and is commented out rather than deleted.

## A New Cast of Materials

The scene swaps its steampunk robot and piano for two spheres, one wood, one rusted iron, standing beside the robot rather than replacing it:

```cpp
data.name = "Mannequin1";
data.path = "../Assets/models/Spheres/Sphere_Wood.fbx";
// ...
data2.path = "../Assets/models/Spheres/Sphere_RustedIron.fbx";
```

A rough wood dielectric next to a rough metal sphere is exactly the kind of pairing that shows off everything the last several posts have built, direct and indirect diffuse, direct and indirect specular, and now shadow edges that blend instead of stairstep, all in one frame.

## What We Have Now

$$
\text{one depth compare, hard edge} \;\longrightarrow\; \text{nine depth compares, soft edge}.
$$

The shadow map's resolution, projection, and bias are all exactly what they were in the shadow-mapping post several entries back. Only the read changed, one sample became nine, and a hardware feature most of this series hasn't touched yet, the comparison sampler, does the actual filtering for free.
