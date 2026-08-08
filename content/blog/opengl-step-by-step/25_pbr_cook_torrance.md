+++
title = "PBR: Cook-Torrance Replaces Blinn-Phong, One BRDF for Every Light"
date = 2020-03-15T18:03:00+05:30
tags = ["opengl", "rendering"]
description = "The material system trades a hand-tuned specular exponent for Roughness and Metallic, the G-buffer grows a fifth channel to carry them, and the lighting pass replaces Blinn-Phong with a Cook-Torrance BRDF built from a GGX normal distribution, Smith geometry term, and Fresnel-Schlick approximation."
math = true
+++

Every specular highlight this series has drawn so far came from the same trick: raise a reflection-vector dot product to some hand-picked power, 32 here, 128 there, whichever number happened to look right for that light at that moment. This commit replaces that trick entirely. The lighting pass gets a real bidirectional reflectance distribution function, Cook-Torrance, driven by two bounded, physically meaningful material properties, roughness and metallicness, instead of an exponent nobody could explain the value of.

&nbsp;

Physically based rendering earned its place as the industry-standard material model for exactly this reason: a Roughness/Metallic pair means one material definition looks correct under a sunset, a studio softbox, or this engine's own baked HDRI sky without touching a single number per light. That's the opposite of what this series' own Blinn-Phong pass has been doing, its specular exponent and attenuation formula have both been quietly retuned more than once just to keep one scene looking reasonable. PBR trades that kind of per-scene fiddling for a model grounded in how light actually scatters off a rough versus a smooth, metal versus dielectric surface, which is exactly why it's the default in Unreal, Unity, and every modern game engine's material editor. This commit lays the groundwork, direct point and directional lights running through a proper Cook-Torrance BRDF; a couple posts from now, that same material data feeds an image-based lighting pass that derives ambient diffuse and specular straight from the HDRI sky already baked into a cubemap, instead of the flat, hand-tuned reflection term currently sitting in the lighting shader.

## From a Roughness Color to Real Roughness and Metallic Values

`Material` used to describe surface response with a `vec4 Roughness` color, more decorative than physical. It's now two plain floats plus an occlusion and height value:

```cpp
m_colAlbedo = glm::vec4(1.0f);
m_colEmission = glm::vec4(0.0f);
m_fRoughness = 0.5f;
m_fMetallic = 0.5f;
m_fOcclusion = 1.0f;
m_fHeight = 0.0f;
```

Emission also splits out into its own color instead of sharing space with roughness, and the old `TEXTURE_SPECULAR`/`TEXTURE_NORMAL`/`TEXTURE_HEIGHT`/`TEXTURE_OCCLUSION` texture slots collapse into a single packed `TEXTURE_MASK`:

```cpp
TextureProperty m_pTexMask;   // R-Roughness, G-Metallic, B-Occlusion, A-Height
```

`Model::ProcessMesh()` still pulls this texture from Assimp's `aiTextureType_SPECULAR` slot, an artist authoring the model in a DCC tool still fills in what looks like a specular map, but the engine now reads its red, green, and blue channels as roughness, metallic, and occlusion instead of a specular tint. `Mesh::SetMaterialProperties()` sends the scalar values through as individual uniforms rather than one packed vec4:

```cpp
glUniform1fv(glGetUniformLocation(shaderID, "material.Roughness"), 1,  &(mat->m_fRoughness));
glUniform1fv(glGetUniformLocation(shaderID, "material.Metallic"), 1, &(mat->m_fMetallic));
glUniform1fv(glGetUniformLocation(shaderID, "material.Occlusion"), 1, &(mat->m_fOcclusion));
```

## A Fifth G-Buffer Channel

The deferred G-buffer, position, normal, albedo, emission, gains a mask attachment to carry those three values from the geometry pass to the lighting pass:

```cpp
glGenTextures(1, &m_MaskBuffer);
glBindTexture(GL_TEXTURE_2D, m_MaskBuffer);
glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB16F, horizRes, vertRes, 0, GL_RGB, GL_FLOAT, nullptr);
// ...
glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT4, GL_TEXTURE_2D, m_MaskBuffer, 0);
```

`NormalMapWSDeferred.frag` writes it, falling back to the material's flat scalars when the mesh has no packed mask texture:

```glsl
if(hasMask)
    Mask = vec3(texture(texture_mask, vs_outUV));
else
    Mask = vec3(material.Roughness, material.Metallic, material.Occlusion);

gMask = Mask;
```

The old specular value that used to ride in the normal buffer's alpha channel is gone; that channel is relabeled `HEIGHT` in a comment but nothing writes into it yet this commit, reserved rather than active.

## The Cook-Torrance BRDF

`DeferredLighting.frag`'s lighting math is rebuilt around three functions that together model how a microfacet surface reflects light. The normal distribution function estimates what fraction of a surface's microscopic facets are angled exactly toward the halfway vector between light and view:

```glsl
float NormalDistributionFunction_GGX(vec3 Normal, vec3 Half, float roughness)
{
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH2 = max(dot(Normal, Half), 0) * max(dot(Normal, Half), 0);

    float Dr = (NdotH2 * (a2 - 1.0f) + 1.0f);
    return a2 / max(PI * Dr * Dr, 0.001f);
}
```

$$
D_{GGX}(N,H,\alpha) = \frac{\alpha^2}{\pi\left((N\cdot H)^2(\alpha^2-1)+1\right)^2}, \qquad \alpha = \text{roughness}^2.
$$

The geometry function accounts for facets shadowing or blocking each other at grazing angles, computed once from the view direction and once from the light direction, then combined:

$$
k = \frac{(\text{roughness}+1)^2}{8}, \qquad G_{SchlickGGX}(x,k) = \frac{x}{x(1-k)+k}, \qquad G = G_{SchlickGGX}(N{\cdot}V,k)\cdot G_{SchlickGGX}(N{\cdot}L,k).
$$

And the Fresnel term captures how reflectivity rises toward grazing angles, starting from a base reflectance `F0` that's mostly flat and low for non-metals but takes on the albedo color itself for metals:

```glsl
vec3 F0 = vec3(0.04f);
F0 = mix(F0, Albedo, Metallic);

vec3 F = Fresnel_Schilck(max(dot(Half, viewDir), 0.0f), F0);
```

$$
F(\cos\theta, F_0) = F_0 + (1-F_0)(1-\cos\theta)^5.
$$

The three combine into the specular term, and a energy-conservation split keeps diffuse and specular from ever summing past what the surface actually received:

```glsl
vec3 Numerator = NDF * G * F;
float Denominator = 4.0f * max(dot(Normal, viewDir), 0.0f) * max(dot(Normal, LightDir), 0.0f);
vec3 Specular = Numerator / max(Denominator, 0.001f);

vec3 Ks = F;
vec3 Kd = (vec3(1) - Ks) * (1.0f - Metallic);

Lo += (Kd * Albedo / PI + Specular) * lightColor * intensity * atten * NdotL;
```

$$
L_o = \left(k_d\frac{\text{Albedo}}{\pi} + \frac{D\,G\,F}{4(N{\cdot}V)(N{\cdot}L)}\right)\cdot\text{radiance}\cdot(N{\cdot}L).
$$

A fully metallic surface has `Kd` collapse to zero, all of its response comes from the specular term and takes on the albedo's color via `F0`, which is exactly the metal/non-metal split PBR is built around. Point lights also pick up a tidier falloff along the way, `max(1/dist² - 1/radius², 0)`, an inverse-square attenuation that fades cleanly to zero at the light's radius instead of the patched-together formulas earlier posts cycled through.

## What We Have Now

$$
\text{specular exponent (32, 128, ...)} \;\longrightarrow\; \text{Roughness, Metallic} \;\rightarrow\; \text{Cook-Torrance BRDF (same equation, every light)}.
$$

Direct lighting, point and directional both, now runs through one physically grounded equation instead of two independently hand-tuned ones. What it doesn't do yet is light a surface from the environment itself, the HDRI sky baked into a cubemap several posts back still only contributes a flat, low-intensity reflection term. That's the gap the next couple of posts close: image-based diffuse and specular, sampling that same environment map to light every surface the way the sun and point lights already do here.
