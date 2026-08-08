+++
title = "Loading a Real Mesh: Assimp Comes Back, and the Cube Gets Benched"
date = 2019-11-20T18:03:00+05:30
tags = ["opengl", "rendering"]
description = "Wiring up Assimp through a new Mesh/Model/StaticObject pipeline to load an actual FBX file, rendering it in permanent wireframe, and finally giving the hand-typed cube a rest."
math = true
+++

By the end of this post, the scene renders geometry that didn't come from eight hand-typed `glm::vec3` corners: a real character mesh, loaded from an `.FBX` file on disk. Every mesh so far, quad, cube, skybox, has been vertices and indices someone typed directly into a `.cpp` file. That approach tops out fast. `assimp`, linked into the project two posts ago and then quietly removed again last post because the skybox didn't need it, finally earns its keep here.

&nbsp;

{{< youtube NTY7yXMwdxE >}}

&nbsp;

$$
\text{hand-typed vertices} \;\longrightarrow\; \text{Assimp-loaded mesh (Mesh / Model / StaticObject)}
$$

## A Real File Enters the Pipeline

`Source.cpp` now points at an actual asset:

```cpp
StaticObjectData data;
data.path = "../Assets/models/Mannequin/SK_Mannequin.FBX";
data.shader = "";
data.position = glm::vec3(0,0,0);
data.angle = 0.0f;
data.rotation = glm::vec3(0,1,0);
data.scale = glm::vec3(1);
StaticObject* obj1 = new StaticObject(data);
obj1->Init();
```

The cube doesn't get deleted for this. It gets benched:

```cpp
//GLCube cube(glm::vec4(1,1,0,1));
//cube.Init();
```

Every `cube.Update()` and `cube.Render()` call in the main loop is commented out the same way. `obj1` is also the first thing in this series allocated with `new` instead of living on the stack, and `main()` picks up a matching `delete obj1;` right before `glfwTerminate()`.

## Three New Classes, One Job Each

$$
\text{StaticObject (transform + shader)} \;\longrightarrow\; \text{Model (owns Mesh list)} \;\longrightarrow\; \text{Mesh (owns VAO/VBO/IBO)}
$$

`StaticObject` is the thing placed in the world: a position, rotation, scale, a shader, and a `Model`. `Model` is the thing loaded from disk: it owns however many `Mesh` objects Assimp finds inside the file. `Mesh` is the thing actually drawn: its own VAO, VBO, and IBO, built from plain `VertexP` positions and `GLuint` indices, no different in kind from `GLCube`'s buffers, just filled from a file instead of a constructor.

## Assimp Walks the Scene Graph

`Model::LoadModel()` hands the file straight to Assimp:

```cpp
Assimp::Importer importer;
const aiScene* scene = importer.ReadFile(path, aiProcess_Triangulate | aiProcess_CalcTangentSpace | aiProcess_GenSmoothNormals);
```

`aiProcess_Triangulate` guarantees every face arrives as a triangle, which is why the index extraction below can assume three indices per face without checking. From there, `ProcessNode()` walks the scene graph recursively:

```cpp
for (GLuint i = 0 ; i < node->mNumMeshes ; i++)
{
    aiMesh* mesh = scene->mMeshes[node->mMeshes[i]];
    m_Meshes.push_back(ProcessMesh(mesh, scene));
}

for (GLuint j = 0 ; j < node->mNumChildren ; j++)
{
    ProcessNode(node->mChildren[j], scene);
}
```

A node holds indices into the scene's actual mesh data, not the data itself, so `ProcessMesh()` does the real extraction, position only:

```cpp
VertexP vertex;
vertex.position = glm::vec3(mesh->mVertices[i].x, mesh->mVertices[i].y, mesh->mVertices[i].z);
vertices.push_back(vertex);
```

Worth noticing: `aiProcess_CalcTangentSpace` and `aiProcess_GenSmoothNormals` explicitly ask Assimp to compute tangents and smooth normals for this mesh. `VertexP` only has a `position` field, so both of those get computed and then discarded on the way out. The request isn't wrong, it's just aimed at a vertex format that doesn't have anywhere to put the answer yet.

## Rendering, Unconditionally in Wireframe

`Mesh::Render()` doesn't check a flag before switching polygon mode:

```cpp
glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
glEnable(GL_DEPTH_TEST);
```

Every mesh drawn through this path renders as lines, always, this commit. That's a different situation from `GLCube`'s wireframe flag a few posts back, which was reachable-in-theory but permanently off. Here it's simply on, unconditionally, for everything. `SetShaderVariables()` fills in the usual three matrices, projection and view pulled from the camera singleton, world passed in by the caller, the same pattern every object in this series has used since the camera arrived.

## The Shader Loses Its Color

`vs.glsl` and `ps.glsl`, the same shader pair `GLCube` has used since the very first post, get reused here, because `StaticObject`'s shader name is an empty string, and its path-building logic turns that into exactly `Shaders/vs.glsl` and `Shaders/ps.glsl`. But `VertexP` has no color to feed them, so the color attribute is gone:

```glsl
layout(location=0) in vec3 in_Position;

void main()
{
    mat4 WVP = matProj * matView * matWorld;
    gl_Position = WVP * vec4(in_Position, 1.0);
}
```

The fragment shader stops asking for a color and just picks one:

```glsl
void main()
{
    outColor = vec4(1,1,0,1);
}
```

The `brightColor` bloom math from two posts ago doesn't get to stay around unused this time either, it's deleted outright, along with the second output it wrote to. Whatever comes back to finish that bloom pass will have to start over.

## Breadcrumbs for a Bounding Box

A few pieces in this commit exist without anything calling them yet. `Model::GetVertexPositions()` is declared in `Model.h`, "Required for Bounding Box!" says the comment right above it, but `Model.cpp` never implements it. `StaticObjectData` grows a `showBBox` field, defaulted to `false`, that nothing currently reads. `Mesh.h` forward-declares `struct Texture;` and `struct Material;`, neither of which shows up anywhere else in this diff. And `Mesh::Kill()` is declared but, like `GetVertexPositions()`, never implemented, while `Mesh`'s actual destructor is empty, so nothing yet releases a mesh's VAO, VBO, or IBO. None of this affects what's on screen today; it's the shape of at least two future posts, bounding boxes and materials, already visible in the header files.

## What We Have Now

$$
\texttt{.FBX file} \;\rightarrow\; \text{Assimp::Importer} \;\rightarrow\; \text{ProcessNode (recursive)} \;\rightarrow\; \text{Mesh list} \;\rightarrow\; \text{StaticObject::Render()}.
$$

The cube that's anchored every post since the texturing tutorial is still in the file, just commented out rather than deleted, waiting the way `TextureManager` waited two posts ago. In its place is a real, file-loaded mesh, rendered as a permanent wireframe with a flat yellow line color, no lighting, no materials, no normals kept around to light it with even though Assimp already computed them. The geometry pipeline just grew up; everything else is still catching up to it.
