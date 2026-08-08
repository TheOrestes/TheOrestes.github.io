+++
title = "Deferred Rendering: One Lighting Pass Instead of Many, and the HDR Pipeline Left Behind"
date = 2020-01-31T18:03:00+05:30
tags = ["opengl", "rendering"]
description = "Splitting mesh shaders into a geometry pass that fills a three-target G-buffer and a single lighting pass that reads it back, and finding that three posts of HDR, tone mapping, and bloom work don't come along for the ride."
math = true
+++

Every lighting shader so far has done the same thing: sample textures, loop over every point light, add up diffuse and specular and reflection, all inside the one fragment shader drawing that particular mesh. That means the same lighting loop runs again for every object, and again for every light, every time a pixel gets touched. This commit splits that in two: a geometry pass that just records what's at each pixel, position, normal, color, and a single lighting pass, run once per screen pixel, that reads those recordings back and does the actual lighting math exactly once no matter how many objects or lights are involved.

$$
\text{N objects} \times \text{M lights, computed per fragment} \;\longrightarrow\; \text{G-buffer} \;\rightarrow\; \text{1 lighting pass, per screen pixel}
$$

## How the G-Buffer Feeds the Lighting Pass

![Three geometry-pass shaders write into a three-attachment G-buffer (position, normal+specular, albedo), which a single fullscreen lighting pass reads back to produce the final screen color](/images/blog/deferred_pipeline_diagram.svg)

&nbsp;

*The geometry pass fills the G-buffer once per object; the lighting pass reads it back once per screen pixel.*

## Filling the G-Buffer

`PostProcess::CreateDeferredBuffers()` attaches three textures to one framebuffer instead of one:

```cpp
glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB16F, horizRes, vertRes, 0, GL_RGB, GL_FLOAT, nullptr);
glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, m_PositionBuffer, 0);

glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, horizRes, vertRes, 0, GL_RGBA, GL_FLOAT, nullptr);
glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT1, GL_TEXTURE_2D, m_NormalBuffer, 0);

glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, horizRes, vertRes, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT2, GL_TEXTURE_2D, m_AlbedoBuffer, 0);

GLuint attachments[3] = { GL_COLOR_ATTACHMENT0, GL_COLOR_ATTACHMENT1, GL_COLOR_ATTACHMENT2 };
glDrawBuffers(3, attachments);
```

Position and normal both need floating-point precision, `RGB16F` / `RGBA16F`, because world-space coordinates and directions routinely fall outside `[0,1]`. Albedo is ordinary 8-bit color, it's just a base color, nothing about it needs the extra range. `glDrawBuffers(3, ...)` is what turns this into a true multi-target write: one draw call from one shader fills all three textures in a single pass over the geometry.

## Packing Specular Into the Normal Buffer's Alpha Channel

Three attachments hold four pieces of data. `psNormalMapWSDeferred.glsl` writes the normal's three components into `gNormal.rgb` and then tucks the specular texture's red channel into the leftover alpha slot:

```glsl
gNormal.rgb = Normal;
gNormal.a = specColor.r;
```

Rather than opening a fourth render target for one scalar, the format that was already carrying a normal has room for one more number, and specular gets to ride along in it.

## The Normal-Map Remap Finally Gets Turned On

Both normal-mapping posts left the same line sitting commented out: the step that remaps a normal map's raw `[0,1]` texture color into the `[-1,1]` range a direction actually needs. This commit turns it on:

```glsl
vec3 texNormal = normalize(texture(texture_normal, vs_outUV) * 2.0 - 1.0).rgb;
```

Two posts of `// * 2.0 - 1.0` sitting next to the active line, and this is the one where it finally isn't commented out.

## One Lighting Pass Instead of Many

`psDeferredLighting.glsl` runs the same diffuse-and-specular point-light loop every lighting shader in this series has used, just fed by G-buffer samples instead of interpolated vertex output:

```glsl
vec3 Position = texture2D(positionBuffer, vs_outTexcoord).rgb;
vec4 NormalBufferColor = texture2D(normalBuffer, vs_outTexcoord);
vec3 Normal = NormalBufferColor.rgb;
float Specular = NormalBufferColor.a;

vec4 Albedo = texture2D(albedoBuffer, vs_outTexcoord);
```

The final accumulation changes shape along with the data feeding it:

```glsl
outColor = Albedo + DiffusePoint + SpecularPoint * Specular + Reflection * Specular;
```

$$
\text{outColor} = \text{Albedo} + \text{DiffusePoint} + \text{Specular}_{G}\cdot(\text{SpecularPoint} + \text{Reflection}).
$$

Albedo and diffuse are added rather than multiplied together the way `Ambient * DiffusePoint` used to work, and the specular scalar pulled from `gNormal.a` now does the job the live `texture_specular` sample used to do directly inside the mesh shader. Every mesh in the scene shares this exact same lighting pass; it runs once per pixel regardless of how many objects or lights contributed to that pixel's G-buffer values.

## What Didn't Come Along

The last three posts built an HDR color buffer, exposure tone mapping, gamma correction, and a full bloom extract-blur-composite pipeline. None of it runs this commit. `Application::Initialize()` calls `CreateDeferredBuffers()` where it used to call `CreateColorBrightnessBuffer()`, and `Application::Run()` calls `ExecuteDeferredRenderPass()` where it used to call `ExecuteBloomPass()`. `PostProcess` still has every function from both of those posts, `CreateColorBrightnessBuffer()`, `ExecuteBloomPass()`, `ExecutePostprocessPass()`, the exposure and gamma members, none of it is deleted, none of it is called.

&nbsp;

That has a direct consequence in `Scene::InitScene()`. The point lights that were tuned bright enough to need HDR just two posts ago, channel values of `5.0` designed to overflow a display's normal range and rely on tone mapping to bring them back down, drop to ordinary `1.0` colors with an explicit `SetLightIntensity(0.1f)` on each:

```cpp
m_pRedPointLight = new PointLightObject(glm::vec4(1, 0, 0, 1));
m_pRedPointLight->SetLightIntensity(0.1f);
```

With no tone-mapping pass catching overbright values on the way out, the lights get turned down at the source instead. The safety net is gone, so the lights stopped needing one.

## A Few Threads Close, Others Get Cut

`Mesh::PointLightIlluminance()` moves out of `Mesh` entirely and becomes `PostProcess::PointLightIlluminance()`, matching where lighting now actually happens. `Mesh::Render()` also drops its skybox-reflection binding altogether, the texture-unit counter that spent three posts going from unused, to counting something nothing read, to finally picking a texture unit for the skybox, is removed along with the code that used it: meshes in the geometry pass don't touch the skybox anymore, the lighting pass samples it once, for everyone.

&nbsp;

`psLightDeferred.glsl` and `psSkyboxDeferred.glsl` both still carry the brightness-threshold comment block from the bloom post, commented out rather than deleted:

```glsl
// Find out brightness for this fragment
//float brightness = dot(color.rgb, vec3(0.2126f, 0.7152f, 0.0722f));
//if(brightness > 1.0f)
//	brightColor = vec4(color.rgb, 1.0f);
```

Nothing in this architecture writes a `brightColor` anymore, there's no third bloom attachment in this G-buffer, but the comment describing how it used to work is still sitting there.

## What We Have Now

The geometry pass and the lighting pass are now two genuinely separate stages instead of one shader doing both jobs at once, which is the entire point of deferred rendering: lighting cost stops scaling with how many objects overlap a pixel and starts scaling with how many pixels are on screen. What it cost to get there this commit is everything the last three posts built on top of the old forward pipeline, still present in the code, just not part of this one's path from geometry to screen.
