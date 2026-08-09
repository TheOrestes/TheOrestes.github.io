# Post 9 — Assimp, and loading actual meshes

## `8b3ab6a` — 2018-11-01 _(master)_

> Assimp Integration

```diff
diff --git a/RayTracer/Camera.cpp b/RayTracer/Camera.cpp
new file mode 100644
index 0000000..6d54767
--- /dev/null
+++ b/RayTracer/Camera.cpp
@@ -0,0 +1,45 @@
+
+#include <Windows.h>
+#include "Camera.h"
+
+Camera::Camera()
+{
+	aperture = 0.0f;
+	focus_dist = 1.0f;
+	vfov = 45.0f;
+}
+
+Camera::~Camera()
+{
+
+}
+
+void Camera::InitCamera(float screenWidth, float screenHeight)
+{
+	lookFrom = Vector3(4.0f, 4.0f, 7.0f);
+	lookAt = Vector3(0.0f, 2.0f, 0.0f);
+	Up = Vector3(0.0f, 1.0f, 0.0f);
+
+	lens_radius = aperture / 2.0f;
+	 
+	float theta = vfov * PI / 180.0f;
+	float half_height = tan(theta / 2);
+	float half_width = (screenWidth / screenHeight) * half_height;
+
+	origin = lookFrom;
+	w = UnitVector(lookFrom - lookAt);
+	u = UnitVector(Cross(Up, w));
+	v = Cross(w, u);
+
+	lower_left_corner = origin - half_width * focus_dist * u - half_height * focus_dist * v - focus_dist * w;
+	horizontal = 2 * half_width * focus_dist * u;
+	vertical = 2 * half_height * focus_dist * v;
+}
+
+Ray Camera::get_ray(float s, float t)
+{
+	Vector3 rd = lens_radius * Helper::GetRandomInUnitDisk();
+	Vector3 offset = rd.x * u + rd.y * v;
+	return Ray(origin + offset, lower_left_corner + s * horizontal + t * vertical - origin - offset);
+}
+
diff --git a/RayTracer/Camera.h b/RayTracer/Camera.h
index f7c2eac..6351fc6 100644
--- a/RayTracer/Camera.h
+++ b/RayTracer/Camera.h
@@ -6,36 +6,24 @@
 class Camera
 {
 public:
-	Camera(Vector3 lookFrom, Vector3 lookAt, Vector3 Up, float vfov, float aspect, float aperture, float focus_dist)	// vofv is vertical fov
+	static Camera& getInstance()
 	{
-		lens_radius = aperture / 2.0f;
-
-		float theta = vfov * PI / 180.0f;
-		float half_height = tan(theta / 2);
-		float half_width = aspect * half_height;
-
-		origin = lookFrom;
-		w = unit_vector(lookFrom - lookAt);
-		u = unit_vector(cross(Up, w));
-		v = cross(w, u);
-
-		lower_left_corner = origin - half_width * focus_dist * u - half_height * focus_dist * v - focus_dist * w;
-		horizontal = 2 * half_width * focus_dist * u;
-		vertical = 2 * half_height * focus_dist * v;
+		static Camera instance;
+		return instance;
 	}
 
-	Ray get_ray(float s, float t)
-	{
-		Vector3 rd = lens_radius * Helper::GetRandomInUnitDisk();
-		Vector3 offset = rd.x * u + rd.y * v;
-		return Ray(origin + offset, lower_left_corner + s * horizontal + t * vertical - origin - offset);
-	}
+	~Camera();
+
+	void InitCamera(float screenWidth, float screenHeight);
+	Ray get_ray(float s, float t);
 
 private:
+	Camera();
+	Vector3 lookFrom, lookAt, Up;
 	Vector3 origin;
 	Vector3 lower_left_corner;
 	Vector3 horizontal;
 	Vector3 vertical;
 	Vector3 u, v, w;
-	float lens_radius;
+	float lens_radius, aperture, vfov, focus_dist;
 };
diff --git a/RayTracer/Helper.h b/RayTracer/Helper.h
index 7de53bf..a55b3b6 100644
--- a/RayTracer/Helper.h
+++ b/RayTracer/Helper.h
@@ -1,6 +1,7 @@
 #pragma once
 
 #include "Vector3.h"
+#include <cstdlib>
 
 const float PI = 3.14159265358f;
 
@@ -22,7 +23,7 @@ namespace Helper
 		do
 		{
 			p = 2.0f * Vector3(GetRandom01(), GetRandom01(), 0.0f) - Vector3(1, 1, 0);
-		} while (dot(p, p) >= 1.0f);
+		} while (Dot(p, p) >= 1.0f);
 		
 		return p;
 	}
@@ -34,25 +35,25 @@ namespace Helper
 		do
 		{
 			P = 2.0f * Vector3(GetRandom01(), GetRandom01(), GetRandom01()) - Vector3(1, 1, 1);
-		} while (P.squaredLength() >= 1.0f);
+		} while (P.LengthSquared() >= 1.0f);
 
 		return P;
 	}
 
 	inline Vector3 Reflect(const Vector3& v, const Vector3& n)
 	{
-		return v - 2 * dot(v, n) * n;
+		return v - 2 * Dot(v, n) * n;
 	}
 
 	inline bool Refract(const Vector3& v, const Vector3& n, float ni_over_nt, Vector3& refracted)
 	{
-		Vector3 unit_v = unit_vector(v);
-		float NdotV = dot(unit_v, n);
-		float discriminant = 1.0 - ni_over_nt * ni_over_nt * (1 - NdotV * NdotV);
+		Vector3 unit_v = UnitVector(v);
+		float NDotV = Dot(unit_v, n);
+		float discriminant = 1.0 - ni_over_nt * ni_over_nt * (1 - NDotV * NDotV);
 
 		if (discriminant > 0)
 		{
-			refracted = ni_over_nt * (unit_v - NdotV * n) - sqrt(discriminant) * n;
+			refracted = ni_over_nt * (unit_v - NDotV * n) - sqrt(discriminant) * n;
 			return true;
 		}
 		else
diff --git a/RayTracer/Metal.cpp b/RayTracer/Metal.cpp
index f75bf1a..a2b43c3 100644
--- a/RayTracer/Metal.cpp
+++ b/RayTracer/Metal.cpp
@@ -4,8 +4,8 @@
 
 bool Metal::Scatter(const Ray& r_in, const HitRecord& rec, Vector3& attenuation, Ray& scatterd) const
 {
-	Vector3 target = Helper::Reflect(unit_vector(r_in.GetRayDirection()), rec.N);
+	Vector3 target = Helper::Reflect(UnitVector(r_in.GetRayDirection()), rec.N);
 	scatterd = Ray(rec.P, target + fuzz * Helper::RandomInUnitSphere());
 	attenuation = Albedo;
-	return (dot(scatterd.GetRayDirection(), rec.N) > 0);
+	return (Dot(scatterd.GetRayDirection(), rec.N) > 0);
 }
\ No newline at end of file
diff --git a/RayTracer/Ray.h b/RayTracer/Ray.h
index 4eb083b..29ce595 100644
--- a/RayTracer/Ray.h
+++ b/RayTracer/Ray.h
@@ -12,9 +12,9 @@ public:
 		direction = B; 
 	}
 
-	Vector3 GetRayOrigin() const { return origin; }
-	Vector3 GetRayDirection() const { return direction; }
-	Vector3 GetPointAt(float t) const { return origin + t * direction; }
+	inline Vector3 GetRayOrigin() const { return origin; }
+	inline Vector3 GetRayDirection() const { return direction; }
+	inline Vector3 GetPointAt(float t) const { return origin + t * direction; }
 
 private:
 	Vector3 origin;
diff --git a/RayTracer/Scene.cpp b/RayTracer/Scene.cpp
index 9a1d498..cd05ca1 100644
--- a/RayTracer/Scene.cpp
+++ b/RayTracer/Scene.cpp
@@ -1,42 +1,52 @@
 
 #include "Scene.h"
+#include "Camera.h"
 #include "Sphere.h"
 #include "Lambertian.h"
 #include "Metal.h"
 #include "Transparent.h"
 #include "Triangle.h"
+#include "TriangleMesh.h"
 
 Scene::Scene()
 {
 	vecHitables.clear();
-	//InitScene();
-	InitRandomScene();
+	InitScene();
+	//InitRandomScene();
+}
+
+Scene::~Scene()
+{
+	vecHitables.clear();
 }
 
 void Scene::InitScene()
 {
-	Vector3 center0(0.0f, 0, -3);
+	Vector3 center0(-3.0f, 0, 0);
 	Vector3 albedo0(1, 0, 0);
 	Material* pMatSphere0 = new Metal(albedo0, 0.2f);
-	Sphere* pSphere0 = new Sphere(center0, 0.5, pMatSphere0);
+	Sphere* pSphere0 = new Sphere(center0, 0.5f, pMatSphere0);
 
 	// Sphere2
 	Vector3 center1(0, -100.5, 0);
-	Vector3 albedo1(0.2, 0.2, 0.2);
+	Vector3 albedo1(0.3, 0.3, 0.3);
 	Material* pMatSphere1 = new Lambertian(albedo1);
 	Sphere* pSphere1 = new Sphere(center1, 100.0f, pMatSphere1);
 
-	Sphere* pSphere2 = new Sphere(Vector3(0, 0, 2), 0.5, new Lambertian(Vector3(1.0f, 0.0f, 0.0f)));
-	Sphere* pSphere3 = new Sphere(Vector3(-1.05f, 0, 0), 0.5, new Metal(Vector3(1.0, 0.2, 0.0), 0));
-	Sphere* pSphere4 = new Sphere(Vector3(1.05f, 0, 0), 0.5, new Transparent(1.5f));
-	Triangle* pTriangle0  = new Triangle(Vector3(-2.0f, 0.0f, -1.0f), Vector3(2.0f, 0.0f, -1.0f), Vector3(0.0f, 2.0f, -1.0f), new Metal(Vector3(0.0, 1.0f, 0.0f), 0.1f));
+	Sphere* pSphere2 = new Sphere(Vector3(0, 0.0f, 2.05f), 0.5f, new Transparent(1.5f));
+	Sphere* pSphere3 = new Sphere(Vector3(1.05f, 0.5f, -2.05), 1, new Metal(Vector3(1.0, 0.2, 0.0), 0));
+	Sphere* pSphere4 = new Sphere(Vector3(2.05f, 0.0f, 0), 0.5, new Lambertian(Vector3(0.0f, 0.4f, 1.0f)));
+	Triangle* pTriangle0  = new Triangle(Vector3(-2.0f, 0.0f, -1.0f), Vector3(2.0f, 0.0f, -1.0f), Vector3(0.0f, 2.0f, -1.0f), new Metal(Vector3(0.0, 1.0f, 0.0f), 0.5f));
+
+	TriangleMesh* pMesh0 = new TriangleMesh("models/deer.obj", new Metal(Vector3(0.0f, 0.85f, 0.25f), 0.2f));
 
 	vecHitables.push_back(pSphere0);
 	vecHitables.push_back(pSphere1);
 	vecHitables.push_back(pSphere2);
 	vecHitables.push_back(pSphere3);
 	vecHitables.push_back(pSphere4);
-	vecHitables.push_back(pTriangle0);
+	//vecHitables.push_back(pTriangle0);
+	vecHitables.push_back(pMesh0);
 }
 
 void Scene::InitRandomScene()
@@ -53,7 +63,7 @@ void Scene::InitRandomScene()
 			float choose_mat = Helper::GetRandom01();
 
 			Vector3 center(a + 0.9f * Helper::GetRandom01(), 0.2, b + 0.9 * Helper::GetRandom01());
-			if ((center - Vector3(4, 0.2, 0)).length() > 0.9f)
+			if ((center - Vector3(4, 0.2, 0)).Length() > 0.9f)
 			{
 				if (choose_mat < 0.8f)
 				{
diff --git a/RayTracer/Scene.h b/RayTracer/Scene.h
index b36c02c..4fbdb5c 100644
--- a/RayTracer/Scene.h
+++ b/RayTracer/Scene.h
@@ -3,9 +3,12 @@
 #include <vector>
 #include "Hitable.h"
 
+class Camera;
+
 class Scene
 {
 public:
+	~Scene();
 	
 	static Scene& getInstance()
 	{
@@ -13,7 +16,6 @@ public:
 		return instance;
 	}
 
-	
 	bool Trace(const Ray& r, float tmin, float tmax, HitRecord& rec);
 
 private:
diff --git a/RayTracer/Sphere.cpp b/RayTracer/Sphere.cpp
index f606e35..684b44b 100644
--- a/RayTracer/Sphere.cpp
+++ b/RayTracer/Sphere.cpp
@@ -5,9 +5,9 @@
 bool Sphere::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
 {
 	Vector3 oc = r.GetRayOrigin() - center;
-	float a = dot(r.GetRayDirection(), r.GetRayDirection());
-	float b = 2.0f * dot(oc, r.GetRayDirection());
-	float c = dot(oc, oc) - radius * radius;
+	float a = Dot(r.GetRayDirection(), r.GetRayDirection());
+	float b = 2.0f * Dot(oc, r.GetRayDirection());
+	float c = Dot(oc, oc) - radius * radius;
 	float discriminant = b * b - 4 * a* c;
 
 	float t;
diff --git a/RayTracer/Transparent.h b/RayTracer/Transparent.h
index 0f227c7..7ef5830 100644
--- a/RayTracer/Transparent.h
+++ b/RayTracer/Transparent.h
@@ -23,17 +23,17 @@ public:
 		float reflect_prob;
 		float cosine;
 
-		if (dot(ray_direction, rec.N) > 0)
+		if (Dot(ray_direction, rec.N) > 0)
 		{
 			outward_normal = -1 * rec.N;  // because we want inverted image for refraction? 
 			ni_over_nt = refr_index;
-			cosine = refr_index * dot(ray_direction, rec.N) / ray_direction.length();
+			cosine = refr_index * Dot(ray_direction, rec.N) / ray_direction.Length();
 		}
 		else
 		{
 			outward_normal = rec.N;
 			ni_over_nt = 1 / refr_index;
-			cosine = -dot(ray_direction, rec.N) / ray_direction.length();
+			cosine = -Dot(ray_direction, rec.N) / ray_direction.Length();
 		}
 
 		if (Helper::Refract(ray_direction, outward_normal, ni_over_nt, refracted))
diff --git a/RayTracer/Triangle.cpp b/RayTracer/Triangle.cpp
index 7c5aa41..6d0836f 100644
--- a/RayTracer/Triangle.cpp
+++ b/RayTracer/Triangle.cpp
@@ -9,18 +9,18 @@ bool Triangle::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
 	Vector3 edge1 = V2 - V1;
 	Vector3 edge2 = V0 - V2;
 
-	Vector3 N = unit_vector(cross(edge0, edge1));
+	Vector3 N = UnitVector(Cross(edge0, edge1));
 
 	// Check if ray & plane are parallel
-	float NdotRayDirection = dot(N, r.GetRayDirection());
-	if (fabs(NdotRayDirection) < 0.001f)
+	float NDotRayDirection = Dot(N, r.GetRayDirection());
+	if (fabs(NDotRayDirection) < 0.001f)
 		return false;
 
 	// Compute plane distance from origin
-	float d = dot(V0, N);
+	float d = Dot(V0, N);
 
 	// Compute t at which intersection happens!
-	float t = (d - dot(N, r.GetRayOrigin())) / NdotRayDirection;
+	float t = (d - Dot(N, r.GetRayOrigin())) / NDotRayDirection;
 
 	if (t < tmin || t > tmax)
 		return false;
@@ -34,7 +34,7 @@ bool Triangle::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
 	Vector3 P1 = P - V1;
 	Vector3 P2 = P - V2;
 
-	if (dot(N, cross(edge0, P0)) >= 0 && dot(N, cross(edge1, P1)) >= 0 && dot(N, cross(edge2, P2)) >= 0)
+	if (Dot(N, Cross(edge0, P0)) >= 0 && Dot(N, Cross(edge1, P1)) >= 0 && Dot(N, Cross(edge2, P2)) >= 0)
 	{
 		// Record hit data!!!
 		rec.t = t;
@@ -49,23 +49,23 @@ bool Triangle::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
 
 	//auto edge0 = V1 - V0;
 	//auto edge1 = V2 - V1;
-	//auto normal = unit_vector(cross(edge0, edge1));
-	//auto planeOffset = dot(V0, normal);
+	//auto normal = UnitVector(Cross(edge0, edge1));
+	//auto planeOffset = Dot(V0, normal);
 	//auto p0 = r.GetPointAt(tmin);
 	//auto p1 = r.GetPointAt(tmax);
-	//auto offset0 = dot(p0, normal);
-	//auto offset1 = dot(p1, normal);
+	//auto offset0 = Dot(p0, normal);
+	//auto offset1 = Dot(p1, normal);
 	//if ((offset0 - planeOffset)*(offset1 - planeOffset) <= 0.f) // Line segment intersects the plane of the triangle
 	//{
 	//	float t = tmin + (tmax - tmin)*(planeOffset - offset0) / (offset1 - offset0);
 	//	auto p = r.GetPointAt(t);
-	//	auto c0 = cross(edge0, p - V0);
-	//	auto c1 = cross(edge1, p - V1);
-	//	if (dot(c0, c1) >= 0.f)
+	//	auto c0 = Cross(edge0, p - V0);
+	//	auto c1 = Cross(edge1, p - V1);
+	//	if (Dot(c0, c1) >= 0.f)
 	//	{
 	//		auto edge2 = V0 - V2;
-	//		auto c2 = cross(edge2, p - V2);
-	//		if (dot(c1, c2) >= 0.f)
+	//		auto c2 = Cross(edge2, p - V2);
+	//		if (Dot(c1, c2) >= 0.f)
 	//		{
 	//			rec.t = t;
 	//			rec.P = p;
diff --git a/RayTracer/Triangle.h b/RayTracer/Triangle.h
index bfceb91..008d76a 100644
--- a/RayTracer/Triangle.h
+++ b/RayTracer/Triangle.h
@@ -1,7 +1,5 @@
 #pragma once
 
-#pragma once
-
 #include "Hitable.h"
 
 class Material;
diff --git a/RayTracer/TriangleMesh.cpp b/RayTracer/TriangleMesh.cpp
new file mode 100644
index 0000000..6a0da45
--- /dev/null
+++ b/RayTracer/TriangleMesh.cpp
@@ -0,0 +1,96 @@
+
+#include "TriangleMesh.h"
+#include <Windows.h>
+
+TriangleMesh::TriangleMesh()
+{
+
+}
+
+TriangleMesh::TriangleMesh(const std::string& path, Material* ptr_mat)
+{
+	m_vecTriangles.clear();
+	m_ptrMaterial = ptr_mat;
+
+	LoadModel(path);
+}
+
+void TriangleMesh::LoadModel(const std::string& path)
+{
+	Assimp::Importer importer;
+	const aiScene* scene = importer.ReadFile(path, aiProcess_Triangulate);
+
+	if (!scene || scene->mFlags == AI_SCENE_FLAGS_INCOMPLETE || !scene->mRootNode)
+	{
+		MessageBox(0, L"Assimp Error!", L"Error", MB_OK);
+		return;
+	}
+
+	// process root node recursively!
+	ProcessNode(scene->mRootNode, scene);
+}
+
+void TriangleMesh::ProcessNode(aiNode* node, const aiScene* scene)
+{
+	// node only contains indices to actual objects in the scene. But scene,
+	// conatins all the data, node is just to keep things organized.
+	for (unsigned int i = 0; i < node->mNumMeshes; ++i)
+	{
+		aiMesh* mesh = scene->mMeshes[node->mMeshes[i]];
+		ProcessMesh(mesh, scene);
+	}
+
+	// Once we have processed all the meshes, we recursively process
+	// each child node
+	for (unsigned int i = 0; i < node->mNumChildren; ++i)
+	{
+		ProcessNode(node->mChildren[i], scene);
+	}
+}
+
+void TriangleMesh::ProcessMesh(aiMesh* mesh, const aiScene* scene)
+{
+	std::vector<aiVector3D> vecVertices;
+	vecVertices.reserve(mesh->mNumVertices);
+
+	for (unsigned int i = 0; i < mesh->mNumVertices; i++)
+	{
+		vecVertices.push_back(mesh->mVertices[i]);
+	}
+
+	for (unsigned int i = 0; i < mesh->mNumFaces; i++)
+	{
+		aiFace* face = &(mesh->mFaces[i]);
+		int numIndices = face->mNumIndices;
+
+		unsigned int index0 = face->mIndices[0];
+		unsigned int index1 = face->mIndices[1]; 
+		unsigned int index2 = face->mIndices[2];
+
+		Vector3 pos0(vecVertices.at(index0).x, vecVertices.at(index0).y, vecVertices.at(index0).z);
+		Vector3 pos1(vecVertices.at(index1).x, vecVertices.at(index1).y, vecVertices.at(index1).z);
+		Vector3 pos2(vecVertices.at(index2).x, vecVertices.at(index2).y, vecVertices.at(index2).z);
+
+		Triangle* tri = new Triangle(pos0, pos1, pos2, m_ptrMaterial);
+
+		m_vecTriangles.push_back(tri);
+	}
+}
+
+/////////////////////////////////////////////////////////////////////////////////////////
+bool TriangleMesh::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
+{
+	bool isIntersection = false;
+	float closestSoFar = tmax;
+
+	for (int i = 0; i < m_vecTriangles.size(); i++)
+	{
+		if (m_vecTriangles[i]->hit(r, tmin, closestSoFar, rec))
+		{
+			isIntersection = true;
+			closestSoFar = rec.t;
+		}
+	}
+
+	return isIntersection;
+}
diff --git a/RayTracer/TriangleMesh.h b/RayTracer/TriangleMesh.h
new file mode 100644
index 0000000..bd87176
--- /dev/null
+++ b/RayTracer/TriangleMesh.h
@@ -0,0 +1,30 @@
+#pragma once
+
+#include <vector>
+#include <string>
+#include "assimp\Importer.hpp"
+#include "assimp\postprocess.h"
+#include "assimp\scene.h"
+
+#include "Triangle.h"
+
+class Material;
+
+class TriangleMesh : public Hitable
+{
+public:
+	TriangleMesh();
+	~TriangleMesh();
+	TriangleMesh(const std::string& path, Material* ptr_mat);
+
+	virtual bool hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const;
+
+private:
+
+	void LoadModel(const std::string& path);
+	void ProcessNode(aiNode* node, const aiScene* scene);
+	void ProcessMesh(aiMesh* mesh, const aiScene* scene);
+
+	std::vector<Triangle*> m_vecTriangles;
+	Material* m_ptrMaterial;
+};
diff --git a/RayTracer/Vector3.cpp b/RayTracer/Vector3.cpp
index c2b4460..4890eee 100644
--- a/RayTracer/Vector3.cpp
+++ b/RayTracer/Vector3.cpp
@@ -1,62 +1,100 @@
-
 #include "Vector3.h"
 
-///////////////////////////////////////////////////////////////////////////////////////////////////
-inline Vector3& Vector3::operator+=(const Vector3& v)
+Vector3 operator+(const Vector3 &lhs, const Vector3 &rhs)
+{
+	return Vector3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z);
+}
+
+Vector3 operator-(const Vector3 &lhs, const Vector3 &rhs)
+{
+	return Vector3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z);
+}
+
+Vector3 operator-(const Vector3 &vec)
+{
+	return Vector3(-vec.x, -vec.y, -vec.z);
+}
+
+Vector3 operator*(const Vector3 &lhs, const Vector3 &rhs)
+{
+	return Vector3(lhs.x * rhs.x, lhs.y * rhs.y, lhs.z * rhs.z);
+}
+
+Vector3 operator*(const float value, const Vector3 &vec)
+{
+	return Vector3(vec.x * value, vec.y * value, vec.z * value);
+}
+
+Vector3 operator*(const Vector3 &vec, const float value)
+{
+	return Vector3(vec.x * value, vec.y * value, vec.z * value);
+}
+
+Vector3 operator/(const Vector3 &vec, const float value)
+{
+	return Vector3(vec.x / value, vec.y / value, vec.z / value);
+}
+
+Vector3& Vector3::operator+=(const Vector3 &v2)
 {
-	x += v.x;
-	y += v.y;
-	z += v.z;
-	
+	e[0] += v2.e[0];
+	e[1] += v2.e[1];
+	e[2] += v2.e[2];
+
 	return *this;
 }
 
-///////////////////////////////////////////////////////////////////////////////////////////////////
-inline Vector3& Vector3::operator-=(const Vector3& v)
+Vector3& Vector3::operator-=(const Vector3 &v2)
 {
-	x -= v.x;
-	y -= v.y;
-	z -= v.z;
+	e[0] -= v2.e[0];
+	e[1] -= v2.e[1];
+	e[2] -= v2.e[2];
 
 	return *this;
 }
 
-///////////////////////////////////////////////////////////////////////////////////////////////////
-inline Vector3& Vector3::operator*=(const Vector3& v)
+Vector3& Vector3::operator*=(const Vector3 &v2)
 {
-	x *= v.x;
-	y *= v.y;
-	z *= v.z;
+	e[0] *= v2.e[0];
+	e[1] *= v2.e[1];
+	e[2] *= v2.e[2];
 
 	return *this;
 }
 
-///////////////////////////////////////////////////////////////////////////////////////////////////
-inline Vector3& Vector3::operator/=(const Vector3& v)
+Vector3& Vector3::operator/=(const Vector3 &v2)
 {
-	x /= v.x;
-	y /= v.y;
-	z /= v.z;
+	e[0] /= v2.e[0];
+	e[1] /= v2.e[1];
+	e[2] /= v2.e[2];
 
 	return *this;
 }
 
-///////////////////////////////////////////////////////////////////////////////////////////////////
-inline Vector3& Vector3::operator*=(const float v)
+Vector3& Vector3::operator*=(const float value)
 {
-	x *= v;
-	y *= v;
-	z *= v;
+	e[0] *= value;
+	e[1] *= value;
+	e[2] *= value;
 
 	return *this;
 }
 
-///////////////////////////////////////////////////////////////////////////////////////////////////
-inline Vector3& Vector3::operator/=(const float v)
+Vector3& Vector3::operator/=(const float value)
 {
-	x /= v;
-	y /= v;
-	z /= v;
+	e[0] /= value;
+	e[1] /= value;
+	e[2] /= value;
 
 	return *this;
 }
+
+float Vector3::Length() const
+{
+	return sqrtf((e[0] * e[0]) + (e[1] * e[1]) + (e[2] * e[2]));
+}
+
+float Vector3::LengthSquared() const
+{
+	return (e[0] * e[0]) + (e[1] * e[1]) + (e[2] * e[2]);
+}
\ No newline at end of file
diff --git a/RayTracer/Vector3.h b/RayTracer/Vector3.h
index 4b5e77a..542e615 100644
--- a/RayTracer/Vector3.h
+++ b/RayTracer/Vector3.h
@@ -1,98 +1,65 @@
 #pragma once
 
 #include <math.h>
-#include <stdlib.h>
-#include <iostream>
 
 class Vector3
 {
 public:
-	Vector3() {}
-	Vector3(float _x, float _y, float _z) { x = _x; y = _y; z = _z; }
-
-	inline const Vector3& operator+() const { return *this; }
-	inline Vector3 operator-() { return Vector3(-x, -y, -z); }
-
-	inline Vector3& operator+=(const Vector3& v2);
-	inline Vector3& operator-=(const Vector3& v2);
-	inline Vector3& operator*=(const Vector3& v2);
-	inline Vector3& operator/=(const Vector3& v2);
-	inline Vector3& operator*=(const float t);
-	inline Vector3& operator/=(const float t);
-
-	inline float length() const { return sqrt(x * x + y * y + z * z); }
-	inline float squaredLength() const { return(x*x + y * y + z * z); }
-	
-	float x, y, z;
+	union
+	{
+		struct { float x, y, z; };
+		struct { float r, g, b; };
+
+		float e[3];
+	};
+
+	Vector3(float e1, float e2, float e3) { e[0] = e1; e[1] = e2; e[2] = e3; }
+	Vector3() { e[0] = e[1] = e[2] = 0; };
+
+	inline float operator[](int i) const { return e[i]; }
+	friend Vector3 operator+(const Vector3 &lhs, const Vector3 &rhs);
+	friend Vector3 operator-(const Vector3 &lhs, const Vector3 &rhs);
+	friend Vector3 operator-(const Vector3 &vec);
+	friend Vector3 operator*(const Vector3 &lhs, const Vector3 &rhs);
+	friend Vector3 operator/(const Vector3 &lhs, const Vector3 &rhs);
+	friend Vector3 operator*(const Vector3 &vec, const float value);
+	friend Vector3 operator*(const float value, const Vector3 &vec);
+	friend Vector3 operator/(const Vector3 &vec, const float value);
+
+	Vector3& operator+=(const Vector3 &v2);
+	Vector3& operator-=(const Vector3 &v2);
+	Vector3& operator*=(const Vector3 &v2);
+	Vector3& operator/=(const Vector3 &v2);
+	Vector3& operator*=(const float value);
+	Vector3& operator/=(const float value);
+
+	float Length() const;
+	float LengthSquared() const;
 };
 
-///////////////////////////////////////////////////////////////////////////////////////////////////
-inline std::ostream& operator<<(std::ostream& os, const Vector3& v)
-{
-	os << v.x << " " << v.y << " " << v.z;
-	return os;
-}
-
-///////////////////////////////////////////////////////////////////////////////////////////////////
-inline std::istream& operator>>(std::istream &is, Vector3 &v) 
-{
-	is >> v.x >> v.y >> v.z;
-	return is;
-}
-
-///////////////////////////////////////////////////////////////////////////////////////////////////
-inline Vector3 operator+(const Vector3& v1, const Vector3& v2)
-{
-	return Vector3(v1.x + v2.x, v1.y + v2.y, v1.z + v2.z);
-}
-
-///////////////////////////////////////////////////////////////////////////////////////////////////
-inline Vector3 operator-(const Vector3& v1, const Vector3& v2)
+inline float Dot(const Vector3 &v1, const Vector3 &v2)
 {
-	return Vector3(v1.x - v2.x, v1.y - v2.y, v1.z - v2.z);
+	return v1.x * v2.x + v1.y * v2.y + v1.z * v2.z;
 }
 
-///////////////////////////////////////////////////////////////////////////////////////////////////
-inline Vector3 operator*(const Vector3& v1, const Vector3& v2)
+inline Vector3 Reflect(const Vector3 &v, const Vector3 &n)
 {
-	return Vector3(v1.x * v2.x, v1.y * v2.y, v1.z * v2.z);
+	return v - 2 * Dot(v, n) * n;
 }
 
-///////////////////////////////////////////////////////////////////////////////////////////////////
-inline Vector3 operator/(const Vector3& v1, const Vector3& v2)
+inline Vector3 UnitVector(const Vector3 &vec)
 {
-	return Vector3(v1.x / v2.x, v1.y / v2.y, v1.z / v2.z);
+	return vec / vec.Length();
 }
 
-///////////////////////////////////////////////////////////////////////////////////////////////////
-inline Vector3 operator*(float t, const Vector3& v2)
+inline Vector3 Cross(const Vector3 &v1, const Vector3 &v2)
 {
-	return Vector3(t * v2.x, t * v2.y, t * v2.z);
+	return Vector3((v1.y * v2.z - v1.z * v2.y),
+		(-(v1.x * v2.z - v1.z * v2.x)),
+		(v1.x * v2.y - v1.y * v2.x));
 }
 
-///////////////////////////////////////////////////////////////////////////////////////////////////
-inline Vector3 operator/(const Vector3& v2, float t)
+inline Vector3 Lerp(const Vector3 &v1, const Vector3 &v2, float t)
 {
-	return Vector3(v2.x / t, v2.y / t, v2.z / t);
+	return (1.0f - t) * v1 + (t * v2);
 }
-
-///////////////////////////////////////////////////////////////////////////////////////////////////
-inline float dot(const Vector3& v1, const Vector3& v2)
-{
-	return v1.x*v2.x + v1.y*v2.y + v1.z*v2.z;
-}
-
-///////////////////////////////////////////////////////////////////////////////////////////////////
-inline Vector3 cross(const Vector3& v1, const Vector3& v2)
-{
-	return Vector3((v1.y*v2.z - v1.z*v2.y), (-(v1.x*v2.z - v1.z*v2.x)), (v1.x*v2.y-v1.y*v2.x));
-}
-
-///////////////////////////////////////////////////////////////////////////////////////////////////
-inline Vector3 unit_vector(Vector3 v)
-{
-	return v / v.length();
-}
-
-
-
diff --git a/WindowsRayTracer.cpp b/WindowsRayTracer.cpp
index f139b26..29aa1e9 100644
--- a/WindowsRayTracer.cpp
+++ b/WindowsRayTracer.cpp
@@ -25,9 +25,9 @@
 #define C11_THREADS
 
 const int COLOR_CHANNELS = 3; // RGB
-const int gBackbufferWidth = 480;
-const int gBackbufferHeight = 270;
-const int nSamples = 10;
+const int gBackbufferWidth = 960;
+const int gBackbufferHeight = 540;
+const int nSamples = 1;
 
 unsigned long long int numRays = 0;
 
@@ -41,13 +41,8 @@ double TotalRenderTime = 0;
 #include "enkiTS\TaskScheduler.h"
 #endif
 
-Vector3 lookFrom(0, 5, 5);
-Vector3 lookAt(0, 0, 0);
-float dist_to_focus = 1.0f;	// set this to 1.0 & apertue to 0.0f to stop DOF effect!
-float aperture = 0.0f;
-
-
-Camera cam(lookFrom, lookAt, Vector3(0, 1, 0), 40, float(gBackbufferWidth) / float(gBackbufferHeight), aperture, dist_to_focus);
+//Camera* gCam = new Camera(Vector3(2,2,20), Vector3(0,0,0), Vector3(0, 1, 0), 60, float(gBackbufferWidth) / float(gBackbufferHeight), 0.0f, 1.0f);
+Camera* gCam = nullptr; // (pos, lookAt, Up, 45, float(gBackbufferWidth) / float(gBackbufferHeight), 0.0f, 1.0f);
 
 #define MAX_LOADSTRING 100
 
@@ -91,7 +86,7 @@ INT_PTR CALLBACK    About(HWND, UINT, WPARAM, LPARAM);
 //		{
 //			float choose_mat = Helper::GetRandom01();
 //			Vector3 center(a + 0.9f*Helper::GetRandom01(), 0.2, b + 0.9*Helper::GetRandom01());
-//			if ((center - Vector3(4, 0.2, 0)).length() > 0.9f)
+//			if ((center - Vector3(4, 0.2, 0)).Length() > 0.9f)
 //			{
 //				if (choose_mat < 0.8f)
 //				{
@@ -141,7 +136,7 @@ Vector3 TraceColor(const Ray& r, int depth)
 	}
 	else
 	{
-		Vector3 unit_direction = unit_vector(r.GetRayDirection());
+		Vector3 unit_direction = UnitVector(r.GetRayDirection());
 		float t = 0.5 * (unit_direction.y + 1.0f);
 		return Helper::LerpVector(Vector3(1.0f, 1.0f, 1.0f), Vector3(0.5f, 0.7f, 1.0f), t);
 	}
@@ -183,7 +178,7 @@ void ParallelTrace(std::mutex* threadMutex, int i)
 					float u = float(i + Helper::GetRandom01()) / float(backBufferWidth);
 					float v = float(j + Helper::GetRandom01()) / float(backBufferHeight);
 				
-					Ray r = cam.get_ray(u, v);
+					Ray r = gCam->get_ray(u, v);
 				
 					color = color + TraceColor(r, 0);
 				}
@@ -212,8 +207,12 @@ void ParallelTrace(std::mutex* threadMutex, int i)
 
 void Trace()
 {
+	if (gCam == nullptr)
+		return;
+
 #pragma region OLD_CODE
 	//HDC hdc = GetDC(hWnd);
+	//
 	//for (int j = gBackbufferHeight; j >= 0; j--)
 	//{
 	//	for (int i = 0; i <= gBackbufferWidth; i++)
@@ -225,7 +224,7 @@ void Trace()
 	//			float u = float(i + Helper::GetRandom01()) / float(gBackbufferWidth);
 	//			float v = float(j + Helper::GetRandom01()) / float(gBackbufferHeight);
 	//
-	//			Ray r = cam.get_ray(u, v);
+	//			Ray r = gCam->get_ray(u, v);
 	//
 	//			color = color + TraceColor(r, 0);
 	//		}
@@ -289,8 +288,9 @@ void Execute(HDC hdc)
 
 	const size_t len = 256;
 	wchar_t buffer[len] = {};
-	swprintf(buffer, L"Total Render Time : %0.2f seconds!", TotalRenderTime);
-	MessageBox(hWnd, buffer, L"Render Time!", MB_OKCANCEL);
+	swprintf(buffer, L"Windows Ray Tracer [Render Time : %0.2f seconds!]", TotalRenderTime);
+	SetWindowText(hWnd, buffer);
+	//MessageBox(hWnd, buffer, L"Render Time!", MB_OKCANCEL);
 
 	//printf("Render Time : %.2f seconds\n", time);
 
@@ -438,6 +438,9 @@ BOOL InitInstance(HINSTANCE hInstance, int nCmdShow)
       return FALSE;
    }
 
+   Camera::getInstance().InitCamera(gBackbufferWidth, gBackbufferHeight);
+   gCam = &Camera::getInstance();
+
    ShowWindow(hWnd, nCmdShow);
    UpdateWindow(hWnd);
 
```

