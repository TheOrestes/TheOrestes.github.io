# Post 11 — A Maya to FBX material and transform pipeline

## `dd2400c` — 2019-05-06 _(master)_

> - Reading Material information from FBX - Modified TriangleMesh to support multiple materials - Added Cornel Box scene - Modified bardarian model to have material info.

```diff
diff --git a/Application.cpp b/Application.cpp
index 73b59f1..088d5f4 100644
--- a/Application.cpp
+++ b/Application.cpp
@@ -21,7 +21,7 @@ Application::Application()
 {
 	m_iBackbufferWidth = 480;
 	m_iBackbufferHeight = 270;
-	m_iNumSamples = 50;
+	m_iNumSamples = 5;
 	m_dTotalRenderTime = 0;
 	m_dDenoiserTime = 0;
 	m_bThreaded = false;
diff --git a/RayTracer/Scene.cpp b/RayTracer/Scene.cpp
index 61a6a1c..fae97f8 100644
--- a/RayTracer/Scene.cpp
+++ b/RayTracer/Scene.cpp
@@ -55,9 +55,7 @@ void Scene::InitScene(float screenWidth, float screenHeight)
 	//Material* pMatMesh = new FlatColor (new ConstantTexture(glm::vec3(1,1,0)));
 	//TriangleMesh* pMesh0 = new TriangleMesh("models/UVCube5.fbx", pMatSphere0);
 
-	Texture* baseTexture = new ImageTexture("models/Body_Color.jpg");
-	Material* pMatMesh = new Lambertian(baseTexture);
-	TriangleMesh* pMesh0 = new TriangleMesh("models/barb1.fbx", pMatMesh, 1024);
+	TriangleMesh* pMesh0 = new TriangleMesh("models/barb1.fbx", 512);
 
 	Profiler::getInstance().WriteToProfiler("Triangle Count:", pMesh0->GetTriangleCount());
 
@@ -82,9 +80,7 @@ void Scene::InitCornellScene(float screenWidth, float screenHeight)
 	
 	Sphere* pSphereLight = new Sphere(glm::vec3(0.0f, 1.0f, 1.0f), 1.0f, new DiffuseLight(new ConstantTexture(glm::vec3(1.0f, 1.0f, 1.0f))));
 	
-
-	Material* pMatMesh = new Lambertian(new ConstantTexture(glm::vec3(0.8f, 0.8f, 0.8f)));
-	TriangleMesh* pMesh0 = new TriangleMesh("models/Cornell.fbx", pMatMesh, 10);
+	TriangleMesh* pMesh0 = new TriangleMesh("models/Cornell.fbx", 10);
 
 	Profiler::getInstance().WriteToProfiler("Triangle Count:", pMesh0->GetTriangleCount());
 
diff --git a/RayTracer/TriangleMesh.cpp b/RayTracer/TriangleMesh.cpp
index f116584..2c4ecf0 100644
--- a/RayTracer/TriangleMesh.cpp
+++ b/RayTracer/TriangleMesh.cpp
@@ -3,6 +3,11 @@
 
 #include "LameBVH.h"
 #include "TriangleMesh.h"
+#include "Material.h"
+#include "Lambertian.h"
+#include "Metal.h"
+#include "Transparent.h"
+#include "Texture.h"
 #include "AABB.h"
 #include <Windows.h>
 
@@ -16,7 +21,12 @@ TriangleMesh::TriangleMesh()
 TriangleMesh::~TriangleMesh()
 {
 	m_vecTriangles.clear();
-	m_ptrMaterial = nullptr;
+
+	if (m_ptrMaterial)
+	{
+		delete m_ptrMaterial;
+		m_ptrMaterial = nullptr;
+	}
 
 	if (m_ptrAABB)
 	{
@@ -48,6 +58,23 @@ TriangleMesh::TriangleMesh(const std::string& path, Material* ptr_mat, uint32_t
 	m_ptrBVH->BuildBVHTree(&m_vecTriangles, m_iLeafSize);
 }
 
+///////////////////////////////////////////////////////////////////////////////////////////////////
+TriangleMesh::TriangleMesh(const std::string& path, uint32_t _leafSize)
+{
+	m_vecTriangles.clear();
+	m_ptrMaterial = nullptr;
+
+	m_ptrAABB = new AABB();
+
+	LoadModel(path);
+
+	m_iTriangleCount = m_vecTriangles.size();
+
+	m_iLeafSize = _leafSize;
+	m_ptrBVH = new BVHTree();
+	m_ptrBVH->BuildBVHTree(&m_vecTriangles, m_iLeafSize);
+}
+
 ///////////////////////////////////////////////////////////////////////////////////////////////////
 void TriangleMesh::LoadModel(const std::string& path)
 {
@@ -105,6 +132,41 @@ void TriangleMesh::ProcessMesh(aiMesh* mesh, const aiScene* scene)
 		vecVertices.push_back(vertex);
 	}
 
+	// process materials
+	if (mesh->mMaterialIndex >= 0)
+	{
+		aiMaterial* material = scene->mMaterials[mesh->mMaterialIndex];
+		aiString aiName;
+		if (AI_SUCCESS == aiGetMaterialString(material, AI_MATKEY_NAME, &aiName))
+		{
+			std::string name = aiName.C_Str();
+			if (name.find("lambert") != std::string::npos)
+			{
+				// Look if material has texture info...
+				aiString path;
+				
+				if (AI_SUCCESS == aiGetMaterialTexture(material, aiTextureType_DIFFUSE, 0, &path))
+				{
+					std::string finalPath = "models/" + std::string(path.C_Str());
+					Texture* baseTexture = new ImageTexture(finalPath);
+					Material* pMatMesh = new Lambertian(baseTexture);
+					m_ptrMaterial = pMatMesh;
+					//m_vecMaterials.push_back(pMatMesh);
+				}
+				else
+				{
+					// if no texture information is present, use color...
+					aiColor4D diffuseColor;
+					aiGetMaterialColor(material, AI_MATKEY_COLOR_DIFFUSE, &diffuseColor);
+					Texture* baseColor = new ConstantTexture(glm::vec3(diffuseColor.r, diffuseColor.g, diffuseColor.b));
+					Material* pMatMesh = new Lambertian(baseColor);
+					m_ptrMaterial = pMatMesh;
+					//m_vecMaterials.push_back(pMatMesh);
+				}
+			}
+		}
+	}
+
 	for (unsigned int i = 0; i < mesh->mNumFaces; i++)
 	{
 		aiFace face = mesh->mFaces[i];
@@ -142,7 +204,7 @@ bool TriangleMesh::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) con
 
 	if (m_ptrBVH->hit(r, tmin, tmax, rec))
 	{
-		rec.mat_ptr = m_ptrMaterial;
+		//rec.mat_ptr = m_ptrMaterial;
 		//closestSoFar = rec.t;
 		isIntersection = true;
 	}
diff --git a/RayTracer/TriangleMesh.h b/RayTracer/TriangleMesh.h
index 4e87b9b..52e3a44 100644
--- a/RayTracer/TriangleMesh.h
+++ b/RayTracer/TriangleMesh.h
@@ -18,6 +18,7 @@ public:
 	TriangleMesh();
 	~TriangleMesh();
 	TriangleMesh(const std::string& path, Material* ptr_mat, uint32_t _leafSize);
+	TriangleMesh(const std::string & path, uint32_t _leafSize);
 
 	virtual bool hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const;
 	virtual void BoundingBox(AABB& box) const;
@@ -31,6 +32,7 @@ private:
 	void ProcessMesh(aiMesh* mesh, const aiScene* scene);
 
 	std::vector<Triangle*> m_vecTriangles;
+
 	AABB*				   m_ptrAABB;
 	Material*			   m_ptrMaterial;
 
```

## `a83c30b` — 2019-05-12 _(master)_

> - Added MeshInfo, MaterialInfo, Transform block - Material info now read from Maya fbx or explicitly set values - Triangle meshes now respect world space transforms - Added MissColor property (scene specific) - Added Cornell box scene.

```diff
diff --git a/Application.cpp b/Application.cpp
index 088d5f4..30ba87d 100644
--- a/Application.cpp
+++ b/Application.cpp
@@ -21,7 +21,7 @@ Application::Application()
 {
 	m_iBackbufferWidth = 480;
 	m_iBackbufferHeight = 270;
-	m_iNumSamples = 5;
+	m_iNumSamples = 100;
 	m_dTotalRenderTime = 0;
 	m_dDenoiserTime = 0;
 	m_bThreaded = false;
@@ -55,6 +55,7 @@ void Application::Initialize(HWND hwnd, bool _threaded)
 	_threaded ? m_iMaxThreads = std::thread::hardware_concurrency() : 0;
 
 	m_pScene = new Scene();
+	//m_pScene->InitScene(m_iBackbufferWidth, m_iBackbufferHeight);
 	m_pScene->InitCornellScene(m_iBackbufferWidth, m_iBackbufferHeight);
 
 	// Create Open Image Denoise Device
@@ -224,7 +225,7 @@ glm::vec3 Application::TraceColor(const Ray & r, int depth, int& rayCount)
 		//glm::vec3 unit_direction = glm::normalize(r.GetRayDirection());
 		//float t = 0.5f * (unit_direction[1] + 1.0f);
 		//traceColor = Helper::LerpVector(glm::vec3(1.0f, 1.0f, 1.0f), glm::vec3(0.5f, 0.7f, 1.0f), t);
-		return glm::vec3(0.01f);
+		return m_pScene->getMissColor();
 	}
 
 	// debug info...
diff --git a/RayTracer/Scene.cpp b/RayTracer/Scene.cpp
index fae97f8..887752d 100644
--- a/RayTracer/Scene.cpp
+++ b/RayTracer/Scene.cpp
@@ -16,6 +16,7 @@
 ///////////////////////////////////////////////////////////////////////////////////////////////////
 Scene::Scene()
 {
+	m_colMiss = glm::vec4(0.5f);
 	vecHitables.clear();
 	m_pCamera = nullptr;
 }
@@ -46,25 +47,33 @@ void Scene::InitScene(float screenWidth, float screenHeight)
 	Material* pMatSphereGround = new Lambertian(new ConstantTexture(albedo1));
 	Sphere* pSphereGround = new Sphere(center1, 100.0f, pMatSphereGround);
 
-	Sphere* pSphereGlass1 = new Sphere(glm::vec3(-4.0f, 0.4f, 0.0f), 1.0f, new Transparent(1.3f));
-	Sphere* pSphereMetal = new Sphere(glm::vec3(0.0f, 0.7f, -3.5f), 1.4f, new Metal(new ConstantTexture(glm::vec3(1.0f, 0.1f, 0.0f)), 0.1f));
-	Sphere* pSphereLight = new Sphere(glm::vec3(-1.5f, 0.5f, 1.25f), 1.0f, new DiffuseLight(new ConstantTexture(glm::vec3(1.0f, 1.0f, 1.0f))));
-	Sphere* pSphereEarth = new Sphere(glm::vec3(2.5f, 0.0f, 0.0f), 0.5, new Lambertian(new ImageTexture("models/earth.jpg")));
-
-	//Triangle* pTriangle0  = new Triangle(glm::vec3(-2.0f, 0.0f, -1.0f), glm::vec3(2.0f, 0.0f, -1.0f), glm::vec3(0.0f, 2.0f, -1.0f), new Metal(new ConstantTexture(glm::vec3(0.0, 1.0f, 0.0f)), 0.5f));
-	//Material* pMatMesh = new FlatColor (new ConstantTexture(glm::vec3(1,1,0)));
-	//TriangleMesh* pMesh0 = new TriangleMesh("models/UVCube5.fbx", pMatSphere0);
+	//Sphere* pSphereGlass1 = new Sphere(glm::vec3(-4.0f, 0.4f, 0.0f), 1.0f, new Transparent(1.3f));
+	//Sphere* pSphereMetal = new Sphere(glm::vec3(0.0f, 0.7f, -3.5f), 1.4f, new Metal(new ConstantTexture(glm::vec3(1.0f, 0.1f, 0.0f)), 0.1f));
+	//Sphere* pSphereLight = new Sphere(glm::vec3(-1.5f, 0.5f, 1.25f), 1.0f, new DiffuseLight(new ConstantTexture(glm::vec3(1.0f, 1.0f, 1.0f))));
+	//Sphere* pSphereEarth = new Sphere(glm::vec3(2.5f, 0.0f, 0.0f), 0.5, new Lambertian(new ImageTexture("models/earth.jpg")));
+	
+	//MeshInfo barbInfo;
+	//barbInfo.filePath = "models/barb1.fbx";
+	//barbInfo.isLightSource = false;
+	//barbInfo.leafSize = 512;
+	//TriangleMesh* pMesh0 = new TriangleMesh(barbInfo);
 
-	TriangleMesh* pMesh0 = new TriangleMesh("models/barb1.fbx", 512);
+	MeshInfo cubePhongInfo;
+	cubePhongInfo.filePath = "models/CubePhong.fbx";
+	cubePhongInfo.matInfo.albedoColor = glm::vec4(0, 1, 0, 1);
+	cubePhongInfo.isLightSource = false;
+	cubePhongInfo.leafSize = 12;
+	TriangleMesh* pCubePhong = new TriangleMesh(cubePhongInfo);
 
-	Profiler::getInstance().WriteToProfiler("Triangle Count:", pMesh0->GetTriangleCount());
+	//Profiler::getInstance().WriteToProfiler("Triangle Count:", pMesh0->GetTriangleCount());
 
 	vecHitables.push_back(pSphereGround);
-	vecHitables.push_back(pSphereGlass1);
-	vecHitables.push_back(pSphereMetal);
-	vecHitables.push_back(pSphereEarth);
-	vecHitables.push_back(pSphereLight);
-	vecHitables.push_back(pMesh0);
+	//vecHitables.push_back(pSphereGlass1);
+	//vecHitables.push_back(pSphereMetal);
+	//vecHitables.push_back(pSphereEarth);
+	//vecHitables.push_back(pSphereLight);
+	//vecHitables.push_back(pMesh0);
+	vecHitables.push_back(pCubePhong);
 }
 
 ///////////////////////////////////////////////////////////////////////////////////////////////////
@@ -76,16 +85,58 @@ void Scene::InitCornellScene(float screenWidth, float screenHeight)
 	m_pCamera = new Camera();
 	m_pCamera->InitCamera(cameraPosition, cameraLookAt, screenWidth, screenHeight);
 
-	// Sphere Ground
+	// Override miss color to black
+	m_colMiss = glm::vec4(0.0f);
 	
 	Sphere* pSphereLight = new Sphere(glm::vec3(0.0f, 1.0f, 1.0f), 1.0f, new DiffuseLight(new ConstantTexture(glm::vec3(1.0f, 1.0f, 1.0f))));
-	
-	TriangleMesh* pMesh0 = new TriangleMesh("models/Cornell.fbx", 10);
-
-	Profiler::getInstance().WriteToProfiler("Triangle Count:", pMesh0->GetTriangleCount());
 
-	vecHitables.push_back(pSphereLight);
-	vecHitables.push_back(pMesh0);
+	// Room Mesh
+	MeshInfo roomInfo;
+	roomInfo.filePath = "models/Cornell.fbx";
+	roomInfo.isLightSource = false;
+	roomInfo.leafSize = 10;
+	TriangleMesh* pRoom = new TriangleMesh(roomInfo);
+
+	// Cube 1
+	MeshInfo cubeLeftInfo;
+	cubeLeftInfo.filePath = "models/CubePhong.fbx";
+	cubeLeftInfo.isLightSource = false;
+	cubeLeftInfo.leafSize = 12;
+	cubeLeftInfo.position = glm::vec3(1.0f, 1.8f, -1.35f);
+	cubeLeftInfo.rotationAxis = glm::vec3(0, 1, 0);
+	cubeLeftInfo.rotationAngle = 9.0f;
+	cubeLeftInfo.scale = glm::vec3(1.6f, 3.6f, 1.6f);
+	cubeLeftInfo.matInfo.albedoColor = glm::vec4(1, 1, 1, 1);
+	cubeLeftInfo.matInfo.roughness = 0.2f;
+	TriangleMesh* pLeftCube = new TriangleMesh(cubeLeftInfo);
+
+	// Cube 2
+	MeshInfo cubeRightInfo;
+	cubeRightInfo.filePath = "models/Cube.fbx";
+	cubeRightInfo.isLightSource = false;
+	cubeRightInfo.leafSize = 10;
+	cubeRightInfo.position = glm::vec3(-0.9f, 0.9f, 1.0f);
+	cubeRightInfo.rotationAxis = glm::vec3(0, 1, 0);
+	cubeRightInfo.rotationAngle = -6.0f;
+	cubeRightInfo.scale = glm::vec3(1.8f);
+	cubeRightInfo.matInfo.albedoColor = glm::vec4(0, 0, 1, 1);
+	TriangleMesh* pRightCube = new TriangleMesh(cubeRightInfo);
+
+	// Light Quad
+	MeshInfo lightInfo;
+	lightInfo.filePath = "models/Quad.fbx";
+	lightInfo.isLightSource = true;
+	lightInfo.leafSize = 2;
+	lightInfo.position = glm::vec3(0, 4.99f, 0.5f);
+	lightInfo.scale = glm::vec3(2);
+	TriangleMesh* pLight = new TriangleMesh(lightInfo);
+
+	vecHitables.push_back(pLight);
+	vecHitables.push_back(pRoom);
+	vecHitables.push_back(pLeftCube);
+	vecHitables.push_back(pRightCube);
+
+	Profiler::getInstance().WriteToProfiler("Triangle Count:", pRoom->GetTriangleCount() + pLight->GetTriangleCount() + pLeftCube->GetTriangleCount() + pRightCube->GetTriangleCount());
 }
 
 ///////////////////////////////////////////////////////////////////////////////////////////////////
diff --git a/RayTracer/Scene.h b/RayTracer/Scene.h
index 8de198d..542e6e2 100644
--- a/RayTracer/Scene.h
+++ b/RayTracer/Scene.h
@@ -18,8 +18,11 @@ public:
 	void InitRandomScene(float screenWidth, float screenHeight);
 
 	inline Camera* getCamera() { if(m_pCamera) return m_pCamera; }
+	inline glm::vec4 getMissColor() { return m_colMiss; }
 
 private:	
+	glm::vec4			  m_colMiss;
 	Camera*				  m_pCamera;
 	std::vector<Hitable*> vecHitables;
+
 };
\ No newline at end of file
diff --git a/RayTracer/Triangle.cpp b/RayTracer/Triangle.cpp
index b4cdaad..083c5f6 100644
--- a/RayTracer/Triangle.cpp
+++ b/RayTracer/Triangle.cpp
@@ -4,21 +4,40 @@
 
 //#define MOLLER_TRUMBORE
 
-Triangle::Triangle(const VertexPNT & _v0, const VertexPNT & _v1, const VertexPNT & _v2, Material * ptr_mat)
+///////////////////////////////////////////////////////////////////////////////////////////////////
+Triangle::Triangle()
+{
+	m_pTranform = new Transform();
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+Triangle::Triangle(const VertexPNT & _v0, const VertexPNT & _v1, const VertexPNT & _v2, Transform* _pTransform, Material * ptr_mat)
 {
-	v0 = _v0; v1 = _v1; v2 = _v2;
+	m_pTranform = _pTransform;
+
+	// Transform vertex positions using transformation matrix!
+	v0.position = m_pTranform->matWorld * glm::vec4(_v0.position, 1);
+	v1.position = m_pTranform->matWorld * glm::vec4(_v1.position, 1);
+	v2.position = m_pTranform->matWorld * glm::vec4(_v2.position, 1);
+
+	// Transform normals using Inverse Transpose of transformation matrix!
+	v0.normal = m_pTranform->matInvTransposeWorld * glm::vec4(_v0.normal, 0);
+	v1.normal = m_pTranform->matInvTransposeWorld * glm::vec4(_v1.normal, 0);
+	v2.normal = m_pTranform->matInvTransposeWorld * glm::vec4(_v2.normal, 0);
+
+	// Keep UVs as is...!
+	v0.uv = _v0.uv;
+	v1.uv = _v1.uv;
+	v2.uv = _v2.uv;
+
 	mat_ptr = ptr_mat;
 
 	// calculate centroid...
 	centroid = v0.position + v1.position + v2.position;
 	centroid /= 3.0f;
-	//float x = (v0.position[0] + v1.position[0] + v2.position[0]) / 3.0f;
-	//float y = (v0.position[1] + v1.position[1] + v2.position[1]) / 3.0f;
-	//float z = (v0.position[2] + v1.position[2] + v2.position[2]) / 3.0f;
-	//centroid = glm::vec3(x, y, z);
 }
 
-/////////////////////////////////////////////////////////////////////////////////////////
+///////////////////////////////////////////////////////////////////////////////////////////////////
 bool Triangle::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
 {
 	++rec.rayTriangleQuery;
@@ -76,6 +95,8 @@ bool Triangle::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
 	// cross product's vector direction represents new vector perpendicular to 
 	// plane formed by those two vectors!
 	glm::vec3 N = glm::normalize(area);
+	glm::vec3 transN = m_pTranform->matInvTransposeWorld * glm::vec4(N, 0);
+
 	// Check if ray & plane are parallel
 	float NDotRayDirection = glm::dot(N, rayDirection); 
 	if (fabs(NDotRayDirection) < 0.001f)
@@ -125,37 +146,7 @@ bool Triangle::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
 	else
 		return false;
 #endif
-	
 
-	//auto edge0 = V1 - V0;
-	//auto edge1 = V2 - V1;
-	//auto normal = UnitVector(Cross(edge0, edge1));
-	//auto planeOffset = glm::dot(V0, normal);
-	//auto p0 = r.GetPointAt(tmin);
-	//auto p1 = r.GetPointAt(tmax);
-	//auto offset0 = glm::dot(p0, normal);
-	//auto offset1 = glm::dot(p1, normal);
-	//if ((offset0 - planeOffset)*(offset1 - planeOffset) <= 0.f) // Line segment intersects the plane of the triangle
-	//{
-	//	float t = tmin + (tmax - tmin)*(planeOffset - offset0) / (offset1 - offset0);
-	//	auto p = r.GetPointAt(t);
-	//	auto c0 = Cross(edge0, p - V0);
-	//	auto c1 = Cross(edge1, p - V1);
-	//	if (glm::dot(c0, c1) >= 0.f)
-	//	{
-	//		auto edge2 = V0 - V2;
-	//		auto c2 = Cross(edge2, p - V2);
-	//		if (glm::dot(c1, c2) >= 0.f)
-	//		{
-	//			rec.t = t;
-	//			rec.P = p;
-	//			rec.N = normal;
-	//			rec.mat_ptr = mat_ptr;
-	//			return true;
-	//		}
-	//	}
-	//}
-	//return false;
 }
 
 ///////////////////////////////////////////////////////////////////////////////////////////////////
diff --git a/RayTracer/Triangle.h b/RayTracer/Triangle.h
index 760e300..d29450a 100644
--- a/RayTracer/Triangle.h
+++ b/RayTracer/Triangle.h
@@ -2,6 +2,7 @@
 
 #include "glm/glm.hpp"
 #include "Hitable.h"
+#include "TriangleMeshInfo.h"
 #include "VertexStructures.h"
 
 class Material;
@@ -9,8 +10,8 @@ class Material;
 class Triangle : public Hitable
 {
 public:
-	Triangle() {}
-	Triangle(const VertexPNT& _v0, const VertexPNT& _v1, const VertexPNT& _v2, Material* ptr_mat);
+	Triangle();
+	Triangle(const VertexPNT& _v0, const VertexPNT& _v1, const VertexPNT& _v2, Transform* _pTransform, Material* ptr_mat);
 
 	virtual bool hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const;
 	virtual void BoundingBox(AABB& box) const;
@@ -24,4 +25,6 @@ private:
 	//glm::vec3 centroid;
 	glm::vec3 centroid;
 	Material* mat_ptr;
+
+	Transform* m_pTranform;
 };
diff --git a/RayTracer/TriangleMesh.cpp b/RayTracer/TriangleMesh.cpp
index 2c4ecf0..5d7e106 100644
--- a/RayTracer/TriangleMesh.cpp
+++ b/RayTracer/TriangleMesh.cpp
@@ -5,6 +5,7 @@
 #include "TriangleMesh.h"
 #include "Material.h"
 #include "Lambertian.h"
+#include "DiffuseLight.h"
 #include "Metal.h"
 #include "Transparent.h"
 #include "Texture.h"
@@ -28,6 +29,12 @@ TriangleMesh::~TriangleMesh()
 		m_ptrMaterial = nullptr;
 	}
 
+	if (m_ptrTransform)
+	{
+		delete m_ptrTransform;
+		m_ptrTransform = nullptr;
+	}
+
 	if (m_ptrAABB)
 	{
 		delete m_ptrAABB;
@@ -41,38 +48,23 @@ TriangleMesh::~TriangleMesh()
 	}
 }
 
-///////////////////////////////////////////////////////////////////////////////////////////////////
-TriangleMesh::TriangleMesh(const std::string& path, Material* ptr_mat, uint32_t _leafSize)
-{
-	m_vecTriangles.clear();
-	m_ptrMaterial = ptr_mat;
-
-	m_ptrAABB = new AABB();
-
-	LoadModel(path);
-
-	m_iTriangleCount = m_vecTriangles.size();
-
-	m_iLeafSize = _leafSize;
-	m_ptrBVH = new BVHTree();
-	m_ptrBVH->BuildBVHTree(&m_vecTriangles, m_iLeafSize);
-}
-
-///////////////////////////////////////////////////////////////////////////////////////////////////
-TriangleMesh::TriangleMesh(const std::string& path, uint32_t _leafSize)
+/////////////////////////////////////////////////////////////////////////////////////////////////////
+TriangleMesh::TriangleMesh(const MeshInfo& _meshInfo)
 {
 	m_vecTriangles.clear();
 	m_ptrMaterial = nullptr;
 
+	m_ptrMeshInfo = const_cast<MeshInfo*>(&_meshInfo);
+
+	m_ptrTransform = new Transform(_meshInfo.position, _meshInfo.rotationAxis, _meshInfo.rotationAngle, _meshInfo.scale);
 	m_ptrAABB = new AABB();
 
-	LoadModel(path);
+	LoadModel(_meshInfo.filePath);
 
 	m_iTriangleCount = m_vecTriangles.size();
 
-	m_iLeafSize = _leafSize;
 	m_ptrBVH = new BVHTree();
-	m_ptrBVH->BuildBVHTree(&m_vecTriangles, m_iLeafSize);
+	m_ptrBVH->BuildBVHTree(&m_vecTriangles, _meshInfo.leafSize);
 }
 
 ///////////////////////////////////////////////////////////////////////////////////////////////////
@@ -137,33 +129,81 @@ void TriangleMesh::ProcessMesh(aiMesh* mesh, const aiScene* scene)
 	{
 		aiMaterial* material = scene->mMaterials[mesh->mMaterialIndex];
 		aiString aiName;
+
 		if (AI_SUCCESS == aiGetMaterialString(material, AI_MATKEY_NAME, &aiName))
 		{
 			std::string name = aiName.C_Str();
+
 			if (name.find("lambert") != std::string::npos)
 			{
-				// Look if material has texture info...
-				aiString path;
-				
-				if (AI_SUCCESS == aiGetMaterialTexture(material, aiTextureType_DIFFUSE, 0, &path))
+				// Extract texture info if filepath or flat color?
+				Texture* textureInfo = nullptr;
+				if (!m_ptrMeshInfo->matInfo.albedoFilePath.empty())
+				{
+					textureInfo = new ImageTexture("models/" + m_ptrMeshInfo->matInfo.albedoFilePath);
+					m_ptrMaterial = new Lambertian(textureInfo);
+				}
+				else
+				{
+					// Check if we have set albedo color explicitly or not, if not then use Maya's 
+					// set color from the properties!
+					glm::vec4 albedoCol = m_ptrMeshInfo->matInfo.albedoColor;
+					if (glm::length(albedoCol) == 0)
+					{
+						aiColor4D diffuseColor;
+						aiGetMaterialColor(material, AI_MATKEY_COLOR_DIFFUSE, &diffuseColor);
+						albedoCol = glm::vec4(diffuseColor.r, diffuseColor.g, diffuseColor.b, diffuseColor.a);
+					}
+
+					if (m_ptrMeshInfo->isLightSource)
+					{
+						textureInfo = new ConstantTexture(albedoCol);
+						m_ptrMaterial = new DiffuseLight(textureInfo);
+					}
+					else
+					{
+						textureInfo = new ConstantTexture(albedoCol);
+						m_ptrMaterial = new Lambertian(textureInfo);
+					}
+				}
+			}
+			else if (name.find("metal") != std::string::npos)
+			{
+				// Extract texture info if filepath or flat color?
+				Texture* textureInfo = nullptr;
+				float roughness = m_ptrMeshInfo->matInfo.roughness;
+
+				if (!m_ptrMeshInfo->matInfo.albedoFilePath.empty())
 				{
-					std::string finalPath = "models/" + std::string(path.C_Str());
-					Texture* baseTexture = new ImageTexture(finalPath);
-					Material* pMatMesh = new Lambertian(baseTexture);
-					m_ptrMaterial = pMatMesh;
-					//m_vecMaterials.push_back(pMatMesh);
+					textureInfo = new ImageTexture("models/" + m_ptrMeshInfo->matInfo.albedoFilePath);
+					m_ptrMaterial = new Metal(textureInfo, roughness);
 				}
 				else
 				{
-					// if no texture information is present, use color...
-					aiColor4D diffuseColor;
-					aiGetMaterialColor(material, AI_MATKEY_COLOR_DIFFUSE, &diffuseColor);
-					Texture* baseColor = new ConstantTexture(glm::vec3(diffuseColor.r, diffuseColor.g, diffuseColor.b));
-					Material* pMatMesh = new Lambertian(baseColor);
-					m_ptrMaterial = pMatMesh;
-					//m_vecMaterials.push_back(pMatMesh);
+					// Check if we have set albedo color explicitly or not, if not then use Maya's 
+					// set color from the properties!
+					glm::vec4 albedoCol = m_ptrMeshInfo->matInfo.albedoColor;
+					if (glm::length(albedoCol) == 0)
+					{
+						aiColor4D diffuseColor;
+						aiGetMaterialColor(material, AI_MATKEY_COLOR_DIFFUSE, &diffuseColor);
+						albedoCol = glm::vec4(diffuseColor.r, diffuseColor.g, diffuseColor.b, diffuseColor.a);
+					}
+
+					textureInfo = new ConstantTexture(albedoCol);
+					m_ptrMaterial = new Metal(textureInfo, roughness);
 				}
 			}
+			else if (name.find("transparent") != std::string::npos)
+			{
+				float r_i = m_ptrMeshInfo->matInfo.refrIndex;
+				m_ptrMaterial = new Transparent(r_i);
+			}
+			else
+			{
+				MessageBox(0, L"Unknown Material", L"Error", MB_OK);
+				return;
+			}
 		}
 	}
 
@@ -180,7 +220,7 @@ void TriangleMesh::ProcessMesh(aiMesh* mesh, const aiScene* scene)
 		VertexPNT vert1 = vecVertices.at(index1);
 		VertexPNT vert2 = vecVertices.at(index2);
 
-		Triangle* tri = new Triangle(vert0, vert1, vert2, m_ptrMaterial);
+		Triangle* tri = new Triangle(vert0, vert1, vert2, m_ptrTransform, m_ptrMaterial);
 
 		m_vecTriangles.push_back(tri);
 	}
@@ -215,6 +255,7 @@ bool TriangleMesh::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) con
 	//	{
 	//		if (m_vecTriangles[i]->hit(r, tmin, closestSoFar, rec))
 	//		{
+	//			rec.mat_ptr = m_ptrMaterial;
 	//			isIntersection = true;
 	//			closestSoFar = rec.t;
 	//		}
@@ -224,8 +265,9 @@ bool TriangleMesh::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) con
 	return isIntersection;
 }
 
-///////////////////////////////////////////////////////////////////////////////////////////////////
+////////////////////////////////////////////////////////////////////////////////////////////////////////////////
 void TriangleMesh::BoundingBox(AABB & box) const
 {
 	box = *m_ptrAABB;
 }
+
diff --git a/RayTracer/TriangleMesh.h b/RayTracer/TriangleMesh.h
index 52e3a44..27f2515 100644
--- a/RayTracer/TriangleMesh.h
+++ b/RayTracer/TriangleMesh.h
@@ -5,7 +5,7 @@
 #include "assimp\Importer.hpp"
 #include "assimp\postprocess.h"
 #include "assimp\scene.h"
-
+#include "TriangleMeshInfo.h"
 #include "Triangle.h"
 
 class Material;
@@ -17,8 +17,7 @@ class TriangleMesh : public Hitable
 public:
 	TriangleMesh();
 	~TriangleMesh();
-	TriangleMesh(const std::string& path, Material* ptr_mat, uint32_t _leafSize);
-	TriangleMesh(const std::string & path, uint32_t _leafSize);
+	TriangleMesh(const MeshInfo& _meshInfo);
 
 	virtual bool hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const;
 	virtual void BoundingBox(AABB& box) const;
@@ -33,11 +32,12 @@ private:
 
 	std::vector<Triangle*> m_vecTriangles;
 
-	AABB*				   m_ptrAABB;
-	Material*			   m_ptrMaterial;
+	AABB*					m_ptrAABB;
+	Material*				m_ptrMaterial;
+	Transform*				m_ptrTransform;
+	MeshInfo*				m_ptrMeshInfo;
 
-	BVHTree*			   m_ptrBVH;
+	BVHTree*				m_ptrBVH;
 
-	uint32_t			   m_iLeafSize;
-	uint64_t			   m_iTriangleCount;
+	uint64_t				m_iTriangleCount;
 };
diff --git a/RayTracer/TriangleMeshInfo.h b/RayTracer/TriangleMeshInfo.h
new file mode 100644
index 0000000..f465d73
--- /dev/null
+++ b/RayTracer/TriangleMeshInfo.h
@@ -0,0 +1,87 @@
+#pragma once
+
+#include "glm/glm.hpp"
+#include "glm/gtc/matrix_transform.hpp"
+
+#include <string>
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+struct Transform
+{
+	Transform()
+	{
+		matWorld = glm::mat4(1);
+		matInvWorld = glm::mat4(1);
+		matInvTransposeWorld = glm::mat4(1);
+	}
+
+	Transform(const glm::vec3& _pos, const glm::vec3& _axis, float _angle, const glm::vec3& _scale)
+	{
+		// Identity matrices...
+		matWorld = glm::mat4(1);
+		matInvWorld = glm::mat4(1);
+		matInvTransposeWorld = glm::mat4(1);
+
+		// World matrix
+		matWorld = glm::translate(matWorld, _pos);
+		matWorld = glm::rotate(matWorld, _angle, _axis);
+		matWorld = glm::scale(matWorld, _scale);
+
+		// World inverse & world inverse transpose
+		matInvWorld = glm::inverse(matWorld);
+		matInvTransposeWorld = glm::transpose(matInvWorld);
+	}
+
+	glm::mat4 matWorld;
+	glm::mat4 matInvWorld;
+	glm::mat4 matInvTransposeWorld;
+};
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+struct MaterialInfo
+{
+	MaterialInfo()
+	{
+		albedoFilePath.clear();
+		albedoColor = glm::vec4(0);		// logic is dependent on this being 0 i.e. if length(albedoColor) == 0 then we use Maya's color!
+		roughness = 1.0f;
+		refrIndex = 1.0f;
+	}
+
+	std::string		albedoFilePath;
+	glm::vec4		albedoColor;
+	float			roughness;
+	float			refrIndex;
+};
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+struct MeshInfo
+{
+	MeshInfo()
+	{
+		filePath.clear();
+		position = glm::vec3(0);
+		rotationAxis = glm::vec3(1);
+		rotationAngle = 0.0f;
+		scale = glm::vec3(1);
+		leafSize = 1;
+		isLightSource = false;
+	}
+
+	std::string		filePath;
+
+	// Transform...
+	glm::vec3		position;
+	glm::vec3		rotationAxis;
+	float			rotationAngle;
+	glm::vec3		scale;
+
+	// Material
+	MaterialInfo    matInfo;
+
+	// BVH related...
+	uint32_t		leafSize;
+
+	// Misc...
+	bool			isLightSource;
+};
```

## `f4678f7` — 2019-05-12 _(master)_

> - Texture info is now fecthed from FBX file itself - Added new scene

```diff
diff --git a/Application.cpp b/Application.cpp
index 30ba87d..439fb5f 100644
--- a/Application.cpp
+++ b/Application.cpp
@@ -19,9 +19,9 @@
 ///////////////////////////////////////////////////////////////////////////////////////////////////
 Application::Application()
 {
-	m_iBackbufferWidth = 480;
-	m_iBackbufferHeight = 270;
-	m_iNumSamples = 100;
+	m_iBackbufferWidth = 960;
+	m_iBackbufferHeight = 540;
+	m_iNumSamples = 200;
 	m_dTotalRenderTime = 0;
 	m_dDenoiserTime = 0;
 	m_bThreaded = false;
@@ -57,6 +57,7 @@ void Application::Initialize(HWND hwnd, bool _threaded)
 	m_pScene = new Scene();
 	//m_pScene->InitScene(m_iBackbufferWidth, m_iBackbufferHeight);
 	m_pScene->InitCornellScene(m_iBackbufferWidth, m_iBackbufferHeight);
+	//m_pScene->InitTowerScene(m_iBackbufferWidth, m_iBackbufferHeight);
 
 	// Create Open Image Denoise Device
 	m_oidnDevice = oidn::newDevice();
diff --git a/RayTracer/Scene.cpp b/RayTracer/Scene.cpp
index 887752d..7bff815 100644
--- a/RayTracer/Scene.cpp
+++ b/RayTracer/Scene.cpp
@@ -88,7 +88,7 @@ void Scene::InitCornellScene(float screenWidth, float screenHeight)
 	// Override miss color to black
 	m_colMiss = glm::vec4(0.0f);
 	
-	Sphere* pSphereLight = new Sphere(glm::vec3(0.0f, 1.0f, 1.0f), 1.0f, new DiffuseLight(new ConstantTexture(glm::vec3(1.0f, 1.0f, 1.0f))));
+	Sphere* pSphereLight = new Sphere(glm::vec3(-1.5f, 0.5f, 2.0f), 0.25f, new DiffuseLight(new ConstantTexture(glm::vec3(1.0f, 1.0f, 0.0f))));
 
 	// Room Mesh
 	MeshInfo roomInfo;
@@ -107,19 +107,19 @@ void Scene::InitCornellScene(float screenWidth, float screenHeight)
 	cubeLeftInfo.rotationAngle = 9.0f;
 	cubeLeftInfo.scale = glm::vec3(1.6f, 3.6f, 1.6f);
 	cubeLeftInfo.matInfo.albedoColor = glm::vec4(1, 1, 1, 1);
-	cubeLeftInfo.matInfo.roughness = 0.2f;
+	cubeLeftInfo.matInfo.roughness = 0.8f;
 	TriangleMesh* pLeftCube = new TriangleMesh(cubeLeftInfo);
 
 	// Cube 2
 	MeshInfo cubeRightInfo;
-	cubeRightInfo.filePath = "models/Cube.fbx";
-	cubeRightInfo.isLightSource = false;
-	cubeRightInfo.leafSize = 10;
-	cubeRightInfo.position = glm::vec3(-0.9f, 0.9f, 1.0f);
+	cubeRightInfo.filePath = "models/tigerLambert.fbx";
+	cubeRightInfo.isLightSource = true;
+	cubeRightInfo.leafSize = 512;
+	cubeRightInfo.position = glm::vec3(-0.9f, 0.0f, 1.0f);
 	cubeRightInfo.rotationAxis = glm::vec3(0, 1, 0);
-	cubeRightInfo.rotationAngle = -6.0f;
-	cubeRightInfo.scale = glm::vec3(1.8f);
-	cubeRightInfo.matInfo.albedoColor = glm::vec4(0, 0, 1, 1);
+	cubeRightInfo.rotationAngle = -45.0f;
+	cubeRightInfo.scale = glm::vec3(0.5f);
+	cubeRightInfo.matInfo.albedoColor = glm::vec4(0.7f, 0.8f, 0.0f, 1.0f);
 	TriangleMesh* pRightCube = new TriangleMesh(cubeRightInfo);
 
 	// Light Quad
@@ -131,7 +131,7 @@ void Scene::InitCornellScene(float screenWidth, float screenHeight)
 	lightInfo.scale = glm::vec3(2);
 	TriangleMesh* pLight = new TriangleMesh(lightInfo);
 
-	vecHitables.push_back(pLight);
+	//vecHitables.push_back(pLight);
 	vecHitables.push_back(pRoom);
 	vecHitables.push_back(pLeftCube);
 	vecHitables.push_back(pRightCube);
@@ -139,6 +139,42 @@ void Scene::InitCornellScene(float screenWidth, float screenHeight)
 	Profiler::getInstance().WriteToProfiler("Triangle Count:", pRoom->GetTriangleCount() + pLight->GetTriangleCount() + pLeftCube->GetTriangleCount() + pRightCube->GetTriangleCount());
 }
 
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void Scene::InitTowerScene(float screenWidth, float screenHeight)
+{
+	// Initialize Camera first...!!!
+	glm::vec3 cameraPosition = glm::vec3(5.0f, 2.5f, 5.0f);
+	glm::vec3 cameraLookAt = glm::vec3(0.0f, 0.0f, 0.0f);
+	m_pCamera = new Camera();
+	m_pCamera->InitCamera(cameraPosition, cameraLookAt, screenWidth, screenHeight);
+
+	// Override miss color to black
+	m_colMiss = glm::vec4(0.01f);
+
+	// Sphere Ground
+	glm::vec3 center1(0.0f, -100.5f, 0.0f);
+	glm::vec3 albedo1(0.1f, 0.1f, 0.1f);
+	Material* pMatSphereGround = new Metal(new ConstantTexture(albedo1), 0.0f);
+	Sphere* pSphereGround = new Sphere(center1, 100.0f, pMatSphereGround);
+
+	// Tower
+	MeshInfo towerInfo;
+	towerInfo.filePath = "models/Tower.fbx";
+	towerInfo.isLightSource = true;
+	towerInfo.leafSize = 512;
+	towerInfo.position = glm::vec3(-0.9f, 0.0f, 1.0f);
+	towerInfo.rotationAxis = glm::vec3(0, 1, 0);
+	towerInfo.rotationAngle = -60.0f;
+	towerInfo.scale = glm::vec3(0.5f);
+	towerInfo.matInfo.albedoColor = glm::vec4(2.0f, 1.5f, 1.5f, 1.0f);
+	TriangleMesh* pTower = new TriangleMesh(towerInfo);
+
+	vecHitables.push_back(pSphereGround);
+	vecHitables.push_back(pTower);
+
+	Profiler::getInstance().WriteToProfiler("Triangle Count:", pTower->GetTriangleCount());
+}
+
 ///////////////////////////////////////////////////////////////////////////////////////////////////
 void Scene::InitRandomScene(float screenWidth, float screenHeight)
 {
diff --git a/RayTracer/Scene.h b/RayTracer/Scene.h
index 542e6e2..70233a1 100644
--- a/RayTracer/Scene.h
+++ b/RayTracer/Scene.h
@@ -15,6 +15,7 @@ public:
 
 	void InitScene(float screenWidth, float screenHeight);
 	void InitCornellScene(float screenWidth, float screenHeight);
+	void InitTowerScene(float screenWidth, float screenHeight);
 	void InitRandomScene(float screenWidth, float screenHeight);
 
 	inline Camera* getCamera() { if(m_pCamera) return m_pCamera; }
diff --git a/RayTracer/TriangleMesh.cpp b/RayTracer/TriangleMesh.cpp
index 5d7e106..9a75d66 100644
--- a/RayTracer/TriangleMesh.cpp
+++ b/RayTracer/TriangleMesh.cpp
@@ -138,9 +138,13 @@ void TriangleMesh::ProcessMesh(aiMesh* mesh, const aiScene* scene)
 			{
 				// Extract texture info if filepath or flat color?
 				Texture* textureInfo = nullptr;
-				if (!m_ptrMeshInfo->matInfo.albedoFilePath.empty())
+				
+				// Look if material has texture info...
+				aiString path;
+				if (AI_SUCCESS == aiGetMaterialTexture(material, aiTextureType_DIFFUSE, 0, &path))
 				{
-					textureInfo = new ImageTexture("models/" + m_ptrMeshInfo->matInfo.albedoFilePath);
+					std::string filePath = std::string(path.C_Str());
+					textureInfo = new ImageTexture("models/" + filePath);
 					m_ptrMaterial = new Lambertian(textureInfo);
 				}
 				else
@@ -173,9 +177,12 @@ void TriangleMesh::ProcessMesh(aiMesh* mesh, const aiScene* scene)
 				Texture* textureInfo = nullptr;
 				float roughness = m_ptrMeshInfo->matInfo.roughness;
 
-				if (!m_ptrMeshInfo->matInfo.albedoFilePath.empty())
+				// Look if material has texture info...
+				aiString path;
+				if (AI_SUCCESS == aiGetMaterialTexture(material, aiTextureType_DIFFUSE, 0, &path))
 				{
-					textureInfo = new ImageTexture("models/" + m_ptrMeshInfo->matInfo.albedoFilePath);
+					std::string filePath = std::string(path.C_Str());
+					textureInfo = new ImageTexture("models/" + filePath);
 					m_ptrMaterial = new Metal(textureInfo, roughness);
 				}
 				else
diff --git a/RayTracer/TriangleMeshInfo.h b/RayTracer/TriangleMeshInfo.h
index f465d73..e4d39fd 100644
--- a/RayTracer/TriangleMeshInfo.h
+++ b/RayTracer/TriangleMeshInfo.h
@@ -42,13 +42,11 @@ struct MaterialInfo
 {
 	MaterialInfo()
 	{
-		albedoFilePath.clear();
 		albedoColor = glm::vec4(0);		// logic is dependent on this being 0 i.e. if length(albedoColor) == 0 then we use Maya's color!
 		roughness = 1.0f;
 		refrIndex = 1.0f;
 	}
 
-	std::string		albedoFilePath;
 	glm::vec4		albedoColor;
 	float			roughness;
 	float			refrIndex;
```

