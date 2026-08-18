+++
title = "Somebody Else's Deer"
date = 2026-08-18T00:00:00+05:30
tags = ["raytracing", "assimp", "meshes", "cpp"]
description = "Loading a model off disk with assimp, flattening it into 1503 triangles, and finding out what a linear scan costs."
+++

Every triangle in the renderer so far has been one I typed in by hand. Three vertices, in a call, in a function. That's fine for one triangle and it is obviously not how anybody makes a model.

&nbsp;

So this commit brings in [assimp](https://github.com/assimp/assimp) and loads one off disk.

## A mesh is also a `Hitable`

```cpp
class TriangleMesh : public Hitable
{
public:
	TriangleMesh();
	~TriangleMesh();
	TriangleMesh(const std::string& path, Material* ptr_mat);

	virtual bool hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const;

private:
	void LoadModel(const std::string& path);
	void ProcessNode(aiNode* node, const aiScene* scene);
	void ProcessMesh(aiMesh* mesh, const aiScene* scene);

	std::vector<Triangle*> m_vecTriangles;
	Material* m_ptrMaterial;
};
```

&nbsp;

Same move as `Scene` in the last post: something that holds a pile of `Hitable`s and is itself a `Hitable`. A mesh goes into the scene's vector exactly like a sphere does, and nothing above it needs to know the difference.

## Getting the triangles out

Assimp's job is to read whatever format you throw at it and hand back a uniform structure. Loading is three lines:

&nbsp;

```cpp
Assimp::Importer importer;
const aiScene* scene = importer.ReadFile(path, aiProcess_Triangulate);

if (!scene || scene->mFlags == AI_SCENE_FLAGS_INCOMPLETE || !scene->mRootNode)
{
	MessageBox(0, L"Assimp Error!", L"Error", MB_OK);
	return;
}
```

&nbsp;

`aiProcess_Triangulate` is the only post-processing flag I asked for, and it's the one that matters most here — it guarantees every face has exactly three indices, so I never have to handle a quad. Assimp has a long list of other flags for generating normals, flipping UVs, optimising meshes. I took none of them, which is the right instinct for a first pass and something I come back to later.

&nbsp;

Then walking what it gives you:

&nbsp;

```cpp
void TriangleMesh::ProcessNode(aiNode* node, const aiScene* scene)
{
	// node only contains indices to actual objects in the scene. But scene,
	// conatins all the data, node is just to keep things organized.
	for (unsigned int i = 0; i < node->mNumMeshes; ++i)
	{
		aiMesh* mesh = scene->mMeshes[node->mMeshes[i]];
		ProcessMesh(mesh, scene);
	}

	for (unsigned int i = 0; i < node->mNumChildren; ++i)
	{
		ProcessNode(node->mChildren[i], scene);
	}
}
```

&nbsp;

I left myself a comment there and it's the thing worth understanding about assimp's model: **the node tree is organisation, not data.** A node holds indices; the meshes themselves hang off the scene. So walking the tree means recursing through nodes and reaching back into `scene->mMeshes` for anything real.

&nbsp;

![What comes in and what I keep. The recursion is over a tree; the result is a flat list](/images/blog/raytracer/assimp_flatten.svg)

&nbsp;

And then each face becomes a `Triangle`:

&nbsp;

```cpp
unsigned int index0 = face->mIndices[0];
unsigned int index1 = face->mIndices[1]; 
unsigned int index2 = face->mIndices[2];

Vector3 pos0(vecVertices.at(index0).x, vecVertices.at(index0).y, vecVertices.at(index0).z);
Vector3 pos1(vecVertices.at(index1).x, vecVertices.at(index1).y, vecVertices.at(index1).z);
Vector3 pos2(vecVertices.at(index2).x, vecVertices.at(index2).y, vecVertices.at(index2).z);

Triangle* tri = new Triangle(pos0, pos1, pos2, m_ptrMaterial);

m_vecTriangles.push_back(tri);
```

&nbsp;

Indexed vertices in, individually allocated triangles out. Every one of them gets the same `m_ptrMaterial`, so a mesh is one material all the way through — which is fine for a solid green deer and won't be fine the moment a model arrives with more than one.

## And then it just works

```cpp
TriangleMesh* pMesh0 = new TriangleMesh("models/deer.obj", new Metal(Vector3(0.0f, 0.85f, 0.25f), 0.2f));
vecHitables.push_back(pMesh0);
```

&nbsp;

One line in the scene, and:

&nbsp;

![772 vertices, 1503 triangles, loaded from an .obj and dropped into the same vector as the spheres. Nothing in the renderer was taught what a deer is. My favourite part is the orange metal sphere, which is reflecting it without being asked](/images/blog/raytracer/deer_mesh.png)

&nbsp;

That was a good afternoon. There's a real model in my renderer and I didn't have to teach the renderer anything about models — `Scene::Trace` iterates its vector, one entry happens to be a mesh, and the mesh iterates its own.

&nbsp;

The reflection in the orange sphere is the part I keep looking at. `Metal::Scatter` bounces a ray and asks the world what it hits next, and the world now contains a deer.

## What post 7 warned about

Look closely at the flank.

&nbsp;

![The same render, cropped and enlarged. Every face is a flat plane of constant shade, because every face has exactly one normal — computed from its own three vertices and shared by every point on it](/images/blog/raytracer/deer_facets.png)

&nbsp;

I said this would happen back when I wrote `Triangle`: one normal per face means a curved surface approximated by flat faces looks like flat faces. A model has vertex normals for exactly this reason, and the fix is to interpolate across the face using barycentric coordinates — which is also how you get texture coordinates, so it's one job rather than two. I'm not doing it here.

&nbsp;

It's also worth saying that this deer looks better than it should. It has 1503 triangles for an animal with antlers, and at that density the faceting reads almost as a style.

## The same loop, for the third time

Here's `TriangleMesh::hit`:

&nbsp;

```cpp
bool isIntersection = false;
float closestSoFar = tmax;

for (int i = 0; i < m_vecTriangles.size(); i++)
{
	if (m_vecTriangles[i]->hit(r, tmin, closestSoFar, rec))
	{
		isIntersection = true;
		closestSoFar = rec.t;
	}
}
```

&nbsp;

If that looks familiar it's because I've now written it three times. `HitableList::hit` in post 3, `Scene::Trace` in post 8, and this. Same running minimum, same trick of feeding `closestSoFar` back in as the next candidate's `tmax`.

&nbsp;

Writing it a third time is a signal I didn't act on. What's different this time is the scale. The first two iterate over a handful of objects; this one iterates over **1503 triangles, for every ray, at every bounce**. And it's nested inside the scene's loop, so a ray that misses the deer entirely still asks all 1503 of its triangles whether it hit them.

&nbsp;

$$
1503 \times W \times H \times S
$$

&nbsp;

triangle tests for the primary rays alone, before a single bounce. At 480×270 and 10 samples that's about two billion, and each one of them recomputes the face normal from scratch — a cross product and a square root — for vertices that have not moved since the file was loaded.

&nbsp;

The render still finishes, because sixteen cores and a small model forgive a lot. But this is the first point in the series where I can feel the algorithm rather than the plumbing, and there's an obvious shape to the fix: most of those 1503 triangles are nowhere near the ray, and I'm asking every one of them individually. That's a problem with a well-known answer and it's a few posts away.

## Things I know about

`ProcessNode` never reads `node->mTransformation`. Assimp gives every node a transform relative to its parent, and I ignore all of them — so a model whose parts are positioned by its hierarchy loads with everything piled at the origin. The deer gets away with it because it's a single mesh at identity. The first model that doesn't will make this obvious, and it's what post 11 ends up being about.

&nbsp;

`ProcessMesh` copies every vertex into a local `std::vector<aiVector3D>` and then indexes into that, when it could index `mesh->mVertices` directly. Harmless, pointless, and easy to delete.

&nbsp;

`TriangleMesh::hit` passes `rec` straight through to each triangle rather than using a temporary the way `Scene::Trace` does. It works, because a triangle only writes to the record when it actually hits and the interval test keeps out anything farther than the current best — but the two functions do the same job in visibly different ways, and I'd rather they matched.

&nbsp;

There's also a rename running through this whole commit: `dot` became `Dot`, `length()` became `Length()`, and so on across every file. Nothing behavioural, just me settling on a convention and dragging everything into line.

## Where this leaves us

The renderer can load a model. It's one material, no transforms, flat normals, and a linear search through every triangle — and it puts a deer on screen that reflects in a metal sphere.

&nbsp;

---

**Commit:** [`8b3ab6a` — Assimp Integration](https://github.com/TheOrestes/Windows_RayTracer/commit/8b3ab6a)

&nbsp;

*Next up: textures — stb_image, and the barycentric coordinates I just said I wasn't doing yet.*
