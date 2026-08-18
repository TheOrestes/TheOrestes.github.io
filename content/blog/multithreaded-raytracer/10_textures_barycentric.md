+++
title = "Three Areas and One Very Small Bug"
date = 2026-08-18T00:00:00+05:30
tags = ["raytracing", "textures", "math", "cpp"]
description = "stb_image, barycentric coordinates, and a commit that added UV interpolation without any of it working."
+++

Last post ended with me pointing at barycentric coordinates and saying they'd give me smooth normals and texture coordinates in one job. This is that job, in three commits.

&nbsp;

The middle one doesn't work, and it took me until writing this to understand why.

## A texture is a function

The first commit is small and does the important part:

&nbsp;

```cpp
class Texture
{
public:
	virtual glm::vec3 value(float u, float v) const = 0;
};

class ConstantTexture : public Texture
{
public:
	ConstantTexture(glm::vec3 col) : color(col) {}

	virtual glm::vec3 value(float u, float v) const
	{
		return color;
	}

private:
	glm::vec3 color;
};
```

&nbsp;

Which is the third time I've written this shape. `Hitable` answers *did the ray hit you*, `Material` answers *what happens next*, and now `Texture` answers *what colour are you at this point on your surface*. One pure virtual apiece.

&nbsp;

The materials stop storing a colour and start storing one of these:

&nbsp;

```cpp
-	attenuation = Albedo;
+	attenuation = Albedo->value(0,0);
```

&nbsp;

Albedo has gone from being a number to being a function of position. `ConstantTexture` makes that function return the same thing everywhere, so nothing looks different yet — the machinery goes in with the knob at zero, which is a habit by now.

&nbsp;

Note the `value(0,0)`. There's nowhere to get real coordinates from yet, so every lookup asks for the same corner.

## Something to sample

The second commit brings in `stb_image` and an `ImageTexture`:

&nbsp;

```cpp
void ImageTexture::LoadImage()
{
	data = stbi_load(path.c_str(), &width, &height, &channels, 0);
}

glm::vec3 ImageTexture::value(glm::vec2 uv) const
{
	// Images with alpha channels not supported yet!
	if (channels > 3)
		return glm::vec3(1, 0, 0.8f);

	int i = uv.x * width;
	int j = (1 - uv.y) * height;
	...
}
```

&nbsp;

Nearest-neighbour sampling, coordinates clamped to the edges, no filtering. The `1 - uv.y` is the usual flip between image space counting down from the top and texture space counting up from the bottom.

&nbsp;

The detail I'm fond of is the magenta. Rather than crash or silently misread an RGBA image, unsupported channel counts return a colour I'd never pick on purpose — so an unsupported texture announces itself on screen. That's a debugging decision, and a good one.

&nbsp;

`HitRecord` gains a `glm::vec2 uv`, and spheres learn to fill it:

&nbsp;

```cpp
glm::vec2 Sphere::GetSphereUV(const glm::vec3& p) const
{
	float phi = std::atan2(p.z, p.x);
	float theta = std::asin(p.y);

	float x = 1 - (phi + PI) / (2 * PI);
	float y = (theta + PI / 2) / PI;
	...
}
```

&nbsp;

A point on a unit sphere converted to spherical angles and remapped to $[0,1]^2$. `atan2` gives longitude, `asin` gives latitude, and the arithmetic is just scaling those into texture space. Spheres are easy — there's a closed-form answer.

## Triangles are not easy

For a triangle there's no formula from position to texture coordinate. The vertices carry UVs, loaded from the model, and a hit lands somewhere between them — so I have to work out *how much* of each vertex the hit point is made of.

&nbsp;

That's what barycentric coordinates are, and the geometric version is nice:

&nbsp;

![The point splits the triangle into three, and each vertex's weight is the area of the sub-triangle opposite it over the whole. The same weights interpolate anything the vertices carry](/images/blog/raytracer/barycentric_areas.svg)

&nbsp;

If $P$ sits right on top of $v_0$, the sub-triangle opposite $v_0$ is the entire triangle and the other two have no area — weights $(1, 0, 0)$. Slide $P$ toward the middle and the three areas even out. The weights always sum to 1, because the three pieces are the whole thing.

&nbsp;

And the areas are already nearly in hand, because the cross product of two edges has the area of the parallelogram they span as its magnitude — which is the same cross product I compute for the normal, before normalising it. So the commit does this:

&nbsp;

```cpp
// NOTE that we are not normalizing the normal vector
// as we need to take it's area.
glm::vec3 NormalWithMagnitude = glm::cross(edge0, edge1);
float area = NormalWithMagnitude.length() / 2;

// Normalize normal now!
glm::vec3 N = glm::normalize(NormalWithMagnitude);
```

&nbsp;

```cpp
rec.uv.x = (C1.length() * 0.5f) / area;
rec.uv.y = (C2.length() * 0.5f) / area;
```

&nbsp;

The reasoning is right. The code is not.

## `length()` is not length

`glm::vec3::length()` returns **3**. It's the number of components, not the magnitude — glm follows GLSL, where a vector's `.length()` is its dimension, and the magnitude is the free function `glm::length(v)`.

&nbsp;

So `area` is $3/2$, every `C.length()` is $3$, and every UV I compute is

&nbsp;

$$
\frac{3 \times 0.5}{1.5} = 1
$$

&nbsp;

Constant. Every point on every triangle asks the texture for the same corner, and the whole mesh comes out one flat colour.

&nbsp;

![The commit that added texture coordinates, running. The earth sphere is mapped correctly — spheres have their own closed-form UVs and never touch this code — while the deer is a single colour taken from one pixel of its texture](/images/blog/raytracer/uv_broken_scene.png)

&nbsp;

What makes this an easy mistake rather than a careless one is that it compiles, runs, produces a plausible image, and the mistake is a method call that exists and returns an integer. There's no warning to ignore. And the sphere in the same frame is textured perfectly, which is exactly the kind of evidence that sends you looking in the wrong place.

&nbsp;

The commit message says *"Added code for non optimized barycentric co-ordinates calculation"*. I thought I'd written something slow. I'd written something constant.

## The fix

A week later:

&nbsp;

```cpp
-	float area = NormalWithMagnitude.length() / 2;
+	glm::vec3 area = glm::cross(edge0, edge1);
+	float areaOfParellogram = glm::length(area);
```

&nbsp;

```cpp
float length0 = glm::length(C0);
float length1 = glm::length(C1);
barycentric.x = length0 / areaOfParellogram;
barycentric.y = length1 / areaOfParellogram;
barycentric.z = 1 - barycentric.x - barycentric.y;

rec.uv = barycentric.x * v2.uv + barycentric.y * v0.uv + barycentric.z * v1.uv;
```

&nbsp;

`glm::length` instead of `.length()`, and the halves cancel out — dividing one parallelogram area by another gives the same ratio as dividing the two triangles, so there's no need to halve either.

&nbsp;

For that to mean anything the triangle also had to start carrying per-vertex data, which is what `VertexPNT` is for — position, normal, texture coordinate. `Triangle` stops holding three `glm::vec3` and starts holding three vertices, and `ProcessMesh` fills them from assimp instead of throwing everything but position away.

&nbsp;

![The same crop of the same model. Left: every face a flat patch of one colour. Right: the texture actually varying across each face](/images/blog/raytracer/uv_before_after.png)

&nbsp;

Both of those are the deer. The commit that fixed this also switched the scene to a car model, so for a like-for-like comparison I pointed it back at the deer — one line, same texture, same camera path. It also keeps a Unity Asset Store model out of the pictures.

## What's still flat

The vertices now carry normals. The active code path still does this:

&nbsp;

```cpp
rec.N = N;
```

&nbsp;

The face normal. Same for every point on the triangle.

&nbsp;

There's a second implementation in the same file, a Möller–Trumbore intersection behind `#define MOLLER_TRUMBORE`, and *that* one interpolates:

&nbsp;

```cpp
rec.N = v0.normal * barycentric.x + v1.normal * barycentric.y + v2.normal * barycentric.z;
```

&nbsp;

but it's switched off. It also sets `rec.t = 100.0f` — a hardcoded distance that would break visibility completely if anyone enabled it, which is a decent sign of how far that path got tested.

&nbsp;

So the deer is textured and still faceted. I had the data and the weights and the arithmetic sitting in the same function, applied them to the UVs, and left the normals alone.

## Where this leaves us

Textures on spheres via a closed-form mapping, textures on meshes via barycentric interpolation, a magenta warning colour for anything with an alpha channel, and a week of renders where the mesh was one flat colour because a method returned the number 3.

&nbsp;

---

**Commits:** [`589f360` — Added Constant Color Texture support](https://github.com/TheOrestes/Windows_RayTracer/commit/589f360) · [`2aadee0` — Texture loading using stb_image](https://github.com/TheOrestes/Windows_RayTracer/commit/2aadee0) · [`8f14d49` — Added Barycentric coordinates for texture lookup UVs](https://github.com/TheOrestes/Windows_RayTracer/commit/8f14d49)

&nbsp;

*Next up: getting materials and transforms out of an FBX, and finding out what assimp does with a scene graph I'd been ignoring.*
