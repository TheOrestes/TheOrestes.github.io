+++
title = "HDR: Letting Light Go Above 1.0, and Bringing It Back Down With Tone Mapping"
date = 2020-01-19T18:03:00+05:30
tags = ["opengl", "rendering"]
description = "Switching the post-process framebuffer to a floating-point RGB16F texture so light can exceed 1.0 without clipping, adding exposure-based tone mapping and gamma correction, and turning the point lights up past what an ordinary image could ever hold."
math = true
+++

# HDR: Letting Light Go Above 1.0, and Bringing It Back Down With Tone Mapping

Last post built the pipe: scene into a texture, texture onto a fullscreen quad, quad onto the screen. This post is about what actually flows through that pipe. Right now, every color this series has ever produced has been squeezed into the range \([0,1]\) per channel the moment it left a shader, an 8-bit texture simply has nowhere else to put a value of `1.4`. This commit changes that, and gives the lights something worth the extra room.

## Theory: Why Games Bother With HDR

A normal 8-bit image can only represent 256 brightness levels per channel, from fully black to fully "white," and anything a shader computes above `1.0` gets clamped straight to that ceiling before it's ever stored. Real light doesn't work that way. Direct sunlight can be tens of thousands of times brighter than a shadowed corner of the same scene, a range no single 8-bit exposure can capture without either crushing the shadows to black or blowing the highlights out to flat white.

&nbsp;

![Six bracketed exposures of the same room, showing how no single exposure captures both the dark interior and the bright window](/images/blog/hdr_bracketed_exposures.jpg)

&nbsp;

*Image: "HDRI-Example.jpg" by Dean S. Pemberton, [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:HDRI-Example.jpg), licensed under [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) / GFDL.*

&nbsp;

That's exactly the problem photographers solve by shooting several exposures and merging them, dark frames keep the highlight detail, bright frames keep the shadow detail, and combining them preserves a range no single shot could hold on its own. High-dynamic-range imaging, HDR, means storing that full range numerically instead of clamping it early, in floating point rather than 8-bit integers, so a highlight that's genuinely ten times brighter than "white" stays a `10.0` instead of getting rounded down to `1.0` and losing the difference forever.

&nbsp;

The catch is that a monitor is still an 8-bit-per-channel, standard-dynamic-range device. All that preserved range eventually has to be compressed back down into something displayable, and that compression step, tone mapping, is where the interesting part happens: a good tone-mapping curve rolls off the brightest values smoothly instead of clipping them, so a blown-out window can read as "bright" without turning into a featureless white rectangle, and so multiple additive point lights, exactly the kind this series already has three of, can overlap without their combined brightness collapsing into solid white the moment they overlap.

&nbsp;

![A sunset scene showing bracketed source exposures, the merged HDR result, and a single normal exposure for comparison](/images/blog/hdr_tonemap_pipeline.jpg)

&nbsp;

*Image: "HDRToneMap.jpg" by Cody.Pope, [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:HDRToneMap.jpg), licensed under [CC BY-SA 2.5](https://creativecommons.org/licenses/by-sa/2.5/).*

&nbsp;

That capture-in-full-range, then-tone-map-down-for-display pipeline is precisely what this commit builds, just with a GPU doing the merging every frame instead of a photographer blending exposures by hand.

## A Framebuffer That Can Hold More Than White

The change that makes everything else in this post possible is one line in `PostProcess::CreateColorDepthStencilBuffer()`:

```cpp
glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB16F, horizRes, vertRes, 0, GL_RGB, GL_FLOAT, nullptr);
```

Last post this was `GL_RGB` with `GL_UNSIGNED_BYTE` data, three 8-bit channels, hard-clamped to `[0,1]`. `GL_RGB16F` stores three 16-bit floating-point channels instead, values above `1.0` simply stay above `1.0`. The scene now renders its lighting into a buffer that can actually represent how much brighter than "normal" something is, instead of losing that information the instant it's written.

## Lights Bright Enough to Need It

`Scene::InitScene()` gives the framebuffer something to actually push past `1.0`:

```cpp
m_pRedPointLight = new PointLightObject(glm::vec4(5, 0, 0, 1));
m_pGreenPointLight = new PointLightObject(glm::vec4(0, 5, 0, 1));
m_pBluePointLight = new PointLightObject(glm::vec4(0, 0, 5, 1));
```

Red, green, and blue channel values of `5.0` are meaningless in an ordinary 8-bit image, there's no such thing as "five times white." In an HDR buffer they're just numbers, five times brighter than a normal light, faithfully carried all the way to the post-process pass instead of being clipped the moment they're written.

## Exposure Tone Mapping and Gamma, Back to Back

`psPostProcess.glsl` picks up two new uniforms, `exposure` and `gamma`, and uses them right where the old pass-through used to be:

```glsl
// exposure tone mapping
vec3 mapped = vec3(1.0f) - exp(-screenColor.rgb * exposure);

// Gamma correction
mapped = pow(mapped, vec3(1.0f / gamma));

outColor = vec4(mapped, 1.0f);
```

$$
\text{mapped} = 1 - e^{-\text{HDR} \cdot \text{exposure}}, \qquad \text{final} = \text{mapped}^{1/\gamma}.
$$

The exponential curve is what does the actual dynamic-range compression: as `screenColor.rgb` grows without bound, `mapped` approaches `1.0` smoothly instead of hitting a hard wall, which is why an overbright highlight fades toward white gracefully instead of clipping. `exposure`, set to `0.25f` in `PostProcess`'s constructor, controls how aggressively that curve is applied, a lower exposure holds onto more highlight detail; a higher one brightens the whole image at the cost of it. The gamma step afterward is unrelated to HDR itself, monitors expect color encoded in roughly a `2.2` gamma curve rather than the linear values lighting math naturally produces, so this `pow()` is standard practice regardless of dynamic range.

&nbsp;

Right above the active line, commented out, is the other well-known way to do this:

```glsl
// reinhard tone mapping
//vec3 mapped = screenColor.rgb / (screenColor.rgb + vec3(1.0f));
```

Reinhard tone mapping is a different curve with the same job, both formulas take an unbounded HDR value and squeeze it toward `[0,1]`, they just roll off the highlights differently. This commit picked exposure-based mapping; Reinhard sits right there as the alternative that was tried or considered.

## Two Threads From Last Post Get Closed

`psNormalMapTS.glsl`'s output goes back to full lighting this commit:

```glsl
outColor = Ambient * DiffusePoint + SpecularPoint + Reflection;
```

Last post stripped this down to `Ambient` alone while the framebuffer plumbing was being tested. Now that there's an HDR buffer and a tone-mapping pass actually built to handle bright values, the full diffuse, specular, and reflection terms are back, and this time they have somewhere to put values greater than `1.0` without losing them.

&nbsp;

The other loose end doesn't get tied off, it gets removed. `Source.cpp`'s `glDebugOutput()` callback, written last post and never registered with `glDebugMessageCallback()`, is deleted outright this commit, function and all. Unlike the framebuffer plumbing, this thread just ends.

## Still Sitting There, Unused

`psPostProcess.glsl` still carries all seven post-processing kernels from last post, `invertColor()`, `grayscaleColor()`, and five convolution kernels. None of them run. The only change is which one is name-dropped in the trailing comment:

```glsl
// Kernel based post processing...
//outColor = embossKernel();
```

Last post it was `invertColor()` sitting commented out in that spot; this post it's `embossKernel()`. Same situation, different placeholder.

## What We Have Now

$$
\text{lighting (can exceed 1.0)} \;\rightarrow\; \text{GL\_RGB16F framebuffer} \;\rightarrow\; \text{exposure tone map} \;\rightarrow\; \text{gamma correct} \;\rightarrow\; \text{8-bit screen}.
$$

The scene can finally be genuinely, numerically brighter than white in the middle of a frame, and the post-process pass exists specifically to bring that back down to something a monitor can show without just chopping it off. Everything from here that wants convincing bright light, bloom included, needs exactly this: somewhere to store "too bright" before deciding what to do with it.
