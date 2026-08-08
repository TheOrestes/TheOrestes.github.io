+++
title = "Tangent-Space Normal Mapping: Moving the Transform to the Light, Not the Normal"
date = 2020-01-07T18:03:00+05:30
tags = ["opengl", "rendering"]
description = "Flipping world-space normal mapping around: transforming light and view vectors into tangent space instead of the sampled normal into world space, using the fact that an orthogonal matrix's transpose is its inverse."
math = true
+++

Last post got a normal map into the lighting pipeline by transforming the sampled tangent-space normal into world space, then doing all the usual lighting math there. This post does almost the same lighting, with one thing flipped: instead of moving the normal into world space, it moves the light and view directions into tangent space and does the math there instead. Same result, same TBN matrix, used the other way around.

## Theory: What Tangent Space Actually Buys You

A normal map is authored in tangent space, a coordinate frame that belongs to each point on the surface itself, built from the tangent (`T`, aligned with the surface's texture-U direction), the bitangent (`B`, aligned with texture-V), and the normal (`N`, perpendicular to the surface). Every vertex on a mesh has its own version of this frame, because the surface faces a different way at every point.

&nbsp;

That local-ness is the entire point. A normal map painted once for a brick wall can be applied to any brick wall, front-facing, side-facing, wrapped around a cylinder, because "pointing straight out of the surface" in tangent space doesn't correspond to any fixed direction in the world. It's why a tangent-space normal map, viewed as a raw texture, looks almost uniformly pale blue-purple regardless of what the mesh underneath looks like: most surface detail points close to straight out, which is close to `(0,0,1)` in tangent space, and after the usual `[-1,1] → [0,1]` remap that's a consistent light blue-purple no matter which triangle it's sitting on.

&nbsp;

![Left to right: a diffuse texture, the corresponding normal map baked in tangent space, and that normal data applied to a sphere and rendered in object space](/images/blog/normalmap_tangent_vs_object_space.png)

&nbsp;

*Image: "NormalMaps.png" by Peter23, [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:NormalMaps.png), licensed under [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/).*

&nbsp;

Notice the middle and right panels are the same underlying normal data, just expressed in two different spaces. The tangent-space version, center, is flat and reusable, it doesn't know or care what shape it ends up on. The moment that data gets baked into object or world space, right, it stops being portable: colors now vary with the sphere's own orientation, and the exact same texture would be wrong if painted onto a mesh shaped differently or posed differently. Tangent space is what makes one normal map file usable across an entire model, or across many models, instead of needing a bespoke bake for every surface.

&nbsp;

Once the normal map itself is safely tangent-space, there are two ways to actually light a pixel with it: transform the sampled tangent-space normal out into world space, where the lights and camera already live (last post's approach), or transform the lights and camera into tangent space instead, and do the lighting math down there. This post is the second approach.

## The TBN Matrix, Used Backward

`vsNormalMapTS.glsl` builds `T`, `B`, and `N` exactly like last post, then does one thing differently:

```glsl
// pass "transpose" of matrix to fragment shader, this matrix can be used
// to tranform any vector from world space to tangent space.
// Transpose is used instead of "Inverse" because TBN matrix is composed of
// mutually perpendicular vectors, such matrix is called as orthogonal matrix.
// Inverse of orthogonal matrix is simply transpose of that matrix!
vs_outTBN = transpose(mat3(T,B,N));
```

Last post's `vs_outTBN` was `mat3(T,B,N)`, a matrix that converts tangent-space vectors into world space. This post passes its transpose instead, which converts the other direction, world space into tangent space, because `T`, `B`, and `N` are mutually perpendicular:

$$
M^{-1} = M^{T} \quad \text{when } M \text{ is orthogonal}.
$$

Transposing a matrix is far cheaper than inverting one in general, and for an orthogonal matrix it gives the exact same answer. That's the whole trick.

## Lighting in Tangent Space

`psNormalMapTS.glsl` uses that transpose to bring the world-space light and view directions down into tangent space, right where the sampled normal already lives:

```glsl
// Transform light direction into tangent space
vec3 TangentSpaceLightDir = normalize(vs_outTBN * -LightDir);

// diffuse
NdotLPoint = max(dot(texNormal, TangentSpaceLightDir), 0);
```

`texNormal` never leaves tangent space this time, it's compared directly against a light direction that's been moved to meet it. The specular loop does the same with the view direction, computed once outside the loop:

```glsl
vec3 TangentSpaceViewDir = normalize(vs_outTBN * viewDir);
```

and then transforms each light's direction into tangent space the same way before reflecting it off `texNormal`. `texNormal` itself still comes from the same line as last post, sampled and normalized straight from the texture, with the `[-1,1]` remap still sitting commented out beside it, unchanged.

## Reflection Still Needs the World

Skybox reflections can't happen in tangent space, a cubemap is sampled by a world-space direction, so this shader converts back:

```glsl
// Reflection (always happens in World Space)
vec3 worldNormals = normalize(transpose(mat3(vs_outTBN)) * texNormal);
vec3 viewReflection = normalize(reflect(viewDir, worldNormals));
Reflection = texture(texture_skybox, viewReflection);
```

$$
\left(M^{T}\right)^{T} = M.
$$

`vs_outTBN` is already the world-to-tangent transpose, so transposing it again hands back the original tangent-to-world matrix, exactly the one last post used directly. One matrix, flipped back and forth as needed, depending on which space a given term actually has to run in.

## What We Have Now

$$
\text{normal map (tangent space)} \;\xrightarrow{\text{TBN}^{-1}}\; \text{light, view} \quad\text{vs.}\quad \text{normal} \;\xrightarrow{\text{TBN}}\; \text{world space}.
$$

Both versions of this shader end up doing the same lighting on the same mesh; only which vectors get moved, and into which space, has changed. `Source.cpp` just points `data.shader` at `"NormalMapTS"` to pick this version over last post's. The two techniques exist side by side in this project now, not because one is broken, but because this series is walking through both ways of solving the same problem before moving on.
