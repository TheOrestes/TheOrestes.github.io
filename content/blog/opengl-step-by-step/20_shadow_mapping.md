+++
title = "Shadow Mapping: The Directional Light Scaffolding Finally Comes Alive"
date = 2020-02-12T18:03:00+05:30
tags = ["opengl", "rendering"]
description = "Activating the DirectionalLightObject scaffolding that's sat commented out since the lighting-system post, rendering a depth-only shadow map from the light's point of view, and sampling it back with a slope-scaled bias to avoid shadow acne."
math = true
+++

# Shadow Mapping: The Directional Light Scaffolding Finally Comes Alive

Every light in this series so far has been a point light, a colored bulb with a position and a falloff. This commit adds the other kind this series has been quietly set up for since the lighting-system post: a directional light, a sun with no position at all, just a direction. Getting one working also means rendering the scene a second time, from the light's point of view, just to know what it can and can't see.

&nbsp;

{{< youtube r5l0r9ftYPM >}}

&nbsp;

$$
\text{point lights only} \;\longrightarrow\; \text{directional light} + \text{depth-only shadow pass} \;\rightarrow\; \text{shadow-aware lighting}
$$

## The Directional Light Scaffolding Comes Alive

`LightsManager` has carried an entire commented-out parallel structure for `DirectionalLightObject` since the lighting-system post, a forward declaration, a vector, gather and get functions, all written and immediately disabled. This commit just removes the comment markers:

```cpp
void LightsManager::GatherDirectionalLights( DirectionalLightObject* obj )
{
    m_vecDirLights.push_back(obj);
    m_iNumDirLights = m_vecDirLights.size();
}
```

Every line was already there. `DirectionalLightObject` itself is new this commit, direction, color, intensity, plus two matrices that don't exist on `PointLightObject` at all: a view matrix and a projection matrix, the light's own camera.

## A View Matrix for a Light With No Position

A directional light has no position, sunlight doesn't originate from a point, it just arrives from a direction. But building a view matrix needs one anyway, so `DirectionalLightObject::Update()` invents one:

```cpp
glm::vec3 lightPosition = -m_vecLightDirection * 20.0f;
m_matWorldToLightViewMatrix = glm::lookAt(lightPosition, glm::vec3(0.0, 0.0f, 0.0f), glm::vec3(0.0f, 1.0f, 0.0f));
```

Walk backward along the light's direction far enough, and look at the origin, that's a perfectly good stand-in camera position for a light that doesn't actually have one. The projection matrix, built once in `Init()`, is orthographic rather than perspective:

```cpp
m_matLightViewToProjectionMatrix = glm::ortho(-fBounds, fBounds, -fBounds, fBounds, fNearPlane, fFarPlane);
```

$$
\text{parallel sun rays} \;\longrightarrow\; \text{orthographic projection (no perspective distortion)}.
$$

Perspective projection converges parallel lines toward a vanishing point, which is exactly wrong for something whose rays are already parallel. Orthographic projection keeps them parallel all the way through.

## A Depth-Only Framebuffer

`PostProcess::CreateShadowMappingBuffers()` builds a framebuffer that only stores depth, no color at all:

```cpp
glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT24, m_uiShadowDepthBufferWidth, m_uiShadowDepthBufferHeight, 0, GL_DEPTH_COMPONENT, GL_FLOAT, nullptr);
// ...
glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, m_ShadowDepthBuffer, 0);

// We only need the depth information when rendering the scene from the light's perspective so
// there is no need for a color buffer. A framebuffer object however is not complete without a color
// buffer so we need to explicitly tell OpenGL we're not going to render any color data.
glDrawBuffer(GL_NONE);
glReadBuffer(GL_NONE);
```

The wrap mode is `GL_CLAMP_TO_BORDER` with an explicit white border color, rather than the usual `GL_CLAMP_TO_EDGE`. Sampling outside the area the light actually covers returns the far-plane depth, which reads as "nothing's blocking the light here" instead of accidentally smearing edge pixels into shadow.

## Culling Front Faces to Avoid Peter-Panning

`BeginShadowPass()` renders into this depth-only buffer at its own resolution, `1024×1024`, separate from the main window:

```cpp
glViewport(0, 0, m_uiShadowDepthBufferWidth, m_uiShadowDepthBufferHeight);
glBindFramebuffer(GL_FRAMEBUFFER, m_fboShadow);
// ...
// To avoid peter-panning, only consider depth from back face instead of front face!
glCullFace(GL_FRONT);
```

"Peter-panning" is the name for a shadow that visibly detaches from the object casting it, a common artifact when a mesh's front faces write their own depth into the shadow map and then immediately self-shadow at glancing angles. Culling front faces during the shadow pass means only back faces get recorded, sidestepping that problem. `EndShadowPass()` puts both settings back:

```cpp
glCullFace(GL_BACK);
glBindFramebuffer(GL_FRAMEBUFFER, 0);
glViewport(0, 0, gWindowWidth, gWindowHeight);
```

Forgetting that viewport reset would leave every later pass rendering into a 1024×1024 rectangle instead of the actual window; this commit remembers to undo it.

## An Almost-Empty Shadow Shader

`vsShadowPass.glsl` only needs to answer one question, where does this vertex land in the light's clip space:

```glsl
mat4 matLightSpace = matLightViewToProjection * matWorldToLightView;
gl_Position = matLightSpace * matWorld * vec4(in_Position, 1.0);
```

`psShadowPass.glsl` is almost nothing at all:

```glsl
layout (location = 0) out float shadowDepth;

void main()
{
    // Not needed since OpenGL does it anyways!
    //shadowDepth = gl_FragCoord.z;
}
```

The fixed-function depth test already writes to the bound depth attachment on its own; a fragment shader that explicitly copies `gl_FragCoord.z` into a custom output would just be redoing work the GPU does for free. The output variable is declared and never assigned.

## Reading the Shadow Map Back

`psDeferredLighting.glsl`'s `readShadowMap()` takes a G-buffer position, transforms it into the light's clip space the same way the shadow pass did, and compares depths:

```glsl
vec4 lightSpacePosition = matLightViewToProjection * matWorldToLigthView * vec4(Position, 1.0f);
vec3 projCoords = lightSpacePosition.xyz / lightSpacePosition.w;
projCoords = projCoords * 0.5f + 0.5f;

float closestDepth = texture2D(shadowDepthBuffer, projCoords.xy).r;
float currentDepth = projCoords.z;

float bias = max(0.05f * (1.0f - dot(Normal, dirLights[0].direction)), 0.005f);
float shadow = (closestDepth < currentDepth - bias) ? 0.8f : 0.0f;
```

$$
\text{shadow} = \begin{cases} 0.8 & d_{closest} < d_{current} - \text{bias} \\ 0 & \text{otherwise} \end{cases}, \qquad \text{bias} = \max\big(0.05(1-\hat{n}\cdot\hat{l}),\ 0.005\big).
$$

`closestDepth` is whatever the shadow pass saw first from the light's point of view; `currentDepth` is how far this specific pixel actually is. If the pixel is farther away than whatever's blocking the light, it's in shadow. The bias grows as a surface tilts away from the light, the classic fix for shadow acne, self-shadowing noise that shows up when a surface is nearly edge-on to the light and depth precision isn't quite enough to tell "slightly in front" from "slightly behind." A shadow value of `0.8` rather than `1.0` also means shadowed areas darken rather than go fully black.

## The Point Lights Step Aside

`Scene::InitScene()` still creates all three point lights, same colors, same positions, same intensities, it just stops registering them:

```cpp
m_pRedPointLight = new PointLightObject(glm::vec4(1, 0, 0, 1));
m_pRedPointLight->SetLightIntensity(0.15f);
m_pRedPointLight->SetLightPosition(glm::vec3(2, 5, 5));
//LightsManager::getInstance()->GatherPointLights(m_pRedPointLight);
```

With `GatherPointLights()` commented out for all three, `numPointLights` is zero this commit; none of the point-light loops in the lighting shader have anything to iterate over. In their place, a single directional light:

```cpp
m_pMainDirectionalLight = new DirectionalLightObject(glm::vec4(1, 1, 1, 1));
m_pMainDirectionalLight->SetLightDirection(glm::vec3(0.5f, -1, -0.707f));
```

A new ground plane, `Plane_Oak.fbx` scaled up `20×`, is also added specifically as something for the character to cast a shadow onto, `Scene::RenderShadowMap()` renders both the character and the plane into the shadow pass, since both need to appear in it to shadow each other correctly.

## Guarding Texture Samples with Has-Flags

`psNormalMapWSDeferred.glsl` stops assuming every material has every texture:

```glsl
uniform bool hasDiffuse = false;
uniform bool hasSpecular = false;
uniform bool hasNormal = false;
uniform bool hasEmissive = false;

vec4 baseColor = hasDiffuse ? texture(texture_diffuse, vs_outUV) : vec4(1);
vec4 specColor = hasSpecular ? texture(texture_specular, vs_outUV) : vec4(0);
vec4 emissiveColor = hasEmissive ? texture(texture_emissive, vs_outUV) : vec4(0);
```

`Mesh::Render()` uploads each flag alongside the sampler-unit uniform it already set conditionally. Previously every material sampled all four textures unconditionally, whatever happened to be bound to that unit. Now the shader itself checks first and falls back to a sensible default, white for a missing diffuse map, black for a missing specular or emissive one, rather than sampling a texture that was never actually assigned.

## What We Have Now

$$
\text{shadow pass (light's view, depth only)} \;\rightarrow\; \text{G-buffer position} \;\rightarrow\; \text{shadow test} \;\rightarrow\; \text{ShadowColor} \;\times\; \text{(Albedo + lighting)}.
$$

The unshadowed version of the final composite line is still sitting commented out right above the new one, the same pattern this series keeps landing on when a formula changes but the old one isn't quite ready to be deleted. Reflection also loses its damping this commit, `0.25f` becomes a full `1.0f`, and the emission written to the bloom buffer gets multiplied by `3.0f`. A scene that was entirely point lights two posts ago now has exactly one light in it, and for the first time, that light casts an actual shadow.
