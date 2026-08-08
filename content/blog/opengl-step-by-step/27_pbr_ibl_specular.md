+++
title = "PBR IBL Specular: Prefiltered Reflections Meet a BRDF Lookup Table"
date = 2020-03-29T18:03:00+05:30
tags = ["opengl", "rendering"]
description = "The PrefilterSpecmap and BRDFLut shaders that sat unused last post finally get loaded: a roughness-aware, mip-mapped reflection of the environment combines with a precomputed BRDF lookup table to complete image-based lighting's other half, indirect specular."
math = true
+++

Last post's irradiance map covered indirect *diffuse*, every surface's ambient light came from a blurred average of the whole sky. Indirect *specular* is the harder half: a mirror-smooth surface should show a sharp reflection of the environment, a rough one a soft blurred smear, and that reflection has to respond correctly to viewing angle the way direct specular already does. This commit wires up the two shaders that were sitting in the `Shaders/` folder unused since last post, `PrefilterSpecmap` and `BRDFLut`, to finish the job.

&nbsp;

{{< youtube gDRY3zfJ8gc >}}

&nbsp;

## Prefiltering the Environment, One Roughness Level at a Time

`HDRSkybox::InitPrefilteredSpecularCubemap()` renders the baked HDRI cubemap into a new cubemap with five mip levels, each one convolved for a different roughness value:

```cpp
unsigned int maxMipLevels = 5;
for (GLuint mip = 0; mip < maxMipLevels; ++mip)
{
    unsigned int mipWidth =  m_iPrefiltCubemapSize * std::pow(0.5f, mip);
    unsigned int mipHeight = m_iPrefiltCubemapSize * std::pow(0.5f, mip);

    float roughness = (float)mip / (float)(maxMipLevels - 1);
    glUniform1f(glGetUniformLocation(shaderID, "roughness"), roughness);
    // ... render all six faces at this mip level
}
```

Mip 0 is roughness 0, an untouched mirror reflection; mip 4 is roughness 1, thoroughly blurred. `PrefilterSpecmap.frag` builds each face by taking many samples of the environment biased toward the reflection lobe a surface of that roughness would actually show, rather than sampling uniformly:

```glsl
vec2 Xi = Hammersley(i, SAMPLE_COUNT);
vec3 H = ImportanceSampleGGX(Xi, N, roughness);
vec3 L = 2.0f * dot(V,H) * H - V;

float NdotL = max(dot(N,L), 0.0f);
if(NdotL > 0.0f)
{
    prefilteredColor += textureLod(CubemapTexture, L, mipLevel).rgb * NdotL;
    totalWeight += NdotL;
}
```

`Hammersley()` generates a low-discrepancy sequence, 1024 points spread evenly rather than clustered by chance, and `ImportanceSampleGGX()` warps each point toward the same GGX distribution the direct-lighting BRDF already uses. The result, per mip level, is:

$$
L_{\text{prefiltered}}(R, \text{roughness}) = \frac{\sum_k L_i(L_k)\,(N{\cdot}L_k)}{\sum_k (N{\cdot}L_k)}, \qquad H_k \sim \text{GGX}(\text{roughness}).
$$

A rough surface's reflection vector is genuinely unpredictable, so instead of guessing which exact direction to sample, this bakes the *average* of everything a surface at that roughness would plausibly reflect, once, at startup, into a texture that's just a `textureLod()` lookup away at runtime.

## A Lookup Table for the Rest of the Integral

Prefiltering only handles the environment's side of the specular equation. The other side, how much of that reflected light actually reaches the eye, depends on the same Fresnel and geometry terms direct lighting already uses, but integrated over the whole hemisphere rather than evaluated at one exact angle. Recomputing that integral per pixel every frame would be far too expensive, so `BRDFLut.frag` bakes it once into a small 2D texture instead, indexed by view angle and roughness:

```glsl
vec2 IntegrateBRDF(float NdotV, float roughness)
{
    // ... 1024-sample GGX importance-sampled loop
    A += (1.0 - Fc) * G_Vis;
    B += Fc * G_Vis;
    // ...
    return vec2(A / SAMPLE_COUNT, B / SAMPLE_COUNT);
}
```

$$
\text{DFG}(N{\cdot}V, \text{roughness}) = \Big(\tfrac{1}{N}\textstyle\sum (1-F_c)G_{vis},\ \ \tfrac{1}{N}\textstyle\sum F_c\, G_{vis}\Big) = (\text{scale}, \text{bias}).
$$

This is the split-sum trick: instead of one expensive integral over both the environment *and* the BRDF at once, split it into two separate, cheaper integrals, the prefiltered environment map and this lookup table, that get multiplied back together at runtime. `HDRSkybox::InitSpecularBrdfLUT()` renders this once into a 512×512, two-channel (`GL_RG16F`) texture, a scale and a bias value baked in per (angle, roughness) pair.

## Combining Them at Runtime

`DeferredLighting.frag`'s `main()` samples both new textures and multiplies them back together:

```glsl
const float MAX_REFLECTION_LOD = 4.0f;

vec3 prefilteredSpecColor = textureLod(texture_prefiltSpecular, viewReflection, Roughness * MAX_REFLECTION_LOD).rgb;
vec2 envBRDF = texture(texture_brdfLUT, vec2(max(dot(Normal, viewDir), 0.0f), Roughness)).rg;
vec3 IndirectSpecular = prefilteredSpecColor * ((Ks * envBRDF.x) + envBRDF.y);

vec3 Lo_Indirect = (IndirectDiffuse + IndirectSpecular) * Occlusion;
```

$$
L_{\text{indirect,spec}} = L_{\text{prefiltered}}(R,\text{roughness}) \times \big(K_s \cdot \text{scale} + \text{bias}\big).
$$

`Roughness * MAX_REFLECTION_LOD` picks which of the five prefiltered mip levels to sample, a smooth material reads mostly from mip 0, a rough one blends toward mip 4. The BRDF LUT's two channels scale and offset that color by how much of it actually reflects at this viewing angle. Indirect lighting is now genuinely complete: `Lo_Indirect` sums the diffuse contribution from the irradiance map and the specular contribution from these two new textures, both weighted by the same `Occlusion` value from the material's mask channel.

## A Few Other Adjustments

The packed mask texture now multiplies the material's scalar values instead of replacing them outright:

```glsl
vec3 maskColor = vec3(texture(texture_mask, vs_outUV));
Mask = vec3(material.Roughness * maskColor.r, material.Metallic * maskColor.g, material.Occlusion * maskColor.b);
```

A model with no mask texture still falls back to flat material values as before, but one that does have a texture now uses it as a per-pixel multiplier on top of whatever the material sliders are set to, rather than an all-or-nothing swap. Shadow strength deepens from `0.5f` to `0.85f`, a piano model joins the scene alongside the steampunk robot, and the render resolution jumps to 1920×1080, all cosmetic changes to show the new specular reflections off properly rather than anything structural.

## What We Have Now

$$
\text{irradiance map (diffuse)} \;+\; \text{prefiltered map} \times \text{BRDF LUT (specular)} \;=\; \text{complete image-based lighting}.
$$

Three posts ago, direct lighting traded a hand-tuned specular exponent for a real Cook-Torrance BRDF. Everything since has been extending that same physical grounding to light that doesn't come from a point or directional light at all, first diffuse, now specular. A surface in this scene now responds to the environment the same principled way it responds to the sun.

&nbsp;

*Both the diffuse irradiance convolution from last post and the prefiltered specular map and BRDF LUT covered here are heavily inspired by [LearnOpenGL](https://learnopengl.com/PBR/IBL/Diffuse-irradiance)'s PBR/IBL series, which the shader source comments reference directly.*
