+++
title = "Framebuffers Arrive: A Post-Process Pass, and a Class That Never Gets Compiled"
date = 2020-01-13T18:03:00+05:30
tags = ["opengl", "rendering"]
description = "Restructuring main() into Application and Scene classes, rendering the whole scene into an offscreen framebuffer for a post-process pass, and finding a dedicated Framebuffer class, plus seven post-processing kernels, that never actually run."
math = true
+++

By the end of this post, the scene doesn't draw straight to the screen anymore. It draws into a texture first, then a second pass draws a fullscreen quad sampling that texture onto the actual screen. That's the standard shape of every post-processing effect that's ever existed, bloom, color grading, screen-space anything, and this commit builds the plumbing for it without turning any of the actual effects on yet.

$$
\text{scene} \;\rightarrow\; \text{screen} \quad\longrightarrow\quad \text{scene} \;\rightarrow\; \text{framebuffer texture} \;\rightarrow\; \text{fullscreen quad} \;\rightarrow\; \text{screen}
$$

## The Scene Moves Out of main()

`main()` has owned every object in this series directly since the very first post. That ends here. `Application` now owns a `Scene` and a `PostProcess`:

```cpp
void Application::Initialize()
{
    m_pScene = new Scene();
    m_pScene->InitScene();

    m_pPostFX = new PostProcess();
    m_pPostFX->SetupScreenQuad();

    m_pPostFX->CreateColorDepthStencilBuffer(gWindowWidth, gWindowHeight);
}
```

`Scene::InitScene()` is almost a direct cut-and-paste of what used to live in `main()`, the static object, the three point lights, the skybox. `main()` itself shrinks down to creating an `Application` and calling two functions on it. One casualty of the cleanup: the R, G, and B key handlers that changed the clear color, present since this series' very first post, are deleted outright. The clear color is just white now, hardcoded in `Application::Run()`.

## Rendering Into a Texture Instead of the Screen

`PostProcess::CreateColorDepthStencilBuffer()` builds an FBO with a color texture attachment and a combined depth-stencil renderbuffer:

```cpp
glGenFramebuffers(1, &m_fbo);
glBindFramebuffer(GL_FRAMEBUFFER, m_fbo);

glGenTextures(1, &m_colorBuffer);
glBindTexture(GL_TEXTURE_2D, m_colorBuffer);
glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, horizRes, vertRes, 0, GL_RGB, GL_UNSIGNED_BYTE, nullptr);
glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, m_colorBuffer, 0);

glGenRenderbuffers(1, &m_rbo);
glBindRenderbuffer(GL_RENDERBUFFER, m_rbo);
glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, horizRes, vertRes);
glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, m_rbo);
```

`BeginRTPass()` and `EndRTPass()` bracket the ordinary scene render, binding that framebuffer instead of the default one, then unbinding it again:

```cpp
m_pPostFX->BeginRTPass();
m_pScene->Update(dt);
m_pScene->Render();
m_pPostFX->EndRTPass();

m_pPostFX->ExecutePostprocessPass();
```

Between `BeginRTPass()` and `EndRTPass()`, the scene renders exactly like it always has, it just doesn't know its output is landing in a texture instead of the window.

## A Fullscreen Quad, One More Reuse of VertexPT

`ExecutePostprocessPass()` draws six vertices covering the entire screen in normalized device coordinates, `(-1,-1)` to `(1,1)`, and samples the captured color texture across them:

```cpp
m_vertices[0] = VertexPT(glm::vec3(-1, 1, 0), glm::vec2(0, 1));
m_vertices[1] = VertexPT(glm::vec3(-1, -1, 0), glm::vec2(0, 0));
m_vertices[2] = VertexPT(glm::vec3(1, -1, 0), glm::vec2(1, 0));
```

`VertexPT`, position plus UV, is doing yet another job in this series, the same struct that textured the very first quad now carries the two triangles that cover the whole viewport for a post-process pass.

## A Framebuffer Class That Never Gets Compiled

This commit also adds a whole new `Framebuffer` class, 234 lines, with a constructor that takes a `FramebufferType`, a `CreateFrameBuffer()`, `Bind()`, `Unbind()`, and a getter for its color texture. It's a clean, reusable abstraction for exactly what `PostProcess` needs. `GLCube.vcxproj` adds four new source files to the actual build this commit, `Application.cpp`, `PostProcess.cpp`, `GLQuad.cpp`, `Scene.cpp`. `Framebuffer.cpp` isn't among them. Whatever this class was meant to replace, `PostProcess` still builds its own framebuffer by hand, with the exact same sequence of `glGenFramebuffers` / `glFramebufferTexture2D` / `glRenderbufferStorage` calls duplicated directly inside it.

&nbsp;

`Framebuffer::CreateFrameBuffer()` also carries an entire commented-out `switch (m_enumType)` block, five cases, `COLOR`, `DEPTH`, `DEPTH_STENCIL`, `COLOR_DEPTH`, `COLOR_DEPTH_STENCIL`, each building a differently-configured framebuffer depending on what the caller asked for. Above that switch, uncommented, sits one fixed path that always creates a color texture plus a depth-stencil renderbuffer, regardless of what `FramebufferType` was passed in. The flexible version is fully written and sitting right there; the class using it isn't even part of the build.

## Seven Post-Processing Effects, Zero of Them Running

`psPostProcess.glsl` is where the actual point of this whole commit should show up, and it's stacked with material: `invertColor()`, `grayscaleColor()`, and five kernel-convolution functions, `sharpenKernel()`, `blurKernel()`, `edgeDetectionKernel()`, `laplaceKernel()`, `embossKernel()`, each with its own 3×3 kernel matrix sampling the eight neighboring texels around a pixel. `main()` calls none of them:

```glsl
void main()
{
    // Simple post processing...
    vec4 screenColor = texture2D(colorBuffer, vs_outTexcoord); 
    //outColor = invertColor(screenColor);

    // Kernel based post processing...
    outColor = screenColor;
}
```

Even `invertColor()`, the simplest of the seven, is called and then commented out. The shader that's supposed to be the payoff of building a whole render-to-texture pipeline currently does nothing but copy the framebuffer straight through, seven working effects sitting one uncomment away.

## A Debug Callback, Ready and Unregistered

`Source.cpp` also gains a full `glDebugOutput()` callback, source, type, and severity all decoded into readable strings, and the GLFW context request bumps from OpenGL 3.3 to 4.3, likely to make that callback usable at all. Nothing in this commit calls `glEnable(GL_DEBUG_OUTPUT)` or `glDebugMessageCallback()` to actually register it. The infrastructure for better error messages arrives a step ahead of turning it on, same shape as everything else in this diff.

## The Active Shader Gets Quieter

Unlike some of the shader edits in recent posts, this one is still live: `data.shader` is still `"NormalMapTS"` in `Scene::InitScene()`, and `psNormalMapTS.glsl`'s final line changes this commit:

```glsl
outColor = Ambient;// * DiffusePoint + SpecularPoint + Reflection;
```

Diffuse, specular, and reflection all still compute, they're just excluded from what reaches the screen. The character renders as its flat, unlit albedo color this commit, no shading at all, which makes some sense given the actual subject of this post is whether a post-process pass works, not whether the lighting still looks right.

## What We Have Now

$$
\text{Scene::Render()} \;\rightarrow\; \text{FBO texture} \;\rightarrow\; \text{fullscreen quad} \;\rightarrow\; \text{psPostProcess.glsl (passthrough)} \;\rightarrow\; \text{screen}.
$$

The pipe is fully connected end to end, scene to texture to screen, and every actual effect that pipe was clearly built to carry, kernel filters, a proper `Framebuffer` abstraction, debug logging, is sitting written and disconnected around it. That's a lot of infrastructure to lay down in one commit for a shader that currently just copies its input.
