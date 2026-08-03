+++
title = "HDRI: Turning a Real Photographed Sky Into a Cubemap, Once"
date = 2020-02-24T18:03:00+05:30
tags = ["opengl", "rendering"]
description = "Loading a real equirectangular HDR photograph and baking it into a cubemap at startup, giving the diffuse-texture loader its first real error handling, and undoing two posts' worth of emission boosts now that actual HDR lighting is doing the work."
math = true
+++

# HDRI: Turning a Real Photographed Sky Into a Cubemap, Once

Every skybox so far has been six images an artist picked to line up at the edges. This commit's sky comes from a single photograph instead, an HDR panorama of an actual place, wrapped once around a cube at startup and never touched again after that.

&nbsp;

{{< youtube Z1ZX76HToRw >}}

&nbsp;

$$
\text{6 hand-picked cube faces} \;\longrightarrow\; \text{1 HDR photograph} \;\rightarrow\; \text{baked cubemap (once, at startup)}
$$

## A Real Photograph Instead of Six Painted Faces

`HDRSkybox::Initialize()` loads exactly one file:

```cpp
m_tbo = TextureManager::getInstannce().Load2DTextureFromFile("leadenhall_market_2k.hdr", "../Assets/HDRI");
```

`leadenhall_market_2k.hdr` is an equirectangular HDR image, the kind captured with a real camera in a real location and flattened into a single wide rectangle, the same format real-time renderers and offline renderers both use to light scenes with actual photographed environments. `GLSkybox`, back several posts ago, needed six separately named face images; this needs one.

## The Same Cube, a Fourth Job

`HDRSkybox::InitCaptureCube()` builds the identical eight corners and thirty-six indices that have been `GLCube`, then `GLSkybox`, then `GLLight` in this series. This is its fourth role: a cube used purely as a rendering target, six faces to project the panorama onto, one at a time.

## Baking the Panorama Into Six Faces, Once

`InitCaptureCubemap()` renders that flat panorama onto the inside of the cube from six directions, one render per face, using a 90° field of view and a view matrix pointed straight down each axis:

```cpp
m_matCaptureProj = glm::perspective(glm::radians(90.0f), 1.0f, 0.1f, 10.0f);

m_matCaptureView[0] = glm::lookAt(glm::vec3(0,0,0), glm::vec3(-1,0,0), glm::vec3(0,1,0));
m_matCaptureView[1] = glm::lookAt(glm::vec3(0,0,0), glm::vec3(1,0,0), glm::vec3(0,1,0));
// ... four more, one per remaining axis
```

Each of the six passes binds a different cube face as the render target:

```cpp
glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_CUBE_MAP_POSITIVE_X + i, m_captureTBO, 0);
glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
glDrawElements(GL_TRIANGLES, 36, GL_UNSIGNED_INT, 0);
```

This all happens once, inside `Initialize()`, not once per frame. The panorama gets converted to a cubemap a single time at startup, and the actual skybox render every frame afterward just samples that already-baked cubemap, the same cheap lookup `GLSkybox` always did.

## Equirectangular to Direction

The conversion itself happens in `HDRI2Cubemap.frag`, one direction vector in, one panorama coordinate out:

```glsl
const vec2 invATan = vec2(0.1591f, 0.3183f);

vec2 SampleSphericalMap(vec3 v)
{
    vec2 uv = vec2(atan(v.z, v.x), asin(v.y));
    uv *= invATan;
    uv += 0.5f;
    return uv;
}
```

$$
u = \frac{\operatorname{atan2}(z,x)}{2\pi} + 0.5, \qquad v = \frac{\operatorname{asin}(y)}{\pi} + 0.5.
$$

`atan2(z,x)` gives the horizontal angle around the cube, `asin(y)` the vertical angle up or down, exactly the two angles that describe a point on a sphere. Scaling by `invATan`, \(1/2\pi\) and \(1/\pi\), and shifting by `0.5` maps those angles from radians into the `[0,1]` UV range the flat panorama texture actually uses. Every direction a cube face can look in gets a corresponding pixel in the original photograph.

## The Diffuse Loader Finally Checks If Loading Worked

`TextureManager::Load2DTextureFromFile()` also branches on whether the file is actually HDR:

```cpp
if (stbi_is_hdr(filename.c_str()))
{
    data = stbi_loadf(filename.c_str(), &width, &height, &bpp, 0);
    if (data != nullptr)
    {
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB32F, width, height, 0, GL_RGB, GL_FLOAT, (void*)data);
        // ...
    }
}
else
{
    data = stbi_load(filename.c_str(), &width, &height, &bpp, 0);
    if (data != nullptr)
    {
        // ... existing LDR path ...
    }
    else
    {
        std::cerr << filename.c_str() << " Texture loading failed!!" << std::endl;
        return -1;
    }
}
```

`GL_RGB32F` for the HDR branch, full 32-bit float per channel, even more headroom than the `RGB16F` buffers everywhere else in this pipeline. The more notable change is the `if (data != nullptr)` check on the ordinary LDR path. All the way back in the texturing-a-quad post, this function's `stbi_load()` call had no such check, "this step assumes the image is found and successfully decoded," as that post put it. Several dozen posts later, it finally isn't just an assumption.

## Two Boosts, Both Undone

Last two posts pushed the emission channel hard to make a spaceship's glow visible, `25×` in the geometry shader, another `3×` in the lighting pass. Both get reverted this commit:

```glsl
// psNormalMapWSDeferred.glsl
gEmission = emissiveColor.rgb;          // was 25.0f * emissiveColor.rgb

// psDeferredLighting.glsl
brightColor = Emission;                  // was Emission * 3.0f
```

With a real photographed environment now providing actual bright light instead of a flat procedural sky, the artificial boost that made one specific model glow isn't needed anymore. A few other values move in the same spirit: `Albedo` gets multiplied by `2.5f`, the directional light's specular exponent tightens from `32` to `128`, and the skybox reflection damping drops from a full `1.0f` back down to `0.2f`, all consistent with a much brighter, more detailed environment now sitting behind everything.

## Measuring What's Actually Happening

`Application::Run()` picks up a small FPS counter, printed to the console once a second:

```cpp
if (currTime - prevTime >= 1.0f)
{
    std::cout << "ms : " << 1000.0f / double(nFrames) << std::endl;
    std::cout << "FPS : " << nFrames << std::endl;
    nFrames = 0;
    prevTime += 1.0f;
}
```

`Source.cpp` pairs it with `glfwSwapInterval(0)`, turning off vsync so that counter actually reports how fast the frame is running rather than a number capped at the monitor's refresh rate. Last post's debug tiles also go quiet this commit, `DrawDebugBuffers()` is commented out rather than deleted, and `GLSkybox`'s calls in `Scene.cpp` get the same treatment now that `HDRSkybox` has replaced it, benched, not removed, the same pattern this series keeps repeating whenever one system takes over from another.

## What We Have Now

$$
\text{.hdr photograph} \;\rightarrow\; \text{equirectangular} \rightarrow \text{cubemap (baked once)} \;\rightarrow\; \text{sampled every frame like any other skybox}.
$$

The sky is no longer six colors an artist chose; it's a real place, captured once and reused every frame after. Everything downstream, reflections, emission, the overall brightness of the scene, gets tuned back down to match, because for the first time, the environment itself is supplying real light instead of standing in for it.
