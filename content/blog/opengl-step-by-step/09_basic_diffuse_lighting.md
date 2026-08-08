+++
title = "Basic Diffuse Lighting: Normals Finally Earn Their Keep"
date = 2019-12-08T18:03:00+05:30
tags = ["opengl", "rendering"]
description = "Wiring up per-vertex normals, computed by Assimp three posts ago and discarded ever since, into a basic N·L diffuse term, with the world-space inverse-transpose trick, and finding the new shader quietly ignores its own texture sample."
math = true
+++

By the end of this post, the mesh shows actual lighting for the first time in this series: a simple grayscale shading term computed from the angle between each surface and a fixed light direction. It's not textured, it's not colored, it's just brightness, but it's the first commit in this series where the shape of the geometry itself affects what color a pixel is. Specular highlights and a proper lighting system are the obvious next posts; this is the one that gets normals into the pipeline at all.

&nbsp;

{{< youtube oPel5J8AHtk >}}

&nbsp;

$$
\text{flat texture color} \;\longrightarrow\; \text{grayscale } N\cdot L \text{ diffuse term}
$$

## Normals Finally Earn Their Keep

Back in the custom-mesh post, `Model::LoadModel()` requested `aiProcess_GenSmoothNormals` from Assimp and then threw the result away, because `VertexP` only had room for a position. That's fixed now. `Model::ProcessMesh()` reads the normal Assimp already computed:

```cpp
VertexPTN vertex;
vertex.position = glm::vec3(mesh->mVertices[i].x, mesh->mVertices[i].y, mesh->mVertices[i].z);
vertex.normal = glm::vec3(mesh->mNormals[i].x, mesh->mNormals[i].y, mesh->mNormals[i].z);
```

Three posts after Assimp started generating this data, something finally reads it.

## A Third Vertex Attribute

`VertexPTN` adds a `normal` field alongside position and UV:

```cpp
struct VertexPTN
{
    glm::vec3 position;
    glm::vec2 uv;
    glm::vec3 normal;
};
```

`Mesh::SetupMesh()` wires up a third vertex attribute to match:

```cpp
// normals
glEnableVertexAttribArray(2);
glVertexAttribPointer(2, 3, GL_FLOAT, GL_FALSE, sizeof(VertexPTN), (void*)offsetof(VertexPTN, normal));
```

Position at location `0`, UV at `1`, normal at `2`, the same incremental pattern every vertex format in this series has followed since the very first `VertexPC`.

## Transforming Normals Correctly: the Inverse Transpose

Normals can't just be multiplied by the world matrix the way positions are. A non-uniform scale that stretches a surface unevenly rotates its normal out of perpendicular if you transform it the naive way. The standard fix, and the one `Mesh::SetShaderVariables()` uses, is the inverse transpose of the world matrix:

```cpp
glm::mat4 worldInvTranspose = glm::inverseTranspose(world);
GLuint hWorldInvTranspose = glGetUniformLocation(shaderID, "matWorldInvTranspose");
glUniformMatrix4fv(hWorldInvTranspose, 1, GL_FALSE, glm::value_ptr(worldInvTranspose));
```

$$
\mathbf{M}_{normal} = \left(\mathbf{M}_{world}^{-1}\right)^{T}.
$$

The vertex shader applies it with the normal's `w` component set to \(0\), which is the standard way to transform a direction rather than a point, directions shouldn't be affected by translation:

```glsl
vs_outNormal = (matWorldInvTranspose * vec4(in_Normal, 0)).xyz;
```

## A Simple Dot Product

`psDiffuse.glsl` computes the actual lighting with one dot product:

```glsl
uniform vec3 lightDirection = vec3(0,0,-1);

float NdotL = clamp(dot(normalize(vs_outNormal), -lightDirection), 0, 1);
Diffuse = vec4(NdotL, NdotL, NdotL, 1);
```

$$
N\cdot L = \text{clamp}\big(\hat{n} \cdot (-\hat{l}),\ 0,\ 1\big)
$$

`lightDirection` describes which way the light is traveling, \((0,0,-1)\), into the screen. Negating it gives the direction back toward the light source, which is what the dot product with the surface normal actually wants: a surface facing the light gets a value near \(1\), a surface facing away gets clamped to \(0\). That single scalar becomes the output color directly, red, green, and blue all set to the same `NdotL`, which is why the result is grayscale rather than colored light.

## The Texture Sample That Doesn't Make It Out

`psDiffuse.glsl` still samples the diffuse texture:

```glsl
vec4 Ambient = vec4(0);
vec4 Diffuse = vec4(0);

Ambient = texture(texture_diffuse, vs_outUV);

float NdotL = clamp(dot(normalize(vs_outNormal), -lightDirection), 0, 1);
Diffuse = vec4(NdotL, NdotL, NdotL, 1);

outColor = Diffuse;
```

`Ambient` gets computed and never used anywhere after that. `outColor` comes from `Diffuse` alone, so the rendered result this commit is the lighting term by itself, not tinted by the model's actual texture. The shader also declares the full `Material` struct and its `material` uniform, `Albedo`, `Roughness`, `Metallic`, and never references any of them. Texture and material both ride along in this shader; only the normal actually reaches the screen.

## A Debugging Trace Left in the Old Shader

One more change in this diff has nothing to do with lighting and doesn't affect anything currently on screen. `psTextureMulti.glsl`, last post's shader, gets edited too:

```glsl
//Ambient = material.Albedo * texture(texture_diffuse, vs_outUV);
//Ambient = texture(texture_specular, vs_outUV);
Ambient = texture(texture_normal, vs_outUV);
```

The diffuse line gets commented out and the normal line, commented out since it was written, gets switched on. Since `Source.cpp` now sets `data.shader = "Diffuse"` instead of `"TextureMulti"`, this shader isn't even loaded this commit. It reads like a leftover from checking what the normal map actually looked like, visualized directly as color, before writing the real lighting math next door in `psDiffuse.glsl`.

## What We Have Now

$$
\text{Assimp normal} \;\rightarrow\; \text{world space (inverse transpose)} \;\rightarrow\; N\cdot L \;\rightarrow\; \text{grayscale outColor}.
$$

The mesh finally has shading instead of a flat fill, and the normal pipeline, per-vertex data, a third vertex attribute, a correctly transformed direction, is now in place for every lighting technique this series is clearly walking toward. The texture sample sitting unused in this shader is this post's version of the pattern by now: something gets wired up before it's actually connected to what reaches the screen.
