+++
title = "Name It Lambert and It Becomes Lambertian"
date = 2026-08-19T00:00:00+05:30
tags = ["raytracing", "assimp", "pipeline", "cpp"]
description = "Getting materials, textures and placement out of a Maya FBX — and a glowing tiger in a Cornell box."
+++

Two posts ago I loaded a model and threw away everything except its vertex positions. No materials, no transforms — one hardcoded `Material*` for the whole mesh, sitting at the origin because that's where its coordinates happened to put it.

&nbsp;

These three commits build the missing half: a model authored in Maya arrives with its material, its texture and its placement intact.

## Materials by naming convention

Assimp reads the FBX's materials along with its geometry. The question is what to do with one — my renderer has `Lambertian`, `Metal` and `Transparent` classes, and an FBX has a material with a name and a pile of properties.

&nbsp;

What I settled on is blunt:

&nbsp;

```cpp
aiMaterial* material = scene->mMaterials[mesh->mMaterialIndex];
aiString aiName;

if (AI_SUCCESS == aiGetMaterialString(material, AI_MATKEY_NAME, &aiName))
{
	std::string name = aiName.C_Str();

	if (name.find("lambert") != std::string::npos)
	{
		...
	}
	else if (name.find("metal") != std::string::npos)
	{
		...
	}
	else if (name.find("transparent") != std::string::npos)
	{
		float r_i = m_ptrMeshInfo->matInfo.refrIndex;
		m_ptrMaterial = new Transparent(r_i);
	}
	else
	{
		MessageBox(0, L"Unknown Material", L"Error", MB_OK);
		return;
	}
}
```

&nbsp;

Substring matching on the material's name. Call it `lambert1` in Maya — which is what Maya calls it by default — and you get a `Lambertian`. Call it `metalFloor` and you get a `Metal`.

&nbsp;

It is not a robust scheme. A material named `metallic_lambert` matches the first branch and quietly becomes diffuse; renaming something in the DCC changes how it renders; and a typo lands in the `else`, which pops a message box and returns halfway through loading the mesh.

&nbsp;

But it moved the authoring where it belongs. Before this, choosing a material meant editing C++ and rebuilding. After it, the person making the model decides, in the tool they're already in, and my renderer respects it. For a one-person project that's a real change in how it feels to use.

## A block of information per mesh

The other half is `TriangleMeshInfo.h`, which introduces three plain structs — `Transform`, `MaterialInfo` and `MeshInfo` — and collapses the mesh constructor down to one argument:

&nbsp;

```cpp
-	TriangleMesh(const std::string& path, Material* ptr_mat, uint32_t _leafSize);
-	TriangleMesh(const std::string & path, uint32_t _leafSize);
+	TriangleMesh(const MeshInfo& _meshInfo);
```

&nbsp;

Two overloads that each took a subset of what a mesh needs become one that takes a description of the mesh. A scene now reads like a list of things and their properties rather than a series of constructor calls with positional arguments.

&nbsp;

`MaterialInfo` has a nice bit of override logic in it:

&nbsp;

```cpp
albedoColor = glm::vec4(0);		// logic is dependent on this being 0 i.e. if length(albedoColor) == 0 then we use Maya's color!
```

&nbsp;

```cpp
glm::vec4 albedoCol = m_ptrMeshInfo->matInfo.albedoColor;
if (glm::length(albedoCol) == 0)
{
	aiColor4D diffuseColor;
	aiGetMaterialColor(material, AI_MATKEY_COLOR_DIFFUSE, &diffuseColor);
	albedoCol = glm::vec4(diffuseColor.r, diffuseColor.g, diffuseColor.b, diffuseColor.a);
}
```

&nbsp;

So the scene can override a colour, and if it doesn't, the FBX's own value wins. Sensible defaulting, and the comment is honest about the fact that it's encoded in a magic value.

&nbsp;

Two things about that. The first is that `glm::length` is the free function — the correct one — one post after I spent a week with constant texture coordinates because `.length()` returned the component count. Apparently that lesson took.

&nbsp;

The second is that a genuinely black albedo, `vec4(0)`, is indistinguishable from "not set". Nobody makes a pure black diffuse material very often, and when they do this will silently use Maya's colour instead. It's the standard cost of using a sentinel value.

## Transforms, at last

Here's what I actually wanted:

&nbsp;

```cpp
struct Transform
{
	Transform(const glm::vec3& _pos, const glm::vec3& _axis, float _angle, const glm::vec3& _scale)
	{
		matWorld = glm::mat4(1);
		matWorld = glm::translate(matWorld, _pos);
		matWorld = glm::rotate(matWorld, _angle, _axis);
		matWorld = glm::scale(matWorld, _scale);

		matInvWorld = glm::inverse(matWorld);
		matInvTransposeWorld = glm::transpose(matInvWorld);
	}

	glm::mat4 matWorld;
	glm::mat4 matInvWorld;
	glm::mat4 matInvTransposeWorld;
};
```

&nbsp;

Worth being precise about what this does and doesn't fix. Back in post 9 I flagged that `ProcessNode` ignores `node->mTransformation`, so a model whose parts are positioned by its own hierarchy loads with everything at the origin. **That is still true.** What this adds is a transform *I* supply, per mesh, from the scene description — position, rotation axis and angle, scale. It solves the problem of placing a model in my world. It doesn't read the placement the file already contains.

&nbsp;

The transform gets applied when the triangle is built:

&nbsp;

```cpp
// Transform vertex positions using transformation matrix!
v0.position = m_pTranform->matWorld * glm::vec4(_v0.position, 1);
...
// Transform normals using Inverse Transpose of transformation matrix!
v0.normal = m_pTranform->matInvTransposeWorld * glm::vec4(_v0.normal, 0);
```

&nbsp;

Positions by the world matrix, normals by the inverse transpose. That second one is the part worth knowing:

&nbsp;

![Under a non-uniform scale, transforming a normal the same way you transformed the surface leaves it leaning](/images/blog/raytracer/normal_inverse_transpose.svg)

&nbsp;

Note also the `1` and the `0` in those `vec4` constructors. A position is a point and gets a 1, so translation applies to it. A normal is a direction and gets a 0, so translation doesn't — moving a surface across the room doesn't change which way it faces.

&nbsp;

There are two leftovers here. `matInvWorld` gets computed and stored and never used, because baking the vertices at load means nothing ever needs to go the other way. And inside `Triangle::hit` there's this:

&nbsp;

```cpp
glm::vec3 N = glm::normalize(area);
glm::vec3 transN = m_pTranform->matInvTransposeWorld * glm::vec4(N, 0);
```

&nbsp;

`transN` is computed on every intersection test and never read. It would be wrong to use it, too — the vertices are already in world space, so the normal derived from them is already correct and transforming it again would tip it. Both of those are the residue of the other way of doing this, where the geometry stays put and the rays move instead.

## Meshes that glow

`MeshInfo` carries a flag:

&nbsp;

```cpp
if (m_ptrMeshInfo->isLightSource)
{
	textureInfo = new ConstantTexture(albedoCol);
	m_ptrMaterial = new DiffuseLight(textureInfo);
}
```

&nbsp;

Any mesh can be a light. Combined with a per-scene miss colour — the background stops being the hardcoded sky gradient and becomes a property of the scene — that's everything needed for a closed room lit from inside.

&nbsp;

![The Cornell scene as it is written: red wall, green wall, a light panel on the back wall, and a tiger with `isLightSource` set to true. Materials, textures, placement and emission all came out of FBX files](/images/blog/raytracer/cornell_tiger.png)

&nbsp;

The traditional Cornell box has a plain cube where I have put a glowing tiger, and I'm not going to defend that. What it demonstrates is the whole point of these three commits: every object in that image got its material from its file, its position from a `MeshInfo`, and its emission from a boolean, and none of it required touching the renderer.

&nbsp;

The colour bleeding is real global illumination, incidentally — the red and green on the floor near the walls is light that bounced. Nothing computes that deliberately; it's what falls out of rays scattering off diffuse surfaces and being averaged.

## Where this leaves us

A model can now be authored somewhere else and arrive with its material, its texture, its transform and whether it emits light. The renderer stopped being the place where scenes are described.

&nbsp;

What it still can't do is find anything quickly. Every ray still asks every triangle.

&nbsp;

---

**Commits:** [`dd2400c` — Reading Material information from FBX](https://github.com/TheOrestes/Windows_RayTracer/commit/dd2400c) · [`a83c30b` — MeshInfo, MaterialInfo, Transform](https://github.com/TheOrestes/Windows_RayTracer/commit/a83c30b) · [`f4678f7` — Texture info fetched from the FBX](https://github.com/TheOrestes/Windows_RayTracer/commit/f4678f7)

&nbsp;

*Next up: bounding boxes, and the reflection bug they turned up.*
