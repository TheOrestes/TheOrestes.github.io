+++
title = "Wireframe Overlay: Barycentric Coordinates Replace GL_LINE, Finally"
date = 2020-03-01T18:03:00+05:30
tags = ["opengl", "rendering"]
description = "Rendering a crisp, anti-aliased wireframe directly inside the shaded albedo using per-triangle barycentric coordinates and fwidth(), instead of the GL_LINE polygon mode this series flagged as unreachable dead code several posts ago."
math = true
+++

# Wireframe Overlay: Barycentric Coordinates Replace GL_LINE, Finally

Every wireframe this series has produced so far worked the same way: switch `glPolygonMode` to `GL_LINE` and the mesh stops being a shaded surface and becomes lines instead, one or the other, never both. This commit does something different, a wireframe drawn directly inside the normal shaded render, on top of the lit, textured surface rather than instead of it.

&nbsp;

{{< youtube 8qr20Hsk2KY >}}

&nbsp;

$$
\text{GL\_LINE (lines instead of shading)} \;\longrightarrow\; \text{barycentric edges (lines on top of shading)}
$$

## A Barycentric Coordinate Per Triangle Corner

`VertexPTNBT` gains a `barycentric` field, and `Model::ProcessMesh()` assigns each corner of every triangle one of three fixed values:

```cpp
if (k == 0) vertices[index].barycentric = glm::vec3(1, 0, 0);
else if (k == 1) vertices[index].barycentric = glm::vec3(0, 1, 0);
else if (k == 2) vertices[index].barycentric = glm::vec3(0, 0, 1);
```

$$
b_{v_0} = (1,0,0), \qquad b_{v_1} = (0,1,0), \qquad b_{v_2} = (0,0,1).
$$

This is the standard setup for barycentric-coordinate wireframe rendering, and it comes with a real constraint: a vertex shared between two different triangles would need two different barycentric values at once, one for each triangle it belongs to, which isn't possible if the same vertex is reused. The technique only works when every triangle owns its own unshared set of three vertices.

## Passed Straight Through, Interpolated By the Rasterizer

`vsNormalMapWSDeferred.glsl` doesn't transform the barycentric value at all, it just forwards it:

```glsl
vs_outBarycentric = in_Barycentric;
```

The interesting part happens automatically, between the vertex shader and the fragment shader: the GPU linearly interpolates varyings across a triangle. A component that's `1` at one corner and `0` at the other two ends up smoothly ranging from `1` at that corner down to exactly `0` along the entire opposite edge. Each of the three barycentric components hits zero along a different edge, which is exactly the signal needed to detect "how close is this pixel to an edge."

## Detecting Edges With fwidth() and smoothstep()

`psNormalMapWSDeferred.glsl`'s `edgeFactor()` turns that signal into a clean, anti-aliased edge test:

```glsl
float edgeFactor()
{
    vec3 d = fwidth(vs_outBarycentric);
    vec3 f = smoothstep(vec3(0), d * 0.75f, vs_outBarycentric);
    return min(min(f.x, f.y), f.z);
}
```

$$
d = \text{fwidth}(b), \qquad f = \text{smoothstep}(0,\ 0.75d,\ b), \qquad \text{edgeFactor} = \min(f_x, f_y, f_z).
$$

`fwidth()` measures how fast the barycentric coordinate changes from one screen pixel to the next, which shrinks as a triangle gets closer to the camera and grows as it recedes. Scaling the `smoothstep()` threshold by that value is what keeps the wireframe a consistent pixel width regardless of distance, instead of getting thicker up close and vanishing far away. Taking the minimum across all three components means the result is `0` right at any of the triangle's three edges and `1` everywhere else inside it.

## Blending Wireframe Color Into the Albedo

That factor blends between a fixed wireframe color and the mesh's actual lit color:

```glsl
gAlbedo = mix(vec3(0.8f, 1.0f, 0.0f), Ambient.rgb, edgeFactor());
```

$$
\text{gAlbedo} = \text{mix}(\text{wireColor},\ \text{Ambient},\ \text{edgeFactor}).
$$

Right at an edge, `edgeFactor()` is `0` and `gAlbedo` becomes the fixed yellow-green wireframe color; everywhere else it's the normal shaded surface. A simpler version of the same idea sits commented out directly above it:

```glsl
//if(any(lessThan(vs_outBarycentric, vec3(0.02f))))
//	gAlbedo = vec3(0,1,0);
//else
```

A flat threshold check instead of a distance-aware, anti-aliased one, the same kind of "simpler idea, tried and left in place, right next to the one that shipped" this series keeps running into. `GLCube`'s wireframe flag lost its only setter several posts ago; this is what actually replaces the idea it never got to demonstrate, drawn on top of a fully shaded mesh instead of instead of one.

## One More Value Walked Back

`psDeferredLighting.glsl`'s albedo multiplier from last post is gone:

```glsl
vec4 Albedo = texture2D(albedoBuffer, vs_outTexcoord);
```

The `2.5f` boost that compensated for the new HDRI environment's brightness is reverted, one more value in the ongoing back-and-forth of retuning the scene as each new piece of lighting infrastructure arrives.

## What We Have Now

$$
\text{per-corner barycentric} \;\rightarrow\; \text{interpolated across the triangle} \;\rightarrow\; \text{fwidth-scaled edge test} \;\rightarrow\; \text{wireframe} \times \text{lit surface}.
$$

The mesh finally has a wireframe view that doesn't cost the shaded render to see, both exist in the same pixel at once, blended by a single scalar computed entirely from how the triangle's own corners are labeled.
