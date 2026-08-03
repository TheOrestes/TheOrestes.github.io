+++
title = "Bloom Arrives: Extract, Blur, and Composite, All at Once"
date = 2020-01-25T18:03:00+05:30
tags = ["opengl", "rendering"]
description = "Wiring brightColor into a real second render target, blurring it across the brightness texture's own mip chain, and adding that glow back into the HDR composite, the bloom setup this series has been quietly carrying since the camera post."
math = true
+++

# Bloom Arrives: Extract, Blur, and Composite, All at Once

Bloom is three steps: find the pixels bright enough to glow, blur that brightness into a soft halo, and add the halo back on top of the normal image. `brightColor` has existed since this series' camera post, computing exactly step one and then having nowhere to send the result. This commit builds the other two steps and finally gives it somewhere to go.

&nbsp;

{{< youtube rV4jHnYe9nw >}}

&nbsp;

$$
\text{brightColor (computed, unused)} \;\longrightarrow\; \text{extract} \;\rightarrow\; \text{blur} \;\rightarrow\; \text{composite}
$$

## A Second Attachment for Brightness

`PostProcess::CreateColorBrightnessBuffer()` builds a framebuffer with two color attachments instead of one:

```cpp
glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, m_colorBuffer, 0);
// ...
glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT1, GL_TEXTURE_2D, m_brightBuffer, 0);

GLuint attachments[2] = { GL_COLOR_ATTACHMENT0, GL_COLOR_ATTACHMENT1 };
glDrawBuffers(2, attachments);
```

`glDrawBuffers` is what makes this a genuine multiple-render-target setup: a single draw call can now write to both textures at once, ordinary color to attachment `0`, brightness to attachment `1`. The brightness texture also gets its own mip chain, `GL_LINEAR_MIPMAP_LINEAR` filtering and an explicit `glGenerateMipmap()`, which only makes sense in light of what the blur step does with it later.

## Every Active Shader Writes Brightness Now

`psLight.glsl`, `psNormalMapTS.glsl`, and `psSkybox.glsl` all gain a second output this commit, and the threshold logic is the same formula written all the way back when `brightColor` first appeared:

```glsl
float brightness = dot(outColor.rgb, vec3(0.2126f, 0.7152f, 0.0722f));
if(brightness > 1.0f)
    brightColor = vec4(outColor.rgb, 1.0f);
else 
    brightColor = vec4(0.0f, 0.0f, 0.0f, 1.0f);
```

$$
L = 0.2126R + 0.7152G + 0.0722B, \qquad \text{brightColor} = \begin{cases}\text{color} & L > 1 \\ \mathbf{0} & \text{otherwise}\end{cases}.
$$

Everything below the threshold writes black instead of just leaving the attachment untouched, this pass produces an actual image of "only the bright parts," not a sparse one. `psSkybox.glsl` gets the same second output, but writes solid black to it unconditionally, with a comment explaining why: `// Don't consider Cubemap for brightness pass to bloom!`. However bright the sky texture itself is, it's deliberately excluded from glowing.

## Blurring Across the Mip Chain

`psBloom.glsl`'s `blurKernel()` is a five-tap weighted blur, but instead of the usual two-pass horizontal-then-vertical blur, it walks up the brightness texture's mip chain one level per tap:

```glsl
uniform float weight[5] = float[] (0.06136, 0.24477, 0.38774, 0.24477, 0.06136);

vec3 result = textureLod(brightBuffer, vs_outTexcoord, texLod).rgb * weight[0];

for(int i = 1, j = 0, k = 0; i < 8; ++i, ++j, ++k)
{
    if(i%2 == 0)
    {
        result += textureLod(brightBuffer, vs_outTexcoord - vec2(tex_offset.x * j, 0.0), texLod).rgb * weight[j];
        result += textureLod(brightBuffer, vs_outTexcoord + vec2(tex_offset.x * j, 0.0), texLod).rgb * weight[j];
    }
    else
    {
        result += textureLod(brightBuffer, vs_outTexcoord + vec2(0.0, tex_offset.y * k), texLod).rgb * weight[k];
        result += textureLod(brightBuffer, vs_outTexcoord - vec2(0.0, tex_offset.y * k), texLod).rgb * weight[k];
    }

    texLod++;
}
```

Each pass through the loop alternates between a horizontal tap and a vertical tap, and `texLod` climbs by one every iteration regardless of which axis that tap is on. Later taps aren't just further from the center, they're also sampling a coarser, already-downsampled mip level, so the blur gets progressively softer the further out it reaches, using mipmapping to approximate a wide blur radius cheaply instead of summing dozens of full-resolution samples.

## Adding the Glow Back In

`psBloom.glsl` adds that blurred brightness straight onto the ordinary scene color before tone mapping runs:

```glsl
vec4 screenColor = texture2D(colorBuffer, vs_outTexcoord); 
vec4 brightBlur = blurKernel();

screenColor += brightBlur;

// exposure tone mapping
vec3 mapped = vec3(1.0f) - exp(-screenColor.rgb * exposure);
mapped = pow(mapped, vec3(1.0f / gamma));
outColor = vec4(mapped, 1.0f);
```

The same exposure-and-gamma pipeline from last post runs on the combined result, so the added glow gets compressed down to displayable range along with everything else rather than blowing out on its own. `PostProcess`'s default `exposure` also moves from `0.25f` to `1.0f` this commit, presumably retuned now that bloom is adding its own brightness into the mix before that curve ever sees it. `Application::Run()` calls `ExecuteBloomPass()` in place of last post's `ExecutePostprocessPass()`, the reinhard-tone-mapping line stays exactly where it's been for two posts now, commented out beside the exposure version that's actually running.

## What We Have Now

$$
\text{fragment} \;\rightarrow\; \text{brightColor (extract)} \;\rightarrow\; \text{mip-chain blur} \;\rightarrow\; \text{screenColor} + \text{blur} \;\rightarrow\; \text{tone map} \;\rightarrow\; \text{screen}.
$$

`brightColor` spent a long stretch of this series computing an answer nobody asked for. This commit builds the question: a real second render target to catch it, a blur pass to spread it, and a composite step to fold it back into the picture. Three separate missing pieces, all arriving in the same diff.
