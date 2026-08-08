+++
title = "Texturing the Custom Mesh: A Material System Arrives, and the Wireframe Goes Away"
date = 2019-11-26T18:03:00+05:30
tags = ["opengl", "rendering"]
description = "Reading UVs and a diffuse texture straight out of Assimp, wiring up a Material struct with room for five texture slots this commit doesn't use yet, and finally turning off the mesh's permanent wireframe."
math = true
+++

By the end of this post, the loaded mesh stops being a permanent wireframe and starts showing an actual diffuse texture, pulled straight out of the model file itself rather than typed into `Source.cpp` by hand. That's the visible change. The structural one is a new `Material` struct with six texture slots, albedo, specular, normal, height, occlusion, emission, only one of which gets wired up this commit. The other five exist purely so the lighting and PBR posts coming later in this series have somewhere to plug in.

&nbsp;

{{< youtube irXBg_Pgw74 >}}

&nbsp;

$$
\text{wireframe, no texture} \;\longrightarrow\; \text{filled mesh, diffuse texture, Material struct}
$$

## A New Vertex Format, Again

`VertexPT` (position plus UV) shows back up in `VertexStructures.h`, the same name and shape it had all the way back in the texturing-a-quad post, before the cube post swapped it out for `VertexPC`. `Mesh` switches from `VertexP` to `VertexPT`, and `SetupMesh()` gains a second vertex attribute for it:

```cpp
// vertex position
glEnableVertexAttribArray(0);
glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(VertexPT), (void*)0);

// texture coordinates
glEnableVertexAttribArray(1);
glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, sizeof(VertexPT), (void*)offsetof(VertexPT, uv));
```

Every mesh loaded from now on carries UVs, not just a position.

## Reading UVs Straight From Assimp

`Model::ProcessMesh()` now pulls texture coordinates out of the imported file the same way it already pulled positions:

```cpp
if (mesh->mTextureCoords[0])
{
    vertex.uv = glm::vec2(mesh->mTextureCoords[0][i].x, mesh->mTextureCoords[0][i].y);
}
else
{
    vertex.uv = glm::vec2(0, 0);
}
```

Assimp supports multiple UV channels per mesh; `mTextureCoords[0]` is the first one. A mesh that never had UVs authored, unlikely for a textured character model, but possible in general, falls back to `(0,0)` for every vertex rather than crashing on a null pointer.

## A Material Struct With Room to Grow

`Material.h` is new, and it's bigger than this commit needs:

```cpp
enum TextureType
{
    TEXTURE_ALBEDO,
    TEXTURE_SPECULAR,
    TEXTURE_NORMAL,
    TEXTURE_HEIGHT,
    TEXTURE_OCCLUSION,
    TEXTURE_EMISSION,
    TEXTURE_MAX_TYPE
};

struct Material
{
    TextureProperty m_pTexAlbedo;
    TextureProperty m_pTexSpecular;
    TextureProperty m_pTexNormal;
    TextureProperty m_pTexHeight;
    TextureProperty m_pTexOcclusion;
    TextureProperty m_pTexEmission;

    glm::vec4 m_colAlbedo;
    glm::vec4 m_colRoughness;
};
```

Six texture slots, and this commit only ever fills in one of them, `m_pTexAlbedo`. `m_colAlbedo` defaults to a light gray, \((0.8, 0.8, 0.8, 1.0)\), `m_colRoughness` to a dark one, \((0.1, 0.1, 0.1, 1.0)\), flat fallback values for properties that don't have a texture backing them yet.

&nbsp;

`VertexStructures.h` also finally gives `Texture`, forward-declared in `Mesh.h` since the previous post, an actual definition: an `id`, a `name`, and an `aiString path`. `Model::ProcessMesh()` even declares a `std::vector<Texture> textures;` local variable this commit. Nothing ever gets pushed into it, it's built and then ignored, because the material-loading code below reads a texture path from Assimp and writes straight into `material->m_pTexAlbedo` instead of going through that vector at all.

## Pulling a Texture Path Out of the Scene

The actual payoff is in `ProcessMesh()`, right after the vertex and index loops:

```cpp
aiMaterial* mat = scene->mMaterials[mesh->mMaterialIndex];
aiString str;

unsigned int nDiff = mat->GetTextureCount(aiTextureType_DIFFUSE);
if (nDiff > 0)
{
    mat->GetTexture(aiTextureType_DIFFUSE, 0, &str);
    const int id1 = TextureManager::getInstannce().Load2DTextureFromFile(str.C_Str(), m_Directory);
    material->m_pTexAlbedo.setID(id1);
    material->m_pTexAlbedo.SetHasTexture(true);
    material->m_pTexAlbedo.setType(TextureType::TEXTURE_ALBEDO);
    material->m_pTexAlbedo.setName("texture_diffuse");
    material->m_pTexAlbedo.setPath(str.C_Str());
}
```

Assimp doesn't just hand back geometry, it also parses the model's material definitions and can report which image file each one uses for its diffuse slot. That filename gets handed to the same `TextureManager::Load2DTextureFromFile()` that's loaded ordinary 2D textures since the very first texturing post. One `Material*` is passed down through `LoadModel()` → `ProcessNode()` → `ProcessMesh()` and shared across every sub-mesh a model contains, so a model with multiple differently-textured parts would currently have them all overwrite the same `Material`.

## The Wireframe Goes Away

`Mesh::Render()` comments out the line that's forced every loaded mesh into lines since last post:

```cpp
// glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
```

Not deleted, just switched off, the same way `GLCube` got benched rather than removed when this mesh pipeline first showed up. Right above it, the diffuse texture gets bound for drawing:

```cpp
if (material->m_pTexAlbedo.getHasTexture())
{
    glUniform1i(glGetUniformLocation(shaderID, "texture_diffuse"), 0);
}

glActiveTexture(GL_TEXTURE0);
glBindTexture(GL_TEXTURE_2D, material->m_pTexAlbedo.getID());
```

The sampler uniform only gets set when `hasTexture` is true, but the bind call itself runs either way. After the draw call, `glBindTexture(GL_TEXTURE_2D, 0)` unbinds it again, cleanup that wasn't there in the wireframe-only version.

## The Shader Tints What It Samples

The new `vsTexture.glsl` / `psTexture.glsl` pair looks close to the very first texturing shader from several posts back, position and UV in, UV forwarded out. The interesting part is in the fragment shader:

```glsl
struct Material
{
    vec4 Albedo;
    vec4 Roughness;
    vec4 Metallic;
};

uniform Material material;
uniform sampler2D texture_diffuse;

void main()
{
    vec4 Ambient = material.Albedo * texture(texture_diffuse, vs_outUV);
    outColor = Ambient;
}
```

$$
\text{outColor} = \text{Albedo} \odot \text{texture}(texture\_diffuse,\ uv)
$$

The sampled texture color gets multiplied component-wise by `material.Albedo` rather than shown on its own, so the default \((0.8,0.8,0.8,1.0)\) tint quietly darkens whatever the texture provides by twenty percent per channel. The shader's `Material` struct also declares a `Metallic` field that nothing on the C++ side ever sets, `Mesh::SetMaterialProperties()` only uploads `Albedo` and `Roughness`, so it's present in the shader and silent in practice.

## A New Model to Look At

`Source.cpp` swaps assets entirely:

```cpp
data.path = "../Assets/models/Barbarian/BarbNew.fbx";
data.shader = "Texture";
```

The Mannequin from last post is gone; a Barbarian model takes its place. `data.shader = "Texture"` runs through `StaticObject::Init()`'s path-building logic the same way the empty string did last post, except now it resolves to `Shaders/vsTexture.glsl` and `Shaders/psTexture.glsl` instead of the plain, colorless pair the Mannequin used.

## What We Have Now

$$
\text{Assimp material} \;\rightarrow\; \text{TextureManager} \;\rightarrow\; \text{material.m\_pTexAlbedo} \;\rightarrow\; \text{texture\_diffuse} \;\rightarrow\; \text{screen.}
$$

One texture slot out of six is live. `m_colRoughness` is uploaded to the shader but nothing samples or displays it yet, the shader's `Metallic` field has no CPU-side counterpart at all, and the `textures` vector `ProcessMesh()` builds every call still does nothing. The mesh finally looks like something instead of a cage of lines, and the material system underneath it has five more doors installed than it currently opens.
