+++
title = "Multi-Texturing: Specular and Normal Maps Load, But the Shader Still Ignores Them"
date = 2019-12-02T18:03:00+05:30
tags = ["opengl", "rendering"]
description = "Loading specular and normal textures into the same Material struct as last post's albedo, wiring three texture units for rendering, and finding the fragment shader still only samples one of them."
math = true
+++

# Multi-Texturing: Specular and Normal Maps Load, But the Shader Still Ignores Them

By the end of this post, `Material`'s specular and normal texture slots, declared two posts ago and empty ever since, actually get filled in from the model file. `Mesh::Render()` binds three texture units instead of one. None of that changes a single pixel on screen yet. The fragment shader that's supposed to do something with a specular highlight or a normal map still only reads the diffuse texture, the other two lines are written, commented out, sitting one keystroke away from the lighting posts this is clearly building toward.

$$
\text{one texture slot (albedo)} \;\longrightarrow\; \text{three texture slots loaded, one used}
$$

## Two More Slots Get Filled

`Model::ProcessMesh()` extends the diffuse-texture lookup from last post with the same pattern, twice more:

```cpp
unsigned int nSpecular = mat->GetTextureCount(aiTextureType_SPECULAR);
if (nSpecular > 0)
{
    mat->GetTexture(aiTextureType_SPECULAR, 0, &str);
    const int id2 = TextureManager::getInstannce().Load2DTextureFromFile(str.C_Str(), m_Directory);
    material->m_pTexSpecular.setID(id2);
    material->m_pTexSpecular.SetHasTexture(true);
    material->m_pTexSpecular.setType(TextureType::TEXTURE_SPECULAR);
    material->m_pTexSpecular.setName("texture_specular");
    material->m_pTexSpecular.setPath(str.C_Str());
}
```

The normal-map lookup right after it is identical apart from swapping `aiTextureType_SPECULAR` for `aiTextureType_NORMALS` and `m_pTexSpecular` for `m_pTexNormal`. Between last post and this one, three of `Material`'s six texture slots are now genuinely populated from whatever the model file actually specifies.

## Three Texture Units, Bound Every Frame

`Mesh::Render()` sets a sampler uniform for each texture that's present, same conditional pattern as before, now three times over:

```cpp
if (material->m_pTexSpecular.getHasTexture())
{
    ++i;
    glUniform1i(glGetUniformLocation(shaderID, "texture_specular"), 1);
}

if (material->m_pTexNormal.getHasTexture())
{
    ++i;
    glUniform1i(glGetUniformLocation(shaderID, "texture_normal"), 2);
}
```

That `i` is a new local variable, declared as `GLuint i = 0;` right before these checks and incremented once per texture found. Nothing reads it afterward, the texture unit numbers below are hardcoded `0`, `1`, and `2` regardless of what `i` adds up to, so it's counting something this function doesn't currently use the count for.

&nbsp;

The bind calls themselves run unconditionally, all three, whether or not a given slot actually has a texture:

```cpp
glActiveTexture(GL_TEXTURE0);
glBindTexture(GL_TEXTURE_2D, material->m_pTexAlbedo.getID());

glActiveTexture(GL_TEXTURE1);
glBindTexture(GL_TEXTURE_2D, material->m_pTexSpecular.getID());

glActiveTexture(GL_TEXTURE2);
glBindTexture(GL_TEXTURE_2D, material->m_pTexNormal.getID());
```

Cleanup at the end of `Render()` now unbinds all three units the same way, instead of just the one from last post.

## The Shader That Almost Uses Them

`psTextureMulti.glsl` declares all three samplers:

```glsl
uniform sampler2D texture_diffuse;
uniform sampler2D texture_specular;
uniform sampler2D texture_normal;
```

And then uses exactly one of them:

```glsl
Ambient = material.Albedo * texture(texture_diffuse, vs_outUV);
//Ambient = texture(texture_specular, vs_outUV);
//Ambient = texture(texture_normal, vs_outUV);
```

Those two commented-out lines are the most literal version yet of a pattern this series keeps running into: `brightColor` sat unused for two posts before getting math, `LoadCubemapFromFile()` sat unused since the second post, `SetViewMatrix()` is still waiting. Here, the lines that would use the new textures are already typed, in the file, directly below the one line that's live. Uncommenting either one and recompiling would presumably replace the diffuse output entirely rather than combine with it, since nothing here blends the three samples together yet, that math is still ahead too.

## One Word Changes in Source.cpp

The only change to `Source.cpp` in this whole commit is the shader name:

```cpp
data.shader = "TextureMulti";
```

Which, through the same path-building logic as the last two posts, resolves to `Shaders/vsTextureMulti.glsl` and `Shaders/psTextureMulti.glsl`. The vertex shader in that pair is byte-for-byte the same as last post's `vsTexture.glsl`; only the fragment shader actually changed.

## What We Have Now

$$
\text{Assimp} \;\rightarrow\; \text{3 texture slots loaded} \;\rightarrow\; \text{3 units bound} \;\rightarrow\; \text{1 sampled in the shader}.
$$

The gap between "loaded" and "used" is now explicit in the fragment shader itself, not just in an unused struct field somewhere. Specular highlights and normal-mapped lighting are the obvious next posts; the data for both is already sitting in GPU memory, bound to texture units 1 and 2, waiting for a shader that reads more than one line of it.
