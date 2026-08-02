+++
title = "Basic Specular Lighting: A Highlight Arrives, and the Ambient Term Finally Gets Used"
date = 2019-12-14T18:03:00+05:30
tags = ["opengl", "rendering"]
description = "Adding a Phong specular highlight driven by camera position and reflection vectors, and fixing last post's unused Ambient sample along the way."
math = true
+++

# Basic Specular Lighting: A Highlight Arrives, and the Ambient Term Finally Gets Used

By the end of this post, the flat gray diffuse shading from last time gains a bright highlight that shifts as the camera moves around the mesh, the first lighting term in this series that depends on where the viewer is standing, not just where the light points. Getting there also means going back into last post's shader and actually using the texture sample that sat there computed and unread.

&nbsp;

{{< youtube 4eF8ELzBQrI >}}

&nbsp;

$$
\text{Ambient} \cdot \text{Diffuse} \;\longrightarrow\; \text{Ambient} \cdot \text{Diffuse} + \text{Specular}
$$

## The Camera Joins the Lighting Equation

`Mesh::SetShaderVariables()` picks up the camera's world position and uploads it as a new uniform:

```cpp
glm::vec3 camPosition = Camera::getInstance().getCameraPosition();
// ...
GLuint hCamPosition = glGetUniformLocation(shaderID, "cameraPosition");
glUniform3fv(hCamPosition, 1, glm::value_ptr(camPosition));
```

Diffuse lighting only needed a normal and a light direction, neither of which cares where the camera is. Specular highlights do, they're the one part of basic lighting that's genuinely view-dependent, which is why this uniform shows up for the first time exactly when specular does.

## Last Post's Ambient Sample Finally Gets Used

`psDiffuse.glsl` gets edited again this commit, even though it's not the shader in use anymore. Two lines change. First, `Ambient` actually gets multiplied by the material's albedo now:

```glsl
Ambient	= material.Albedo * texture(texture_diffuse, vs_outUV);
```

And second, it actually reaches the screen:

```glsl
outColor = Ambient * Diffuse;
```

Last post, `Ambient` was computed and then quietly dropped, `outColor` came from the grayscale `Diffuse` term alone. This diff is where that gets fixed, one post after the fact, in a shader that's already been retired in favor of the new specular one.

## The Light Direction Changes, Quietly

The same file also changes what direction the light comes from:

```glsl
uniform vec3 lightDirection = vec3(1,1,1);

float NdotL = clamp(dot(normalize(vs_outNormal), lightDirection), 0, 1);
```

`lightDirection` was `(0,0,-1)` last post, and the dot product negated it to get a direction pointing back toward the light. Here the value changes to `(1,1,1)` and the negation disappears, the dot product now treats `lightDirection` itself as the direction toward the light rather than the direction the light travels. Since none of this is in the shader `Source.cpp` actually loads this commit, `data.shader` is `"Specular"` now, not `"Diffuse"`, it's another edit to a file that isn't currently on screen, the same situation `psTextureMulti.glsl` was in last post.

## A New Shader for the Highlight

`vsSpecular.glsl` is byte-for-byte the same as last post's `vsDiffuse.glsl`. The new work is entirely in `psSpecular.glsl`, which builds on the diffuse term with a third component:

```glsl
vec3 viewDir = normalize(cameraPosition - vs_outPosition);
vec3 reflVector = normalize(reflect(lightDirection, vs_outNormal));
float RdotV = pow(clamp(dot(reflVector, viewDir), 0, 1), 64);
Specular = vec4(RdotV, RdotV, RdotV, 1);

Specular *= texture(texture_specular, vs_outUV);
```

$$
\hat{v} = \text{normalize}(\mathbf{p}_{cam} - \mathbf{p}_{world}), \qquad \hat{r} = \text{reflect}(\hat{l}, \hat{n}).
$$

The view and reflection vectors then feed a single dot product, sharpened by an exponent:

$$
S = \big(\text{clamp}(\hat{r}\cdot\hat{v},\ 0,\ 1)\big)^{64}.
$$

`reflect()` bounces the incoming light direction off the surface normal to get the direction it reflects toward. When that reflection lines up with the direction to the camera, `RdotV` is near \(1\); everywhere else it falls off fast. Raising it to the \(64\)th power is what makes that falloff sharp, a tight, small highlight instead of a broad glow, this exponent is the usual knob for how shiny a surface looks. Multiplying by `texture_specular` afterward means the highlight only shows up where the specular texture says the material should be shiny, skin and cloth stay duller than metal or leather even under the same light. The final color adds the highlight on top of the lit base:

```glsl
outColor = Ambient * Diffuse + Specular;
```

## What We Have Now

$$
\text{outColor} = \underbrace{\text{material.Albedo} \cdot \text{texture}}_{\text{Ambient}} \cdot \underbrace{N\cdot L}_{\text{Diffuse}} \;+\; \underbrace{(R\cdot V)^{64} \cdot \text{texture}_{specular}}_{\text{Specular}}.
$$

The mesh now has three lighting terms accumulating into one output color instead of one, and a camera-position uniform that only specular needed but every future lighting technique in this series will too. The next obvious step, judging by the pattern so far, is folding all of this into something less hardcoded than a single fixed light direction typed into a shader.
