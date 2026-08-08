+++
title = "PBR IBL Diffuse: Convolving the Sky Into an Irradiance Map"
date = 2020-03-22T18:03:00+05:30
tags = ["opengl", "rendering"]
description = "The flat, hand-tuned reflection term from last post gets replaced with real image-based lighting: the baked HDRI cubemap is convolved into a small irradiance map, sampled as ambient diffuse for every surface, and the G-buffer grows two more channels just to keep the sky and the scene from being lit the same way."
math = true
+++

Last post's Cook-Torrance BRDF made direct lighting, the sun and the point lights, physically grounded. Everything *not* directly lit still fell back on a flat `Reflection *= 0.02f` fudge sampled straight from the baked HDRI cubemap. This commit replaces that fudge with real image-based lighting: the environment itself becomes a diffuse light source, convolved once at startup into a small irradiance map and sampled per pixel from then on.

&nbsp;

{{< youtube EN0dRLDEXBs >}}

&nbsp;

## Convolving the Sky Into an Irradiance Map

`HDRSkybox::InitIrradianceCubemap()` runs once, right after the HDRI panorama gets baked into a cubemap, and produces a second, much smaller cubemap, 32×32 per face against the source's 512:

```cpp
for (GLuint i = 0; i < 6; ++i)
{
    glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X + i, 0, GL_RGB16F, m_iIrradiancemapSize, m_iIrradiancemapSize, 0, GL_RGB, GL_FLOAT, nullptr);
}
```

`Cubemap2Irradiance.frag` fills each face by integrating incoming light over the entire hemisphere above every direction, approximated as a Riemann sum over spherical coordinates:

```glsl
for(float phi = 0.0f ; phi < 2.0f * PI ; phi += sampleDelta)
{
    for(float theta = 0.0f ; theta < 0.5f * PI ; theta += sampleDelta)
    {
        vec3 tangentSample = vec3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta));
        vec3 sampleVec = tangentSample.x * Right + tangentSample.y * Up + tangentSample.z * N;

        irradiance += texture(CubemapTexture, sampleVec).rgb * cos(theta) * sin(theta);
        NrSamples++;
    }
}
irradiance = PI * irradiance * (1.0f / float(NrSamples));
```

$$
E(N) \approx \pi \cdot \frac{1}{N_{\text{samples}}} \sum_{\phi,\theta} L_i(\phi,\theta)\,\cos\theta\sin\theta.
$$

Each texel of the irradiance map ends up holding the average of everything the sky looks like from that direction's hemisphere, which is exactly what diffuse lighting needs: a rough surface scatters light from every incoming angle roughly equally, so what it reflects is proportional to the *average* incoming light, not any single ray of it. Thirty-two pixels a side is plenty, since the result is already a blurred average and never needs to be sharp.

## Indirect Diffuse Joins Direct Lighting

`DeferredLighting.frag`'s `main()` now computes two separate lighting contributions and adds them together. Direct lighting is exactly last post's `PointLightIlluminance()`/`DirectionalLightIlluminance()` Cook-Torrance sum, renamed `Lo_Direct`. Indirect lighting is new:

```glsl
vec3 F0 = vec3(0.04f);
F0 = mix(F0, Albedo, Metallic);
vec3 Ks = Fresnel_Schlick_Roughness(max(dot(Normal, viewDir), 0.0f), F0, Roughness);
vec3 Kd = (1.0f - Ks) * (1.0f - Metallic);

vec3 Irradiance = vec3(texture(texture_irradiance, Normal));
vec3 IndirectDiffuse = Kd * Irradiance * (Albedo / PI);

vec3 Lo_Indirect = IndirectDiffuse * Occlusion;
```

$$
K_s = F_{\text{Schlick,rough}}(N{\cdot}V, F_0, \text{roughness}), \qquad K_d = (1-K_s)(1-\text{Metallic}),
$$
$$
L_{\text{indirect}} = K_d \cdot E(N) \cdot \frac{\text{Albedo}}{\pi} \cdot \text{Occlusion}.
$$

The Fresnel term picks up a roughness-aware variant, `Fresnel_Schlick_Roughness()`, since ambient light arrives from every direction at once rather than one measurable angle, and the same energy-conservation split from direct lighting, `Kd` shrinking as a surface gets more metallic, applies here too. Sampling the irradiance map only needs the surface normal, no view-dependent reflection vector at all, which is the whole point of baking it as a convolution ahead of time instead of integrating the sky live every frame.

## The G-Buffer Learns to Tell Objects From Sky

Compositing direct and indirect lighting only where actual geometry exists, and leaving the sky untouched by either, needs the lighting pass to know which pixels are which. Two new G-buffer attachments carry that information: a `Skybox` buffer holding the raw HDRI color where the sky is visible, and an `ObjectID` buffer marking every pixel red for scene geometry or green for sky:

```glsl
// NormalMapWSDeferred.frag
gSkybox = vec3(0);
gObjectID = vec3(1,0,0);

// HDRISkybox.frag
gSkybox = texture(cubeMap, -vs_outTex).rgb;
gObjectID = vec3(0, 1, 0);
```

The lighting pass reads that marker back and decides what to output per pixel:

```glsl
if(dot(redChannel, ObjectID) == 1)
    Lo = Lo_Direct + Lo_Indirect;
else if(dot(greenChannel, ObjectID) == 1)
    Lo = Skybox;
```

Geometry gets the full direct-plus-indirect PBR result; sky pixels just pass their sampled HDRI color straight through, untouched by a lighting equation that was never meant to apply to the sky itself. The HDRI's own contribution to the bright/bloom buffer also gets excluded this commit, `brightness` is now measured from `Lo_Direct` alone rather than the final composited color, so an overexposed patch of sky can't bleed into the bloom pass the way a genuinely bright light source should.

## Debug Views Move Into the Lighting Shader Itself

The tiled debug quads from a few posts back, one screen-aligned rectangle per G-buffer channel, are gone. `DrawDebugBuffers()` and its seven `ScreenAlignedQuad` instances are removed entirely, replaced by a single `channelID` uniform the lighting shader branches on at the very end of `main()`:

```glsl
if(channelID == 0)      outColor = vec4(Lo,1);
else if(channelID == 1) outColor = vec4(Lo_Direct, 1);
else if(channelID == 2) outColor = vec4(IndirectDiffuse, 1);
// ...through Shadow Depth, Albedo, Position, Normal, Emission, Roughness, Metallic, Occlusion, Skybox, Object ID
```

The Scene UI's new "Debug Pass" panel exposes each option as a radio button, so inspecting any single stage of the lighting equation, direct only, indirect only, or any raw G-buffer channel, means picking a radio button instead of scanning a wall of tiles. Bloom and the final tonemap/gamma pass also merge this commit, `BeginBloomPrepass()`/`ExecuteBloomPass()` and the old standalone tonemap pass collapse into one `PostFX.frag` shader with a `DoBloom` toggle, run through a single `ExecutePostprocessPass()`.

## What We Have Now

$$
\text{flat }0.02\times\text{ reflection} \;\longrightarrow\; \text{convolved irradiance map} \;\rightarrow\; \text{ambient diffuse, weighted by the same Fresnel split as direct light}.
$$

Every surface in the scene now receives two kinds of physically grounded light instead of one: direct, from the sun and point lights, and indirect, from the environment itself. What's still missing is the other half of image-based lighting, indirect *specular*, a blurry reflection of the environment that sharpens as roughness drops toward zero. The new `PrefilterSpecmap` and `BRDFLut` shaders already sitting in the `Shaders/` folder this commit are exactly that groundwork, written but not yet loaded by any C++ code, which is what the next post wires up.
