+++
title = "Deferred Bloom: Emission Becomes the Fourth G-Buffer Channel"
date = 2020-02-06T18:03:00+05:30
tags = ["opengl", "rendering"]
description = "Adding an emission channel to the G-buffer so bloom works again under deferred shading, finally populating the Material struct's fourth texture slot, and finding a brand-new shader file pair that's never actually loaded."
math = true
+++

# Deferred Bloom: Emission Becomes the Fourth G-Buffer Channel

Bloom worked once already, back before deferred rendering arrived, because the mesh shader that computed final lit color could also decide right there whether that color was bright enough to glow. Deferred rendering split lighting into its own pass, so no shader touches an object's final color anymore until well after the object itself has been drawn. This commit reconnects the two: a fourth G-buffer channel carries "how much this pixel should glow" all the way from the geometry pass to the lighting pass to the bloom blur.

&nbsp;

{{< youtube BmDzJuXCTxs >}}

&nbsp;

$$
\text{3 G-buffer attachments} \;\longrightarrow\; \text{4 attachments (+ gEmission)} \;\rightarrow\; \text{bloom pass}
$$

## Bloom Needs a Fourth Channel

`PostProcess::CreateDeferredBuffers()` adds one more texture attachment alongside position, normal, and albedo:

```cpp
glGenTextures(1, &m_EmissionBuffer);
glBindTexture(GL_TEXTURE_2D, m_EmissionBuffer);
glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB16F, horizRes, vertRes, 0, GL_RGB, GL_FLOAT, nullptr);
glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT3, GL_TEXTURE_2D, m_EmissionBuffer, 0);

GLuint attachments[4] = { GL_COLOR_ATTACHMENT0, GL_COLOR_ATTACHMENT1, GL_COLOR_ATTACHMENT2, GL_COLOR_ATTACHMENT3 };
glDrawBuffers(4, attachments);
```

`RGB16F`, same floating-point format as the position buffer, for the same reason: an emissive or overbright value can legitimately exceed `1.0`, and this texture needs to hold that value without clipping it.

## Emission Finally Gets a Real Texture

`Material` has carried six texture slots since the very first material post, albedo, specular, normal, height, occlusion, emission, and only filled in the first three. `Model::ProcessMesh()` adds the fourth:

```cpp
unsigned int nEmissive = mat->GetTextureCount(aiTextureType_EMISSIVE);
if (nEmissive > 0)
{
    mat->GetTexture(aiTextureType_EMISSIVE, 0, &str);
    const int id4 = TextureManager::getInstannce().Load2DTextureFromFile(str.C_Str(), m_Directory);
    material->m_pTexEmission.setID(id4);
    material->m_pTexEmission.SetHasTexture(true);
}
```

Same lookup pattern as albedo, specular, and normal before it, `Mesh::Render()` binds it to texture unit `3` the same conditional way the others are bound. Four of `Material`'s six slots are genuinely populated now; height and occlusion are still waiting.

## Two Ways Emission Gets Filled

The character mesh has an actual emissive texture to sample, so `psNormalMapWSDeferred.glsl` just writes it straight into the new G-buffer output:

```glsl
gEmission = emissiveColor.rgb;
```

`psLightDeferred.glsl` and `psSkyboxDeferred.glsl` don't have an emissive texture to sample, so they fall back to the exact threshold formula the original bloom post wrote:

```glsl
float brightness = dot(gAlbedo, vec3(0.2126f, 0.7152f, 0.0722f));
if(brightness > 1.0f)
    gEmission = gAlbedo;
else 
    gEmission = vec3(0.0f, 0.0f, 0.0f);
```

$$
\text{gEmission} = \begin{cases}\text{gAlbedo} & L(\text{gAlbedo}) > 1 \\ \mathbf{0} & \text{otherwise}\end{cases}.
$$

The same luminance formula that's shown up in this series before is back for a third role, now deciding what counts as "emissive" for the light-marker cubes and the skybox specifically. With the point lights currently sitting at unit color values scaled by a `0.15` intensity, none of them actually cross the `1.0` threshold yet, so this branch has the same "written, doesn't fire with the current scene" status the very first version of this formula had back in the camera post.

## The Lighting Pass Just Relays It

`psDeferredLighting.glsl` reads the new `emissiveBuffer` and hands it straight to a second output with no threshold check of its own:

```glsl
layout (location = 1) out vec4 brightColor;
// ...
vec4 Emission = texture2D(emissiveBuffer, vs_outTexcoord);
// ...
brightColor = Emission;
```

The thresholding already happened upstream, in whichever geometry-pass shader filled `gEmission` for that pixel. The lighting pass's job is just to carry that value forward into its own `outColor` / `brightColor` pair, the exact shape the bloom pass expects to read from.

## Three Passes, Three Shaders

`Application::Run()` now brackets the deferred lighting pass inside a bloom-buffer render target instead of drawing straight to the screen:

```cpp
m_pPostFX->BeginBloomPrepass();
m_pPostFX->ExecuteDeferredRenderPass();
m_pPostFX->EndBloomPrepass();

m_pPostFX->ExecuteBloomPass();
```

`PostProcess` used to reuse a single `m_pShader` pointer across every post-process pass, reassigning whichever shader `SetupScreenQuad()` created most recently. With deferred lighting and bloom both active in the same frame now, one shared pointer can't cover both, so `PostProcess` splits it into three: `m_pDeferredShader`, `m_pBloomShader`, and `m_pPostFXShader`. All three get created up front; only the first two are actually used this commit; `ExecutePostprocessPass()`, the plain kernel-based post-process pass from a few posts back, isn't called in `Application::Run()` at all anymore, though its shader still gets allocated every startup.

## A New Shader File Nobody Loads

This commit adds two new files, `vsPostProcess_Bloom.glsl` and `psPostProcess_Bloom.glsl`. Nothing in `PostProcess.cpp` constructs a `GLSLShader` pointing at either filename, `m_pBloomShader` loads `Shaders/vsBloom.glsl` and `Shaders/psBloom.glsl`, the pre-existing pair, not the new one. Meanwhile `psBloom.glsl` itself, the shader that's actually running, loses its tone mapping this commit:

```glsl
// exposure tone mapping
//vec3 mapped = vec3(1.0f) - exp(-screenColor.rgb * exposure);

// Gamma correction
//mapped = pow(mapped, vec3(1.0f / gamma));
outColor = screenColor; //vec4(mapped, 1.0f);
```

`psPostProcess_Bloom.glsl`, the file nothing loads, contains exactly the tone-mapped version of this shader, exposure curve, gamma correction, and all seven post-processing kernels intact. It reads like a copy of `psBloom.glsl` saved under a new name right before the original got its tone mapping switched off, left behind rather than wired in.

## What We Have Now

$$
\text{gEmission (4th G-buffer target)} \;\rightarrow\; \text{brightColor (lighting pass)} \;\rightarrow\; \text{blur} \;\rightarrow\; \text{screenColor (no tone mapping this commit)}.
$$

Bloom is technically reconnected end to end again, geometry pass to lighting pass to blur, four G-buffer channels doing the job three used to. Whether the picture it produces is tone-mapped or not depends entirely on which of two nearly identical shader files happens to get loaded, and this commit is loading the one that isn't.
