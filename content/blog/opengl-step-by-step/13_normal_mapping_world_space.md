+++
title = "World-Space Normal Mapping: Tangents Earn Their Keep, and Reflection Returns"
date = 2020-01-01T18:03:00+05:30
tags = ["opengl", "rendering"]
description = "Reading the tangent and bitangent data Assimp has computed since the custom-mesh post to build a per-vertex TBN matrix, sampling a real normal map for the first time, and bringing last post's reflection term back into the final sum."
math = true
+++

# World-Space Normal Mapping: Tangents Earn Their Keep, and Reflection Returns

By the end of this post, surface detail comes from a normal map instead of just the mesh's own geometry, small bumps and creases that were never modeled as actual triangles start showing up in the lighting. Getting there means reading two pieces of data Assimp has been computing since the very first custom-mesh post and throwing away every time since.

&nbsp;

{{< youtube nmfwUIbsuXM >}}

&nbsp;

$$
\text{geometric normal only} \;\longrightarrow\; \text{normal map} \;\rightarrow\; \text{TBN} \;\rightarrow\; \text{world-space normal}
$$

## Tangents Finally Earn Their Keep

`Model::LoadModel()` requested `aiProcess_CalcTangentSpace` from Assimp all the way back when this series first started loading files, and nothing ever read the result. `Model::ProcessMesh()` finally does:

```cpp
if (mesh->mTangents || mesh->mBitangents)
{
    vertex.tangent = glm::vec3(mesh->mTangents[i].x, mesh->mTangents[i].y, mesh->mTangents[i].z);
    vertex.binormal = glm::vec3(mesh->mBitangents[i].x, mesh->mBitangents[i].y, mesh->mBitangents[i].z);
}
```

Same story as the vertex normals two posts ago: Assimp had already done the work, the vertex format just didn't have anywhere to put it yet.

## Two More Vertex Attributes

`VertexPTNBT` extends `VertexPTN` with exactly that room:

```cpp
struct VertexPTNBT
{
    glm::vec3 position;
    glm::vec2 uv;
    glm::vec3 normal;
    glm::vec3 tangent;
    glm::vec3 binormal;
};
```

`Mesh::SetupMesh()` wires up two more vertex attributes to match, binormal at location `3`, tangent at `4`, continuing the same incremental layout every vertex format in this series has used since the first `VertexPC`.

## Building a TBN Matrix in the Vertex Shader

Normal maps store their detail in tangent space, aligned to the surface's own UV directions, not world space. `vsNormalMapWS.glsl` transforms tangent, bitangent, and normal into world space and packs all three into one matrix:

```glsl
vec3 T = normalize(vec3(matWorld * vec4(in_Tangent, 0)));
vec3 B = normalize(vec3(matWorld * vec4(in_BiNormal, 0)));
vec3 N = normalize(vec3(matWorld * vec4(in_Normal, 0)));

vs_outTBN = mat3(T,B,N);
```

$$
\text{TBN} = \big[\ \hat{T}\ \ \hat{B}\ \ \hat{N}\ \big] \quad \text{(world space)}.
$$

That matrix travels to the fragment shader as an interpolated `mat3` varying, `out mat3 vs_outTBN`, ready to move anything sampled from a tangent-space texture into the same space the lighting math already works in.

## Sampling the Normal Map, Almost Correctly

`psNormalMapWS.glsl` samples the normal map and immediately runs into the usual wrinkle with normal maps: texture colors live in `[0,1]`, but directions need `[-1,1]`.

```glsl
vec3 texNormal = normalize(texture(texture_normal, vs_outUV).rgb);// * 2.0 - 1.0);
```

The remap that would actually do that, `* 2.0 - 1.0`, is written right there in the same line, commented out. As it stands, `texNormal` is built straight from the raw `[0,1]` texture color. Whatever comes out of that gets carried into world space through the TBN matrix and used everywhere the geometric normal used to be:

```glsl
vec3 Normal = normalize(vs_outTBN * texNormal);
```

Every `NdotL`, every specular `reflect()`, every reflection lookup in this shader now reads from `Normal` instead of the plain vertex normal.

## Reflection Comes Back

Last post, the environment reflection term was fully computed and then commented out of the final sum. This post, it's back in:

```glsl
Reflection *= 0.15;

// Final Accumulation
outColor = Ambient * DiffusePoint + SpecularPoint + Reflection;
```

Same skybox lookup as before, just a softer multiplier, `0.15` instead of last post's `0.3`, and this time the line actually adds it into `outColor`.

## What We Have Now

$$
\text{texture\_normal} \;\rightarrow\; \text{TBN} \;\rightarrow\; \text{world-space normal} \;\rightarrow\; \{\text{Diffuse, Specular, Reflection}\}.
$$

The model also moves up slightly this commit, `(0,2,0)` instead of the origin, and the three point lights get repositioned and recolored rather than left where they were. None of that changes the pipeline, it's just giving the new normal map something better to catch light from. Two long-idle pieces of Assimp data are doing real work now, and one term that got shelved last post is back, just turned down.
