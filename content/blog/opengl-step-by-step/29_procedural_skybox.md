+++
title = "A Procedural Sky, a Kelvin Slider, and a Grid That Isn't There"
date = 2026-09-30T22:44:50+05:30
tags = ["opengl", "rendering"]
description = "The HDRI photo is replaced by a sky written from equations (gradient, dusk tint, sun disk and glow) that re-bakes itself whenever the sun moves, the sun's colour comes from a blackbody temperature, and an editor-style infinite grid is drawn with nothing but a ray and a plane."
math = true
+++

Until now the sky in this engine has been a photograph. `uffizi.hdr` went in, the capture pass turned it into a cubemap, and the irradiance and prefiltered specular maps were convolved from that. It looked great, and it never moved. Rotate the sun light and the shadows swung around while the sky stayed exactly where the photographer left it.

&nbsp;

This commit replaces the photograph with a function. The sky is now computed from the sun's direction, colour and intensity, which means the sun light is finally allowed to be the boss of the whole scene. Two other things arrive with it: the sun's colour is derived from a physical temperature instead of an RGB picker, and the scene gets an infinite editor-style ground grid that has no mesh at all.

&nbsp;

{{< youtube A4G2golH4dk >}}

&nbsp;

Most of this post is a handful of small formulas wearing shader code. For each piece I'll first say what it does in plain words, then show the formula, then the code.

&nbsp;

## A Sky Is a Function of Direction

The IBL machinery from the last few posts never cared where its environment came from. It takes a flat, rectangular picture of the sky (an equirectangular texture, the same kind of picture as a world map), wraps it into a cube, and blurs that cube. So all I have to produce is that flat picture.

&nbsp;

Think of the picture as a world map, with the sky in place of the Earth. Standing in the middle, you can point in any direction. A direction is just two turns: spin left or right (that's the longitude, which I'll call the azimuth $a$), then tilt up or down (the latitude, which I'll call the elevation $e$). Each pixel of the flat picture is one such pair of turns:

&nbsp;

$$
a = (u - \tfrac{1}{2})\cdot 2\pi, \qquad e = (v - \tfrac{1}{2})\cdot \pi
$$

&nbsp;

$$
\mathbf{d}(u,v) = \big(\cos e\,\cos a,\;\; \sin e,\;\; \cos e\,\sin a\big)
$$

&nbsp;

In words: $u$ and $v$ run from 0 to 1 across the picture. Stretch $u$ over a full turn and $v$ over a half turn, and you have the two angles. The second formula just converts "turn $a$, tilt $e$" into an arrow $(x, y, z)$ pointing that way. The height of the arrow is $\sin e$, and what's left over is shared between $x$ and $z$ by the turn. Nothing deeper than that.

&nbsp;

![One texel of the equirectangular sky corresponds to one direction on the sphere: u sweeps the azimuth a around the vertical axis, v sweeps the elevation e from nadir to zenith, and the direction vector is read off with the formula underneath.](/images/blog/skybox_equirect_mapping.svg)

&nbsp;

So for every pixel I work out which way it points, and ask "what colour is the sky that way?". That's exactly what the loop in `HDRSkybox::GenerateHDRSkyboxTexture()` does, once for each of the 512 by 256 pixels:

&nbsp;

```cpp
float v = (float)y / (float)(height - 1);
float elevation = (v - 0.5f) * glm::pi<float>();

for (int x = 0; x < width; ++x)
{
	float u = (float)x / (float)(width - 1);
	float azimuth = (u - 0.5f) * 2.0f * glm::pi<float>();

	glm::vec3 dir(cosf(elevation) * cosf(azimuth), sinf(elevation), cosf(elevation) * sinf(azimuth));
```

&nbsp;

The code comment says this matches the `asin(dir.y)` convention in `HDRI2Cubemap.frag`'s `SampleSphericalMap`, which is the reason the existing capture pass can consume this texture without being touched. The result is uploaded as `GL_RGB32F`, so values above 1.0 survive, which matters in a moment, because the sun is going to be much brighter than 1.0.

&nbsp;

## Shaping the Gradient

The base sky is a fade between three colours: a deep blue straight up (`zenithColor`), a paler blue at the horizon (`horizonColor`), and a grey-brown below it (`groundColor`). The only question is how far along the fade a pixel is, and for that I use one number, $t = \sin e$. It is simply "how high does this pixel point": $-1$ straight down, $0$ at the horizon, $+1$ straight up. (It's also the direction's $y$ component, so there's no need for any angle maths.)

&nbsp;

Above the horizon the fade amount is the square root of $t$; below it, the square root of $-t$ (flipped so it's positive):

&nbsp;

$$
\text{sky}(t) = \begin{cases}
\text{mix}\big(\text{horizon},\ \text{zenith},\ \sqrt{t}\,\big) & t \ge 0 \\[4pt]
\text{mix}\big(\text{horizon},\ \text{ground},\ \sqrt{-t}\,\big) & t < 0
\end{cases}
$$

&nbsp;

Why a square root? Because it rises fast at first and then flattens out. Only a quarter of the way up ($t = 0.25$, about 14.5 degrees above the horizon) the fade is already halfway to the deep blue ($\sqrt{0.25} = 0.5$). A straight line would crawl the whole way to the top and leave most of the sky looking like the horizon. The square root gives a short, bright haze at the horizon and a quick move into the real blue.

&nbsp;

Two more adjustments sit on top, and both depend on one thing: how high the sun is. I'll call that $y_s$ (it's `sunDir.y`: 0 when the sun is on the horizon, 1 when it's straight overhead, negative when it has set). The first one is brightness. When the sun is high, the whole sky is bright; as it drops, the whole sky dims, not only the area around the sun:

&nbsp;

$$
B(y_s) = \text{clamp}(1.5\,y_s + 0.55,\ 0,\ 1)
$$

&nbsp;

`clamp` just means "never go below 0 or above 1". So this is a ramp: the sky is at full brightness once the sun is about 17.5 degrees above the horizon, and drops steadily to completely black by about 21.5 degrees below it. There is deliberately no minimum brightness. The code comment says the point is to get a true black "floating in space" night, rather than a sky that is always faintly lit.

&nbsp;

The second adjustment is the sunset glow. It should be strongest when the sun is exactly on the horizon and fade away as it moves off in either direction. A "tent" shape does that: 1 at the horizon, falling in a straight line to 0 about 20 degrees away on either side (that's the $0.35$):

&nbsp;

$$
D(y_s) = 1 - \text{clamp}\!\left(\frac{|y_s|}{0.35},\ 0,\ 1\right)
$$

&nbsp;

That number says *when* to glow. *Where* to glow is the pixel's own height: orange is mixed in more strongly the closer the pixel is to the horizon ($1 - t$ is 1 there and 0 straight up), and never more than 70%. So at sunset the horizon turns orange and the top of the sky stays blue:

&nbsp;

```cpp
glm::vec3 baseColor = glm::mix(horizonColor, zenithColor, powf(t, 0.5f));
float horizonProximity = 1.0f - t; // 1 at the horizon, 0 at the zenith
color = glm::mix(baseColor, duskColor, duskFactor * horizonProximity * 0.7f) * skyBrightness;
```

&nbsp;

The half of the sky below the horizon gets the same `skyBrightness` multiplier, "so the ground half fades to black in lockstep", as the comment puts it.

&nbsp;

One more curve is easy to overlook: the sun itself has to switch off once it sinks below the horizon. A plain `if (sunDir.y > 0)` would make it blink out in a single frame. `smoothstep` is the usual fix: it goes from 0 to 1 along a gentle S-shaped curve, here across a narrow band just either side of the horizon (about 3 degrees each way):

&nbsp;

$$
V(y_s) = \text{smoothstep}(-0.05,\ 0.05,\ y_s)
$$

&nbsp;

![Three functions of the sun's height y_s: the brightness ramp B spans roughly 39 degrees from black to full, the dusk tent D peaks exactly on the horizon, and the sun visibility V flips on inside a window of a few degrees around it.](/images/blog/skybox_sky_response.svg)

&nbsp;

### Which Side of the Sky Is the Sun On?

This one cost me something, and it has a comment in the diff to prove it. A light's direction is the way its light *travels*, from the sun towards the ground, so the sun itself sits on the opposite side: at the negative of that direction. `DirectionalLightObject::SetEulerLightAngles` agrees, and builds the shadow camera at `-m_vecLightDirection`. My first version put the sun disk at the positive direction instead, which often landed below the horizon and made the sun look invisible and static no matter how I rotated the light. The fix is one minus sign:

&nbsp;

```cpp
sunDir = glm::normalize(-sun->m_vecLightDirection);
sunColor = sun->GetLightColor() * sun->m_fLightIntensity;
```

&nbsp;

## The Sun: Two Cosine Lobes

To draw a sun I need a number that is biggest when a pixel looks straight at the sun and shrinks as it looks away. The dot product gives me that for free. For the pixel's direction $\mathbf{d}$ and the sun's direction $\mathbf{s}$ (both arrows of length 1), $\cos\theta = \mathbf{d}\cdot\mathbf{s}$ is exactly 1 when they point the same way, and gets smaller as the angle $\theta$ between them grows.

&nbsp;

On its own that falls off far too slowly for a sun. The trick is to raise it to a power. Take a pixel 8 degrees away from the sun, where $\cos\theta \approx 0.99$. Raised to the 8th power it's still $0.92$, nearly full brightness. Raised to the 800th power it's $0.0003$, basically black. So a big exponent gives a tiny, sharp spot, and a small exponent gives a wide, soft one. The sun is one of each, added together:

&nbsp;

$$
\text{sun}(\theta) = \text{sunColor}\cdot V\cdot\Big(\cos^{800}\theta \;+\; 0.3\,\cos^{8}\theta\Big)
$$

&nbsp;

The $V$ is the horizon fade from before, and the $0.3$ keeps the glow at 30% of the disk's strength. To get a feel for how big each lobe is, I asked: how far from the sun's centre is it only half as bright? Solving $\cos^n\theta = 0.5$ for the angle gives:

&nbsp;

$$
\theta_{1/2}(800) = \arccos\!\big(0.5^{1/800}\big) \approx 2.4^\circ, \qquad \theta_{1/2}(8) = \arccos\!\big(0.5^{1/8}\big) \approx 23.5^\circ
$$

&nbsp;

So the disk is half bright just 2.4 degrees from its centre, and the glow is half bright 23.5 degrees out: a tiny hot spot inside a big soft halo. For scale, one pixel of this texture covers $360^\circ / 512 \approx 0.7^\circ$ of sky, so the disk's half-bright radius is only about three and a half pixels. That's a small disk in a small texture, and everything downstream sees it at that resolution.

&nbsp;

![Left: the disk lobe, cos(theta) to the power 800, drops to half brightness about 2.4 degrees from the sun direction. Right: the glow lobe, cos(theta) to the power 8, is half bright at about 23.5 degrees.](/images/blog/skybox_sun_lobes.svg)

&nbsp;

```cpp
float sunVisibility = glm::smoothstep(-0.05f, 0.05f, sunDir.y);
float sunAmount = glm::max(glm::dot(dir, sunDir), 0.0f);
glm::vec3 sunDisk = sunColor * powf(sunAmount, 800.0f) * sunVisibility;
glm::vec3 sunGlow = sunColor * powf(sunAmount, 8.0f) * 0.3f * sunVisibility;
color += sunDisk + sunGlow;
```

&nbsp;

The `sunVisibility` factor has a comment of its own. Without it, `sunColor` stays full brightness after the sun is below the horizon, and the texture ends up with a bright disk baked into an otherwise black sky. With the scene's sun at intensity 3.0, the disk's centre adds 3.0 (plus 0.9 of glow) on top of the sky colour, which is why the float texture is necessary. An 8-bit texture would have clipped the sun to white and the convolution would have had no idea how bright it really was.

&nbsp;

## Plugging It Into the IBL Pipeline

The load line in `Initialize()` is the only thing that changes in the existing pipeline:

&nbsp;

```cpp
// was: m_tbo = TextureManager::getInstannce().Load2DTextureFromFile("uffizi.hdr", "../Assets/HDRI");
GenerateHDRSkyboxTexture();
```

&nbsp;

Capture cubemap, irradiance convolution, prefiltered specular and BRDF LUT all run unchanged on whatever equirect texture they're handed. What's new is that they now need to be run again when the sun moves, which is the job of `RegenerateSky()`:

&nbsp;

```cpp
void HDRSkybox::RegenerateSky()
{
	glDeleteTextures(1, &m_tbo);
	GenerateHDRSkyboxTexture();

	glDeleteTextures(1, &m_captureTBO);
	InitCaptureCubemap();

	glDeleteTextures(1, &m_IrradianceTBO);
	InitIrradianceCubemap();

	glDeleteTextures(1, &m_PrefilterSpecmapTBO);
	InitPrefilteredSpecularCubemap();
}
```

&nbsp;

The BRDF LUT is skipped on purpose. It's an integral over roughness and $N\cdot V$ and has nothing to do with what the sky looks like, so it is baked once and left alone.

&nbsp;

Making this re-runnable exposed two things. First, the capture FBO and RBO used to be created inside `InitCaptureCubemap()`, so calling it again would leak a new pair every time. They now live in a one-time `CreateCaptureFBO()`. Second, and this one was a proper head-scratcher, `InitPrefilteredSpecularCubemap()` resizes the shared depth renderbuffer for each mip level and leaves it at the smallest size (the comment says 32 by 32). The next `RegenerateSky()` then tried to capture into a 512 by 512 viewport with a depth attachment that was too small. The framebuffer was incomplete, the capture silently failed, and the sky went black. The fix is to put the RBO back at full size at the end of the prefilter function:

&nbsp;

```cpp
glBindRenderbuffer(GL_RENDERBUFFER, m_captureRBO);
glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, m_iCubemapSize, m_iCubemapSize);
glBindRenderbuffer(GL_RENDERBUFFER, 0);
```

&nbsp;

In `UIManager`, the rotation, temperature and intensity sliders of light 0 (now labelled "Sky Light") all call `RegenerateSky()` when they change, because all three feed the sun term in the baked texture. That means a full regenerate and reconvolve on every slider tick. It works, and it's fine for an editor UI, but if it starts to hurt I'd re-bake only when the slider is released.

&nbsp;

## Colour From Temperature

The other change to the sun is where its colour comes from. `DirectionalLightObject` no longer stores an RGB value. It stores a temperature in Kelvin, and `GetLightColor()` turns that into a colour:

&nbsp;

```cpp
inline glm::vec3 GetLightColor() { return KelvinToRGB(m_fTemperatureKelvin); }
```

&nbsp;

Anything hot enough glows, and its colour depends only on how hot it is: a candle is orange, a welding torch is white, a clear sky is blue. `KelvinToRGB` in `Helper.h` is a well-known shortcut (Tanner Helland's fit) that turns a temperature into a colour with three simple curves, one each for red, green and blue. The graph below is all you need from it.

&nbsp;

![The three channels of KelvinToRGB across 1000 to 12000 kelvin: red stays at one until 6600 and then decays, green rises logarithmically and decays after 6600, blue is zero below about 1900 and rises to one at 6600. The strip underneath is the resulting colour.](/images/blog/skybox_kelvin_curves.svg)

&nbsp;

Read it left to right. At the cold end it is mostly red, so the light is orange-red. As the temperature climbs, green and then blue rise, and at 6600 K all three are at full strength, which is plain white. That's why the scene's sun is created with `6600.0f`. Past that, red and green slowly fade and blue wins, giving a cool bluish light.

&nbsp;

This also splits the light's two properties cleanly: temperature decides *what colour* it is, and `m_fLightIntensity` decides *how much* of it there is.

&nbsp;

### Turning Off the Direct Light

There's one more consequence of the sun's height. The IBL ambient fades with the sky, but the direct light would keep going at full intensity through the floor, and surfaces would stay lit by a sun that is underground. `PostProcess::DirectionalLightIlluminance` applies the same smoothstep to the intensity, using the same `-direction.y` convention:

&nbsp;

```cpp
float sunElevation = -direction.y;
intensity *= glm::smoothstep(-0.05f, 0.05f, sunElevation);
```

&nbsp;

Sky, sun disk and direct light all use the same 0.1-wide band around the horizon, so they fade out together instead of disagreeing about whether it's night.

&nbsp;

## An Infinite Grid With No Mesh

With the sun allowed to go below the horizon, the scene can go completely black, which is correct, and also makes it impossible to tell where anything is. The fix is the thing every 3D editor has: a ground grid that goes on forever. `InfiniteGrid` is a full-screen pass, not geometry. For every pixel, the fragment shader builds a ray and asks where it hits the $y = 0$ plane.

&nbsp;

### Ray Meets Plane

Every pixel on screen is a line of sight: a ray that starts at the camera and goes out through that pixel. The shader builds it by taking the pixel's screen position and running the camera maths backwards (the inverse of the view-projection matrix) to get a point out in the world. The ray starts at the camera position $\mathbf{o}$ and heads along the direction $\mathbf{d}$ towards that point.

&nbsp;

Where does that ray meet the ground? Say the camera is 2 units above the floor and the ray drops 0.5 units for every 1 unit it travels. It reaches the floor after $2 / 0.5 = 4$ units. That is the whole formula. With $t$ as the distance travelled, the camera height $o_y$ and how steeply the ray drops $d_y$ (negative when it points down, hence the minus sign):

&nbsp;

$$
t = -\frac{o_y}{d_y}, \qquad \mathbf{p} = \mathbf{o} + t\,\mathbf{d}
$$

&nbsp;

Walking $t$ units along the ray from the camera lands on the exact spot on the floor, $\mathbf{p}$. Two cases have no answer. If the ray is nearly flat ($d_y \approx 0$) it never really reaches the floor, and dividing by almost zero would explode. If $t \le 0$ the floor is behind the camera, such as when you look at the sky. Both skip the pixel. And since there's no real depth buffer to test against in this pass (the shader comment says the FBO's depth attachment isn't populated with scene depth), occlusion is done by hand from the G-buffer: if the scene position stored for this pixel is closer than $t$, a mesh is in the way and the grid is discarded. Sky pixels are flagged in the object ID buffer, and they write garbage positions, so they're treated as infinitely far.

&nbsp;

![Side view of two rays from the camera. The first reaches the ground plane unobstructed at t = -o.y / d.y and the grid is drawn there; the second meets a mesh before it reaches the plane, so t is larger than the scene distance and the grid pixel is discarded.](/images/blog/skybox_grid_ray_plane.svg)

&nbsp;

```glsl
vec4 clipPos = vec4(vs_outTexcoord * 2.0f - 1.0f, 1.0f, 1.0f);
vec4 farWorld4 = matInvViewProj * clipPos;
vec3 farWorld = farWorld4.xyz / farWorld4.w;
vec3 rayDir = normalize(farWorld - cameraPosition);

if (abs(rayDir.y) < 1e-4f)
	discard;

float t = -cameraPosition.y / rayDir.y;
if (t <= 0.0f)
	discard;

vec3 worldPos = cameraPosition + rayDir * t;
```

&nbsp;

```glsl
vec3 objectID = texture(objectIDBuffer, vs_outTexcoord).rgb;
float sceneDistance = 1e9f;
if (objectID.g < 0.5f)
{
	vec3 scenePos = texture(positionBuffer, vs_outTexcoord).rgb;
	sceneDistance = length(scenePos - cameraPosition);
}
if (t >= sceneDistance)
	discard;
```

&nbsp;

### Lines Without Aliasing

Now there's a point on the floor, and the question is whether it sits on a grid line. Measure the position in grid cells, $c = \mathbf{p}_{xz} / \text{cellSize}$, so the lines fall on whole numbers: 0, 1, 2, and so on. Then "how far is this point from the nearest line?" is a zig-zag that touches zero at every whole number and rises to 0.5 halfway between them:

&nbsp;

$$
d(c) = \big|\,\text{fract}(c - 0.5) - 0.5\,\big|
$$

&nbsp;

The obvious next step is to say "draw the line if $d$ is smaller than some width". That gives lines of the right width on the floor, but on screen they come out thick up close, hair-thin far away, and shimmery in between, because a distant line is thinner than a pixel. The fix is to measure in pixels, not in floor units. The GPU can tell me, through `fwidth(c)`, how much $c$ changes from one screen pixel to the next. Dividing $d$ by that converts "distance to the line" into "distance to the line in pixels". A line one pixel wide is then:

&nbsp;

$$
\text{line}(c) = 1 - \min\!\left(\frac{d(c)}{\text{fwidth}(c)},\ 1\right)
$$

&nbsp;

![Top: the triangle wave d(c) is zero on every grid line. Bottom: dividing by fwidth(c), the screen-space step per pixel, and subtracting from one turns it into a narrow tent of coverage around each line, which is used as alpha.](/images/blog/skybox_grid_aa.svg)

&nbsp;

Read it as: right on the line (0 pixels away) the value is 1, one pixel away it's 0, and in between it fades smoothly. That soft edge is what stops the line from jagging. The result is how much of the pixel the line covers, not a yes or no, which is why the pass is alpha-blended (`GL_SRC_ALPHA`, `GL_ONE_MINUS_SRC_ALPHA`) over the already-lit scene and not written as an opaque G-buffer surface. The shader computes it twice, once on $c$ for minor lines and once on $c / 10$ for major lines, and the axis lines through the origin use $|p_x|$ and $|p_z|$ divided by their own `fwidth`:

&nbsp;

```glsl
vec2 coord = worldPos.xz / cellSize;
vec2 minorDerivative = fwidth(coord);
vec2 minorGrid = abs(fract(coord - 0.5f) - 0.5f) / max(minorDerivative, vec2(1e-6f));
float minorLine = 1.0f - min(min(minorGrid.x, minorGrid.y), 1.0f);

// Every 10th line drawn thicker/brighter ("major" line)
vec2 majorCoord = coord / 10.0f;
vec2 majorDerivative = fwidth(majorCoord);
vec2 majorGrid = abs(fract(majorCoord - 0.5f) - 0.5f) / max(majorDerivative, vec2(1e-6f));
float majorLine = 1.0f - min(min(majorGrid.x, majorGrid.y), 1.0f);
```

&nbsp;

Colours are unlit constants (dim grays and a maroon pair through the origin), so the grid is visible even when everything else is black. They're scaled by 0.1 in the shader, and the pass runs before tonemapping. A final fade with distance hides the aliasing near the horizon:

&nbsp;

```glsl
coverage *= 1.0f - smoothstep(fadeDistance * 0.5f, fadeDistance, t);
```

&nbsp;

On the C++ side, `PostProcess::ExecuteInfiniteGridPass()` runs right after `ExecuteDeferredRenderPass()` while the HDR colour buffer is still bound, and the UI gets a collapsing header for enable, cell size and fade distance.

&nbsp;

## The Smaller Changes

A few things rode along in the same commit:

&nbsp;

- **WASD is polled per frame.** The old `KeyHandler` reacted to key-repeat events with a fixed `tick`, so movement stepped at the OS's auto-repeat rate while the mouse, which feeds a fresh delta every frame, stayed smooth. `Application::Run` now calls `glfwGetKey` four times per frame and passes the real `dt`.
- **VSync is on.** `glfwSwapInterval(0)` became `glfwSwapInterval(1)`. The comment says an uncapped loop pinned the GPU at 100% with no visible benefit, and was what drove the boost/throttle clock cycling behind the FPS swing.
- **The scene is trimmed.** The two mannequins and the shadow-test plane are commented out in `Scene::InitScene()`, and the third object is renamed from "Mannequin2" to "Robot", which it should always have been.
- **The project file no longer copies the `Data` and `Shaders` folders** in the post-build step. It copies the assimp, glew and glfw DLLs into the output directory instead.

&nbsp;

## What We Have Now

$$
\text{HDRI photo} \;\longrightarrow\; \text{sky}(\mathbf{d};\ \mathbf{s},\ K,\ I)
$$

&nbsp;

In one line: the sky used to be a picture, and now it's a recipe that takes the sun's direction, temperature and intensity. The sky, the IBL ambient and reflections, the sun disk, the direct light and the shadows all derive from one light: its rotation, its temperature and its intensity. Move the slider and everything agrees about what time of day it is. The downstream pipeline did not have to change at all, because a convolution doesn't care whether the equirect texture came from a camera or from a `for` loop.
