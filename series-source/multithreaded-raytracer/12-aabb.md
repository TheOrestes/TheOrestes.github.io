# Post 12 — AABBs, and the reflection bug they exposed

## `da1081d` — 2018-12-08 _(master)_

> Added AABB support for triangle meshes. Ray tracer now considers AABB intersection before doing triangle-ray intersection.

```diff
diff --git a/RayTracer/AABB.cpp b/RayTracer/AABB.cpp
new file mode 100644
index 0000000..9356763
--- /dev/null
+++ b/RayTracer/AABB.cpp
@@ -0,0 +1,64 @@
+
+#include "AABB.h"
+#include <algorithm>
+
+/////////////////////////////////////////////////////////////////////////////////////////////////////
+AABB::AABB()
+{
+	minBound = glm::vec3(0);
+	maxBound = glm::vec3(0);
+}
+
+/////////////////////////////////////////////////////////////////////////////////////////////////////
+void AABB::UpdateBB(const glm::vec3& _pos)
+{
+	if (_pos.x < minBound.x) { minBound.x = _pos.x; }
+	if (_pos.y < minBound.y) { minBound.y = _pos.y; }
+	if (_pos.z < minBound.z) { minBound.z = _pos.z; }
+
+	if (_pos.x > maxBound.x) { maxBound.x = _pos.x; }
+	if (_pos.y > maxBound.y) { maxBound.y = _pos.y; }
+	if (_pos.z > maxBound.z) { maxBound.z = _pos.z; }
+}
+
+bool AABB::hit(const Ray & r, float tmin, float tmax)
+{
+	glm::vec3 rayOrigin = r.GetRayOrigin();
+	glm::vec3 rayDirection = r.GetRayDirection();
+	glm::vec3 rayInvDirection = r.GetInvRayDirection();
+	
+	// X Direction
+	float t0x = (minBound.x - rayOrigin.x) * rayInvDirection.x;
+	float t1x = (maxBound.x - rayOrigin.x) * rayInvDirection.x;
+	if (rayInvDirection.x < 0.0f)
+		std::swap(t0x, t1x);
+	
+	tmin = (t0x > tmin) ? t0x : tmin;
+	tmax = (t1x < tmax) ? t1x : tmax;
+	if (tmax <= tmin)
+		return false;
+	
+	// Y Direction
+	float t0y = (minBound.y - rayOrigin.y) * rayInvDirection.y;
+	float t1y = (maxBound.y - rayOrigin.y) * rayInvDirection.y;
+	if (rayInvDirection.y < 0.0f)
+		std::swap(t0y, t1y);
+	
+	tmin = (t0y > tmin) ? t0y : tmin;
+	tmax = (t1y < tmax) ? t1y : tmax;
+	if (tmax <= tmin)
+		return false;
+	
+	// Z Direction
+	float t0z = (minBound.z - rayOrigin.z) * rayInvDirection.z;
+	float t1z = (maxBound.z - rayOrigin.z) * rayInvDirection.z;
+	if (rayInvDirection.z < 0.0f)
+		std::swap(t0z, t1z);
+	
+	tmin = (t0z > tmin) ? t0z : tmin;
+	tmax = (t1z < tmax) ? t1z : tmax;
+	if (tmax <= tmin)
+		return false;
+
+	return true;
+}
diff --git a/RayTracer/AABB.h b/RayTracer/AABB.h
new file mode 100644
index 0000000..7bcd84d
--- /dev/null
+++ b/RayTracer/AABB.h
@@ -0,0 +1,21 @@
+#pragma once
+
+#include "glm\glm.hpp"
+#include "Ray.h"
+
+class AABB
+{
+public:
+	AABB();
+	~AABB() {}
+	AABB(const glm::vec3& _min, const glm::vec3& _max) :
+		minBound(_min),
+		maxBound(_max) {}
+
+	void UpdateBB(const glm::vec3& _pos);
+	bool hit(const Ray& r, float tmin, float tmax);
+
+private:
+	glm::vec3 minBound;
+	glm::vec3 maxBound;
+};
\ No newline at end of file
diff --git a/RayTracer/Ray.h b/RayTracer/Ray.h
index 4c55e7b..bfa6fe5 100644
--- a/RayTracer/Ray.h
+++ b/RayTracer/Ray.h
@@ -10,13 +10,17 @@ public:
 	{ 
 		origin = A;
 		direction = B; 
+
+		invDirection = glm::vec3(1 / direction.x, 1/direction.y, 1/direction.z);
 	}
 
 	inline glm::vec3 GetRayOrigin() const { return origin; }
 	inline glm::vec3 GetRayDirection() const { return direction; }
+	inline glm::vec3 GetInvRayDirection() const { return invDirection; }
 	inline glm::vec3 GetPointAt(float t) const { return origin + t * direction; }
 
 private:
 	glm::vec3 origin;
 	glm::vec3 direction;
+	glm::vec3 invDirection;
 };
\ No newline at end of file
diff --git a/RayTracer/TriangleMesh.cpp b/RayTracer/TriangleMesh.cpp
index 27124b1..85c27a7 100644
--- a/RayTracer/TriangleMesh.cpp
+++ b/RayTracer/TriangleMesh.cpp
@@ -1,6 +1,7 @@
 
 #include "glm\glm.hpp"
 #include "TriangleMesh.h"
+#include "AABB.h"
 #include <Windows.h>
 
 TriangleMesh::TriangleMesh()
@@ -13,6 +14,8 @@ TriangleMesh::TriangleMesh(const std::string& path, Material* ptr_mat)
 	m_vecTriangles.clear();
 	m_ptrMaterial = ptr_mat;
 
+	m_ptrAABB = new AABB();
+
 	LoadModel(path);
 }
 
@@ -57,6 +60,7 @@ void TriangleMesh::ProcessMesh(aiMesh* mesh, const aiScene* scene)
 	for (unsigned int i = 0; i < mesh->mNumVertices; i++)
 	{
 		vecVertices.push_back(mesh->mVertices[i]);
+		m_ptrAABB->UpdateBB(glm::vec3(mesh->mVertices[i].x, mesh->mVertices[i].y, mesh->mVertices[i].z));
 	}
 
 	for (unsigned int i = 0; i < mesh->mNumFaces; i++)
@@ -84,14 +88,17 @@ bool TriangleMesh::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) con
 	bool isIntersection = false;
 	float closestSoFar = tmax;
 
-	for (int i = 0; i < m_vecTriangles.size(); i++)
+	if (m_ptrAABB->hit(r, tmin, tmax))
 	{
-		if (m_vecTriangles[i]->hit(r, tmin, closestSoFar, rec))
+		for (int i = 0; i < m_vecTriangles.size(); i++)
 		{
-			isIntersection = true;
-			closestSoFar = rec.t;
+			if (m_vecTriangles[i]->hit(r, tmin, closestSoFar, rec))
+			{
+				isIntersection = true;
+				closestSoFar = rec.t;
+			}
 		}
 	}
-
+	
 	return isIntersection;
 }
diff --git a/RayTracer/TriangleMesh.h b/RayTracer/TriangleMesh.h
index bd87176..581cb93 100644
--- a/RayTracer/TriangleMesh.h
+++ b/RayTracer/TriangleMesh.h
@@ -9,6 +9,7 @@
 #include "Triangle.h"
 
 class Material;
+class AABB;
 
 class TriangleMesh : public Hitable
 {
@@ -26,5 +27,6 @@ private:
 	void ProcessMesh(aiMesh* mesh, const aiScene* scene);
 
 	std::vector<Triangle*> m_vecTriangles;
-	Material* m_ptrMaterial;
+	AABB*				   m_ptrAABB;
+	Material*			   m_ptrMaterial;
 };
diff --git a/WindowsRayTracer.cpp b/WindowsRayTracer.cpp
index 501ca84..eee7040 100644
--- a/WindowsRayTracer.cpp
+++ b/WindowsRayTracer.cpp
@@ -26,7 +26,7 @@
 
 const int COLOR_CHANNELS = 3; // RGB
 const int gBackbufferWidth = 960;
-const int gBackbufferHeight = 540;
+const int gBackbufferHeight = 480;
 const int nSamples = 1;
 
 unsigned long long int numRays = 0;
```

## `5770d79` — 2019-04-05 _(master)_

> Fixed reflection bug, modified AABB hit function.

```diff
diff --git a/Application.cpp b/Application.cpp
index 6bd2204..d10868d 100644
--- a/Application.cpp
+++ b/Application.cpp
@@ -15,9 +15,9 @@
 ///////////////////////////////////////////////////////////////////////////////////////////////////
 Application::Application()
 {
-	m_iBackbufferWidth = 960;
-	m_iBackbufferHeight = 540;
-	m_iNumSamples = 10;
+	m_iBackbufferWidth = 480;
+	m_iBackbufferHeight = 270;
+	m_iNumSamples = 1;
 	m_dTotalRenderTime = 0;
 	m_bThreaded = false;
 
@@ -129,7 +129,7 @@ glm::vec3 Application::TraceColor(const Ray & r, int depth, int& rayCount)
 
 		if (depth < 50 && rec.mat_ptr->Scatter(r, rec, rayCount, attenuation, scatteredRay))
 		{
-			if (glm::length(scatteredRay.GetRayOrigin() - scatteredRay.GetRayDirection()) < 0.0000001f)
+			if (glm::distance(scatteredRay.GetRayOrigin(), scatteredRay.GetRayDirection()) < 0.0000001f)
 				traceColor = attenuation;
 			else
 				traceColor = attenuation * (TraceColor(scatteredRay, depth + 1, rayCount));
diff --git a/RayTracer/AABB.cpp b/RayTracer/AABB.cpp
index f5c2dbc..158f494 100644
--- a/RayTracer/AABB.cpp
+++ b/RayTracer/AABB.cpp
@@ -49,52 +49,21 @@ bool AABB::hit(const Ray & r, float tmin, float tmax, HitRecord& rec)
 {
 	++rec.rayBoxQuery;
 
-	bool xHit = true; 
-	bool yHit = true;
-	bool zHit = true;
+	for (int a = 0; a < 3; a++)
+	{
+		float t0 = fminf((minBound[a] - r.GetRayOrigin()[a]) / r.GetRayDirection()[a],
+						 (maxBound[a] - r.GetRayOrigin()[a]) / r.GetRayDirection()[a]);
 
-	glm::vec3 rayOrigin = r.GetRayOrigin();
-	glm::vec3 rayDirection = r.GetRayDirection();
-	glm::vec3 rayInvDirection = r.GetInvRayDirection();
-	
-	// Direction X
-	float t0x = (minBound[0] - rayOrigin[0]) * rayInvDirection[0];
-	float t1x = (maxBound[0] - rayOrigin[0]) * rayInvDirection[0];
-	if (rayInvDirection[0] < 0.0f)
-		std::swap(t0x, t1x);
-	
-	tmin = (t0x > tmin) ? t0x : tmin;
-	tmax = (t1x < tmax) ? t1x : tmax;
-	if (tmax <= tmin)
-		xHit = false;
-	
-	// Y Direction
-	float t0y = (minBound[1] - rayOrigin[1]) * rayInvDirection[1];
-	float t1y = (maxBound[1] - rayOrigin[1]) * rayInvDirection[1];
-	if (rayInvDirection[1] < 0.0f)
-		std::swap(t0y, t1y);
-	
-	tmin = (t0y > tmin) ? t0y : tmin;
-	tmax = (t1y < tmax) ? t1y : tmax;
-	if (tmax <= tmin)
-		yHit = false;
-	
-	// Z Direction
-	float t0z = (minBound[2] - rayOrigin[2]) * rayInvDirection[2];
-	float t1z = (maxBound[2] - rayOrigin[2]) * rayInvDirection[2];
-	if (rayInvDirection[1] < 0.0f)
-		std::swap(t0z, t1z);
-	
-	tmin = (t0z > tmin) ? t0z : tmin;
-	tmax = (t1z < tmax) ? t1z : tmax;
-	if (tmax <= tmin)
-		zHit = false;
+		float t1 = fmaxf((minBound[a] - r.GetRayOrigin()[a]) / r.GetRayDirection()[a],
+						 (maxBound[a] - r.GetRayOrigin()[a]) / r.GetRayDirection()[a]);
 
-	if (xHit && yHit && zHit)
-	{
-		++rec.rayBoxSuccess;
-		return true;
+		tmin = fmaxf(t0, tmin);
+		tmax = fminf(t1, tmax);
+
+		if (tmax <= tmin)
+			return false;
 	}
-	else
-		return false;
+
+	++rec.rayBoxSuccess;
+	return true;
 }
diff --git a/RayTracer/LameBVH.cpp b/RayTracer/LameBVH.cpp
index 16e6e7e..620129a 100644
--- a/RayTracer/LameBVH.cpp
+++ b/RayTracer/LameBVH.cpp
@@ -57,8 +57,8 @@ bool BVHTree::Hit(BVHNode * node, const Ray & ray, float & tMin, float & tMax, H
 
 		BVHNode *firstNode = 0;
 		BVHNode *secondNode = 0;
-		BVHNode *leftNode = node->leftNode;
 
+		BVHNode *leftNode = node->leftNode;
 		if (leftNode)
 		{
 			bool intersectedL = leftNode->bbox.hit(ray, tL0, tL1, rec);
diff --git a/RayTracer/Scene.cpp b/RayTracer/Scene.cpp
index cdf7149..24a89ec 100644
--- a/RayTracer/Scene.cpp
+++ b/RayTracer/Scene.cpp
@@ -25,35 +25,30 @@ Scene::~Scene()
 
 void Scene::InitScene()
 {
-	glm::vec3 center0(-3.0f, 0.15f, 0);
-	glm::vec3 albedo0(1.0f, 0.0f, 0.0f);
-	Material* pMatSphere0 = new Metal(new ConstantTexture(glm::vec3(1.0f, 0.3f, 0.0f)), 0);
-	Sphere* pSphere0 = new Sphere(center0, 0.8f, pMatSphere0);
-
-	// Sphere2
+	// Sphere Ground
 	glm::vec3 center1(0.0f, -100.5f, 0.0f);
 	glm::vec3 albedo1(0.2f, 0.2f, 0.2f);
-	Material* pMatSphere1 = new Lambertian(new ConstantTexture(albedo1));
-	Sphere* pSphere1 = new Sphere(center1, 100.0f, pMatSphere1);
+	Material* pMatSphereGround = new Lambertian(new ConstantTexture(albedo1));
+	Sphere* pSphereGround = new Sphere(center1, 100.0f, pMatSphereGround);
+
+	Sphere* pSphereGlass1 = new Sphere(glm::vec3(-4.0f, 0.4f, 0.0f), 1.0f, new Transparent(1.3f));
+	Sphere* pSphereMetal = new Sphere(glm::vec3(0.0f, 0.7f, -3.5f), 1.4f, new Metal(new ConstantTexture(glm::vec3(1.0f, 0.1f, 0.0f)), 0));
+	Sphere* pSphereEarth = new Sphere(glm::vec3(2.5f, 0.0f, 0.0f), 0.5, new Lambertian(new ImageTexture("models/earth.jpg")));
 
-	Sphere* pSphere2 = new Sphere(glm::vec3(-1.0f, 0.0f, 1.5f), 0.5f, new Transparent(1.5f));
-	Sphere* pSphere3 = new Sphere(glm::vec3(-4.0f, 0.4f, 0.0f), 1.0f, new Metal(new ConstantTexture(glm::vec3(1.0f, 0.1f, 0.0f)), 0));
-	Sphere* pSphere4 = new Sphere(glm::vec3(2.5f, 0.0f, 0.0f), 0.5, new Lambertian(new ImageTexture("models/earth.jpg")));
 	//Triangle* pTriangle0  = new Triangle(glm::vec3(-2.0f, 0.0f, -1.0f), glm::vec3(2.0f, 0.0f, -1.0f), glm::vec3(0.0f, 2.0f, -1.0f), new Metal(new ConstantTexture(glm::vec3(0.0, 1.0f, 0.0f)), 0.5f));
-	Texture* baseTexture = new ImageTexture("models/Body_Color.jpg");
-	Material* pMatMesh = new Lambertian(baseTexture);
 	//Material* pMatMesh = new FlatColor (new ConstantTexture(glm::vec3(1,1,0)));
 	//TriangleMesh* pMesh0 = new TriangleMesh("models/UVCube5.fbx", pMatSphere0);
+
+	Texture* baseTexture = new ImageTexture("models/Body_Color.jpg");
+	Material* pMatMesh = new Lambertian(baseTexture);
 	TriangleMesh* pMesh0 = new TriangleMesh("models/barb1.fbx", pMatMesh);
 
 	Profiler::getInstance().WriteToProfiler("Triangle Count:", pMesh0->GetTriangleCount());
 
-	//vecHitables.push_back(pSphere0);
-	vecHitables.push_back(pSphere1);
-	//vecHitables.push_back(pSphere2);
-	//vecHitables.push_back(pSphere3);
-	vecHitables.push_back(pSphere4);
-	//vecHitables.push_back(pTriangle0);
+	vecHitables.push_back(pSphereGround);
+	vecHitables.push_back(pSphereGlass1);
+	vecHitables.push_back(pSphereMetal);
+	vecHitables.push_back(pSphereEarth);
 	vecHitables.push_back(pMesh0);
 }
 
diff --git a/RayTracer/Transparent.h b/RayTracer/Transparent.h
index 4e9e36e..23e7665 100644
--- a/RayTracer/Transparent.h
+++ b/RayTracer/Transparent.h
@@ -33,7 +33,7 @@ public:
 		{
 			outward_normal = rec.N;
 			ni_over_nt = 1 / refr_index;
-			cosine = glm::dot(-ray_direction, rec.N) / glm::length(ray_direction);
+			cosine = -glm::dot(ray_direction, rec.N) / glm::length(ray_direction);
 		}
 
 		if (Helper::Refract(ray_direction, outward_normal, ni_over_nt, refracted))
```

