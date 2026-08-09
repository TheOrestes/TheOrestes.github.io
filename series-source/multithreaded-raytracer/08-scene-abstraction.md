# Post 8 — A Scene abstraction, and rethinking ownership

## `ef07d36` — 2018-09-03 _(master)_

> Added Scene class for common objects.

```diff
diff --git a/RayTracer/Helper.h b/RayTracer/Helper.h
index 66e5d1b..7de53bf 100644
--- a/RayTracer/Helper.h
+++ b/RayTracer/Helper.h
@@ -6,17 +6,17 @@ const float PI = 3.14159265358f;
 
 namespace Helper
 {
-	Vector3 LerpVector(const Vector3& vec1, const Vector3& vec2, float t)
+	inline Vector3 LerpVector(const Vector3& vec1, const Vector3& vec2, float t)
 	{
 		return (1.0f - t) * vec1 + t * vec2;
 	}
 
-	double GetRandom01()
+	inline double GetRandom01()
 	{
 		return ((double)rand() / (RAND_MAX + 1));
 	}
 
-	Vector3 GetRandomInUnitDisk()
+	inline Vector3 GetRandomInUnitDisk()
 	{
 		Vector3 p;
 		do
@@ -27,7 +27,7 @@ namespace Helper
 		return p;
 	}
 
-	Vector3 RandomInUnitSphere()
+	inline Vector3 RandomInUnitSphere()
 	{
 		Vector3 P;
 
@@ -39,12 +39,12 @@ namespace Helper
 		return P;
 	}
 
-	Vector3 Reflect(const Vector3& v, const Vector3& n)
+	inline Vector3 Reflect(const Vector3& v, const Vector3& n)
 	{
 		return v - 2 * dot(v, n) * n;
 	}
 
-	bool Refract(const Vector3& v, const Vector3& n, float ni_over_nt, Vector3& refracted)
+	inline bool Refract(const Vector3& v, const Vector3& n, float ni_over_nt, Vector3& refracted)
 	{
 		Vector3 unit_v = unit_vector(v);
 		float NdotV = dot(unit_v, n);
@@ -59,7 +59,7 @@ namespace Helper
 			return false;
 	}
 
-	float schlick(float cosine, float ref_idx)
+	inline float schlick(float cosine, float ref_idx)
 	{
 		float r0 = (1 - ref_idx) / (1 + ref_idx);
 		r0 = r0 * r0;
diff --git a/RayTracer/Lambertian.cpp b/RayTracer/Lambertian.cpp
new file mode 100644
index 0000000..852a459
--- /dev/null
+++ b/RayTracer/Lambertian.cpp
@@ -0,0 +1,11 @@
+
+#include "Lambertian.h"
+#include "Helper.h"
+
+bool Lambertian::Scatter(const Ray& r_in, const HitRecord& rec, Vector3& attenuation, Ray& scatterd) const
+{
+	Vector3 target = rec.P + rec.N + Helper::RandomInUnitSphere();
+	scatterd = Ray(rec.P, target - rec.P);
+	attenuation = Albedo;
+	return true;
+}
\ No newline at end of file
diff --git a/RayTracer/Lambertian.h b/RayTracer/Lambertian.h
index 518dc38..9a17851 100644
--- a/RayTracer/Lambertian.h
+++ b/RayTracer/Lambertian.h
@@ -3,20 +3,13 @@
 #include "Ray.h"
 #include "Hitable.h"
 #include "Material.h"
-#include "Helper.h"
 
 class Lambertian : public Material
 {
 public:
 	Lambertian(const Vector3& _albedo) : Albedo(_albedo) {}
 
-	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, Vector3& attenuation, Ray& scatterd) const
-	{
-		Vector3 target = rec.P + rec.N + Helper::RandomInUnitSphere();
-		scatterd = Ray(rec.P, target - rec.P);
-		attenuation = Albedo;
-		return true;
-	}
+	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, Vector3& attenuation, Ray& scatterd) const;
 
 private:
 	Vector3 Albedo;
diff --git a/RayTracer/Metal.cpp b/RayTracer/Metal.cpp
new file mode 100644
index 0000000..f75bf1a
--- /dev/null
+++ b/RayTracer/Metal.cpp
@@ -0,0 +1,11 @@
+
+#include "Metal.h"
+#include "Helper.h"
+
+bool Metal::Scatter(const Ray& r_in, const HitRecord& rec, Vector3& attenuation, Ray& scatterd) const
+{
+	Vector3 target = Helper::Reflect(unit_vector(r_in.GetRayDirection()), rec.N);
+	scatterd = Ray(rec.P, target + fuzz * Helper::RandomInUnitSphere());
+	attenuation = Albedo;
+	return (dot(scatterd.GetRayDirection(), rec.N) > 0);
+}
\ No newline at end of file
diff --git a/RayTracer/Metal.h b/RayTracer/Metal.h
index 496181f..e4a85e7 100644
--- a/RayTracer/Metal.h
+++ b/RayTracer/Metal.h
@@ -3,7 +3,6 @@
 #include "Ray.h"
 #include "Hitable.h"
 #include "Material.h"
-#include "Helper.h"
 
 class Metal : public Material
 {
@@ -16,13 +15,7 @@ public:
 			fuzz = 1;
 	}
 
-	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, Vector3& attenuation, Ray& scatterd) const
-	{
-		Vector3 target = Helper::Reflect(unit_vector(r_in.GetRayDirection()), rec.N);
-		scatterd = Ray(rec.P, target + fuzz * Helper::RandomInUnitSphere());
-		attenuation = Albedo;
-		return (dot(scatterd.GetRayDirection(), rec.N) > 0);
-	}
+	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, Vector3& attenuation, Ray& scatterd) const;
 
 private:
 	Vector3 Albedo;
diff --git a/RayTracer/Scene.cpp b/RayTracer/Scene.cpp
new file mode 100644
index 0000000..b33c05c
--- /dev/null
+++ b/RayTracer/Scene.cpp
@@ -0,0 +1,59 @@
+
+#include "Scene.h"
+#include "Sphere.h"
+#include "Lambertian.h"
+#include "Metal.h"
+#include "Transparent.h"
+#include "Triangle.h"
+
+Scene::Scene()
+{
+	vecHitables.clear();
+	InitScene();
+}
+
+void Scene::InitScene()
+{
+	Vector3 center0(0.0f, 0, -3);
+	Vector3 albedo0(1, 0, 0);
+	Material* pMatSphere0 = new Metal(albedo0, 0.2f);
+	Sphere* pSphere0 = new Sphere(center0, 0.5, pMatSphere0);
+
+	// Sphere2
+	Vector3 center1(0, -100.5, 0);
+	Vector3 albedo1(0.2, 0.2, 0.2);
+	Material* pMatSphere1 = new Lambertian(albedo1);
+	Sphere* pSphere1 = new Sphere(center1, 100.0f, pMatSphere1);
+
+	Sphere* pSphere2 = new Sphere(Vector3(0, 0, 2), 0.5, new Lambertian(Vector3(1.0f, 0.0f, 0.0f)));
+	Sphere* pSphere3 = new Sphere(Vector3(-1.05f, 0, 0), 0.5, new Metal(Vector3(1.0, 0.2, 0.0), 0));
+	Sphere* pSphere4 = new Sphere(Vector3(1.05f, 0, 0), 0.5, new Transparent(1.5f));
+	Triangle* pTriangle0  = new Triangle(Vector3(-2.0f, 0.0f, -1.0f), Vector3(2.0f, 0.0f, -1.0f), Vector3(0.0f, 2.0f, -1.0f), new Metal(Vector3(0.0, 1.0f, 0.0f), 0.1f));
+
+	vecHitables.push_back(pSphere0);
+	vecHitables.push_back(pSphere1);
+	vecHitables.push_back(pSphere2);
+	vecHitables.push_back(pSphere3);
+	vecHitables.push_back(pSphere4);
+	vecHitables.push_back(pTriangle0);
+}
+
+bool Scene::Trace(const Ray& r, float tmin, float tmax, HitRecord& rec)
+{
+	bool hit_anything = false;
+	HitRecord temp_rec;
+	double closest_so_far = tmax;
+
+	for (int i = 0; i < vecHitables.size(); i++)
+	{
+		if (vecHitables[i]->hit(r, tmin, closest_so_far, temp_rec))
+		{
+			hit_anything = true;
+			closest_so_far = temp_rec.t;
+			rec = temp_rec;
+		}
+	}
+
+	return hit_anything;
+}
+
diff --git a/RayTracer/Scene.h b/RayTracer/Scene.h
new file mode 100644
index 0000000..7189699
--- /dev/null
+++ b/RayTracer/Scene.h
@@ -0,0 +1,23 @@
+#pragma once
+
+#include <vector>
+#include "Hitable.h"
+
+class Scene
+{
+public:
+	
+	static Scene& getInstance()
+	{
+		static Scene instance;
+		return instance;
+	}
+
+	void InitScene();
+	bool Trace(const Ray& r, float tmin, float tmax, HitRecord& rec);
+
+private:
+	Scene();
+
+	std::vector<Hitable*> vecHitables;
+};
\ No newline at end of file
diff --git a/RayTracer/Sphere.cpp b/RayTracer/Sphere.cpp
new file mode 100644
index 0000000..f606e35
--- /dev/null
+++ b/RayTracer/Sphere.cpp
@@ -0,0 +1,39 @@
+
+#include "Sphere.h"
+
+/////////////////////////////////////////////////////////////////////////////////////////
+bool Sphere::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
+{
+	Vector3 oc = r.GetRayOrigin() - center;
+	float a = dot(r.GetRayDirection(), r.GetRayDirection());
+	float b = 2.0f * dot(oc, r.GetRayDirection());
+	float c = dot(oc, oc) - radius * radius;
+	float discriminant = b * b - 4 * a* c;
+
+	float t;
+
+	if (discriminant > 0)
+	{
+		t = (-b - sqrt(discriminant)) / (2.0 * a);
+		if (t < tmax && t > tmin)
+		{
+			rec.t = t;
+			rec.P = r.GetPointAt(t);
+			rec.N = (rec.P - center) / radius;
+			rec.mat_ptr = mat_ptr;
+			return true;
+		}
+
+		t = (-b + sqrt(discriminant)) / (2.0 * a);
+		if (t < tmax && t > tmin)
+		{
+			rec.t = t;
+			rec.P = r.GetPointAt(t);
+			rec.N = (rec.P - center) / radius;
+			rec.mat_ptr = mat_ptr;
+			return true;
+		}
+	}
+
+	return false;
+}
\ No newline at end of file
diff --git a/RayTracer/Sphere.h b/RayTracer/Sphere.h
index e9ef16a..c177895 100644
--- a/RayTracer/Sphere.h
+++ b/RayTracer/Sphere.h
@@ -21,39 +21,3 @@ private:
 	Material* mat_ptr;
 };
 
-/////////////////////////////////////////////////////////////////////////////////////////
-bool Sphere::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
-{
-	Vector3 oc = r.GetRayOrigin() - center;
-	float a = dot(r.GetRayDirection(), r.GetRayDirection());
-	float b = 2.0f * dot(oc, r.GetRayDirection());
-	float c = dot(oc, oc) - radius * radius;
-	float discriminant = b * b - 4 * a* c;
-
-	float t;
-
-	if (discriminant > 0)
-	{
-		t = (-b - sqrt(discriminant)) / (2.0 * a);
-		if (t < tmax && t > tmin)
-		{
-			rec.t = t;
-			rec.P = r.GetPointAt(t);
-			rec.N = (rec.P - center) / radius;
-			rec.mat_ptr = mat_ptr;
-			return true;
-		}
-
-		t = (-b + sqrt(discriminant)) / (2.0 * a);
-		if (t < tmax && t > tmin)
-		{
-			rec.t = t;
-			rec.P = r.GetPointAt(t);
-			rec.N = (rec.P - center) / radius;
-			rec.mat_ptr = mat_ptr;
-			return true;
-		}
-	}
-
-	return false;
-}
\ No newline at end of file
diff --git a/RayTracer/Triangle.cpp b/RayTracer/Triangle.cpp
new file mode 100644
index 0000000..7c5aa41
--- /dev/null
+++ b/RayTracer/Triangle.cpp
@@ -0,0 +1,79 @@
+
+#include "Triangle.h"
+
+/////////////////////////////////////////////////////////////////////////////////////////
+bool Triangle::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
+{
+	// Compute Plane Normal
+	Vector3 edge0 = V1 - V0;
+	Vector3 edge1 = V2 - V1;
+	Vector3 edge2 = V0 - V2;
+
+	Vector3 N = unit_vector(cross(edge0, edge1));
+
+	// Check if ray & plane are parallel
+	float NdotRayDirection = dot(N, r.GetRayDirection());
+	if (fabs(NdotRayDirection) < 0.001f)
+		return false;
+
+	// Compute plane distance from origin
+	float d = dot(V0, N);
+
+	// Compute t at which intersection happens!
+	float t = (d - dot(N, r.GetRayOrigin())) / NdotRayDirection;
+
+	if (t < tmin || t > tmax)
+		return false;
+
+	// Compute intersection point
+	Vector3 P = r.GetRayOrigin() + (t * r.GetRayDirection());
+
+	// Perform tests if this P is inside triangle or outside
+	Vector3 C;
+	Vector3 P0 = P - V0;
+	Vector3 P1 = P - V1;
+	Vector3 P2 = P - V2;
+
+	if (dot(N, cross(edge0, P0)) >= 0 && dot(N, cross(edge1, P1)) >= 0 && dot(N, cross(edge2, P2)) >= 0)
+	{
+		// Record hit data!!!
+		rec.t = t;
+		rec.P = P;
+		rec.N = N;
+		rec.mat_ptr = mat_ptr;
+
+		return true;
+	}
+	else
+		return false;
+
+	//auto edge0 = V1 - V0;
+	//auto edge1 = V2 - V1;
+	//auto normal = unit_vector(cross(edge0, edge1));
+	//auto planeOffset = dot(V0, normal);
+	//auto p0 = r.GetPointAt(tmin);
+	//auto p1 = r.GetPointAt(tmax);
+	//auto offset0 = dot(p0, normal);
+	//auto offset1 = dot(p1, normal);
+	//if ((offset0 - planeOffset)*(offset1 - planeOffset) <= 0.f) // Line segment intersects the plane of the triangle
+	//{
+	//	float t = tmin + (tmax - tmin)*(planeOffset - offset0) / (offset1 - offset0);
+	//	auto p = r.GetPointAt(t);
+	//	auto c0 = cross(edge0, p - V0);
+	//	auto c1 = cross(edge1, p - V1);
+	//	if (dot(c0, c1) >= 0.f)
+	//	{
+	//		auto edge2 = V0 - V2;
+	//		auto c2 = cross(edge2, p - V2);
+	//		if (dot(c1, c2) >= 0.f)
+	//		{
+	//			rec.t = t;
+	//			rec.P = p;
+	//			rec.N = normal;
+	//			rec.mat_ptr = mat_ptr;
+	//			return true;
+	//		}
+	//	}
+	//}
+	//return false;
+}
\ No newline at end of file
diff --git a/RayTracer/Triangle.h b/RayTracer/Triangle.h
index d882297..bfceb91 100644
--- a/RayTracer/Triangle.h
+++ b/RayTracer/Triangle.h
@@ -24,80 +24,3 @@ private:
 	Vector3 V2;
 	Material* mat_ptr;
 };
-
-/////////////////////////////////////////////////////////////////////////////////////////
-bool Triangle::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
-{
-	// Compute Plane Normal
-	Vector3 edge0 = V1 - V0;
-	Vector3 edge1 = V2 - V1;
-	Vector3 edge2 = V0 - V2;
-	
-	Vector3 N = unit_vector(cross(edge0, edge1));
-	
-	// Check if ray & plane are parallel
-	float NdotRayDirection = dot(N, r.GetRayDirection());
-	if (fabs(NdotRayDirection) < 0.001f)
-		return false;
-	
-	// Compute plane distance from origin
-	float d = dot(V0, N);
-	
-	// Compute t at which intersection happens!
-	float t = (d - dot(N, r.GetRayOrigin())) / NdotRayDirection;
-
-	if (t < tmin || t > tmax)
-		return false;
-
-	// Compute intersection point
-	Vector3 P = r.GetRayOrigin() + (t * r.GetRayDirection());
-	
-	// Perform tests if this P is inside triangle or outside
-	Vector3 C;
-	Vector3 P0 = P - V0;	
-	Vector3 P1 = P - V1;
-	Vector3 P2 = P - V2;
-	
-	if (dot(N, cross(edge0, P0)) >= 0 && dot(N, cross(edge1, P1)) >= 0 && dot(N, cross(edge2, P2)) >= 0)
-	{
-		// Record hit data!!!
-		rec.t = t;
-		rec.P = P;
-		rec.N = N;
-		rec.mat_ptr = mat_ptr;
-	
-		return true;
-	}
-	else
-		return false;
-
-	//auto edge0 = V1 - V0;
-	//auto edge1 = V2 - V1;
-	//auto normal = unit_vector(cross(edge0, edge1));
-	//auto planeOffset = dot(V0, normal);
-	//auto p0 = r.GetPointAt(tmin);
-	//auto p1 = r.GetPointAt(tmax);
-	//auto offset0 = dot(p0, normal);
-	//auto offset1 = dot(p1, normal);
-	//if ((offset0 - planeOffset)*(offset1 - planeOffset) <= 0.f) // Line segment intersects the plane of the triangle
-	//{
-	//	float t = tmin + (tmax - tmin)*(planeOffset - offset0) / (offset1 - offset0);
-	//	auto p = r.GetPointAt(t);
-	//	auto c0 = cross(edge0, p - V0);
-	//	auto c1 = cross(edge1, p - V1);
-	//	if (dot(c0, c1) >= 0.f)
-	//	{
-	//		auto edge2 = V0 - V2;
-	//		auto c2 = cross(edge2, p - V2);
-	//		if (dot(c1, c2) >= 0.f)
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
-}
\ No newline at end of file
diff --git a/WindowsRayTracer.cpp b/WindowsRayTracer.cpp
index c72f8b3..f139b26 100644
--- a/WindowsRayTracer.cpp
+++ b/WindowsRayTracer.cpp
@@ -14,7 +14,7 @@
 #include "./RayTracer/Ray.h"
 #include "./RayTracer/Sphere.h"
 #include "./RayTracer/Triangle.h"
-#include "./RayTracer/HitableList.h"
+#include "./RayTracer/Scene.h"
 #include "./RayTracer/Camera.h"
 #include "./RayTracer/Helper.h"
 #include "./RayTracer/Material.h"
@@ -25,9 +25,9 @@
 #define C11_THREADS
 
 const int COLOR_CHANNELS = 3; // RGB
-const int gBackbufferWidth = 960;
-const int gBackbufferHeight = 540;
-const int nSamples = 100;
+const int gBackbufferWidth = 480;
+const int gBackbufferHeight = 270;
+const int nSamples = 10;
 
 unsigned long long int numRays = 0;
 
@@ -66,67 +66,66 @@ INT_PTR CALLBACK    About(HWND, UINT, WPARAM, LPARAM);
 /////////////////////////////////////////////////////////////////////////////////////////////////////////////
 #pragma region RayTracer
 
-Hitable* BasicTestScene()
-{
-	Hitable** list = new Hitable*[6];
-	list[0] = new Sphere(Vector3(1.05f, 0, 0), 0.5, new Metal(Vector3(0.5, 0.2, 0.1), 0.5));
-	list[1] = new Sphere(Vector3(0, -100.5, 0), 100, new Lambertian(Vector3(0.2, 0.2, 0.2)));
-	list[2] = new Sphere(Vector3(0, 0, 2), 0.5, new Lambertian(Vector3(1.0f, 0.0f, 0.0f)));
-	list[3] = new Sphere(Vector3(-1.05f, 0, 0), 0.5, new Metal(Vector3(1.0, 0.2, 0.0), 0));
-	list[4] = new Sphere(Vector3(0.0f, 0, -3), 0.5, new Lambertian(Vector3(1.0, 1.0, 0.0)));
-	list[5] = new Triangle(Vector3(-2.0f, 0.0f, -1.0f), Vector3(2.0f, 0.0f, -1.0f), Vector3(0.0f, 2.0f, -1.0f), new Lambertian(Vector3(0.0f, 1.0f, 0.0f)));
-
-	return new HitableList(list, 6);
-}
-
-Hitable* random_scene()
-{
-	int n = 500;
-	Hitable** list = new Hitable*[n + 1];
-	list[0] = new Sphere(Vector3(0, -1000, 0), 1000, new Lambertian(Vector3(0.5, 0.5, 0.5)));
-	int i = 1;
-	for (int a = -11; a < 11; a++)
-	{
-		for (int b = -11; b < 11; b++)
-		{
-			float choose_mat = Helper::GetRandom01();
-			Vector3 center(a + 0.9f*Helper::GetRandom01(), 0.2, b + 0.9*Helper::GetRandom01());
-			if ((center - Vector3(4, 0.2, 0)).length() > 0.9f)
-			{
-				if (choose_mat < 0.8f)
-				{
-					// diffuse
-					list[i++] = new Sphere(center, 0.2f, new Lambertian(Vector3(Helper::GetRandom01()*Helper::GetRandom01(), Helper::GetRandom01()*Helper::GetRandom01(), Helper::GetRandom01()*Helper::GetRandom01())));
-				}
-				else if (choose_mat < 0.95)
-				{
-					// Metal
-					list[i++] = new Sphere(center, 0.2f, new Metal(Vector3(0.5f*(1 + Helper::GetRandom01()), 0.5f*(1 + Helper::GetRandom01()), 0.5f*(1 + Helper::GetRandom01())), Helper::GetRandom01()));
-				}
-				else
-				{
-					// glass
-					list[i++] = new Sphere(center, 0.2f, new Transparent(1.5f));
-				}
-			}
-		}
-	}
-
-	list[i++] = new Sphere(Vector3(0, 1, 0), 1.0f, new Transparent(1.5f));
-	list[i++] = new Sphere(Vector3(-4, 1, 0), 1.0f, new Lambertian(Vector3(0.4f, 0.2f, 0.1f)));
-	list[i++] = new Sphere(Vector3(4, 1, 0), 1.0f, new Metal(Vector3(0.7f, 0.6f, 0.5f), 0.0f));
-
-	return new HitableList(list, i);
-}
-
-Hitable* world = BasicTestScene();
-
+//Hitable* BasicTestScene()
+//{
+//	Hitable** list = new Hitable*[6];
+//	list[0] = new Sphere(Vector3(1.05f, 0, 0), 0.5, new Metal(Vector3(0.5, 0.2, 0.1), 0.5));
+//	list[1] = new Sphere(Vector3(0, -100.5, 0), 100, new Lambertian(Vector3(0.2, 0.2, 0.2)));
+//	list[2] = new Sphere(Vector3(0, 0, 2), 0.5, new Lambertian(Vector3(1.0f, 0.0f, 0.0f)));
+//	list[3] = new Sphere(Vector3(-1.05f, 0, 0), 0.5, new Metal(Vector3(1.0, 0.2, 0.0), 0));
+//	list[4] = new Sphere(Vector3(0.0f, 0, -3), 0.5, new Lambertian(Vector3(1.0, 1.0, 0.0)));
+//	list[5] = new Triangle(Vector3(-2.0f, 0.0f, -1.0f), Vector3(2.0f, 0.0f, -1.0f), Vector3(0.0f, 2.0f, -1.0f), new Lambertian(Vector3(0.0f, 1.0f, 0.0f)));
+//
+//	return new HitableList(list, 6);
+//}
+//
+//Hitable* random_scene()
+//{
+//	int n = 500;
+//	Hitable** list = new Hitable*[n + 1];
+//	list[0] = new Sphere(Vector3(0, -1000, 0), 1000, new Lambertian(Vector3(0.5, 0.5, 0.5)));
+//	int i = 1;
+//	for (int a = -11; a < 11; a++)
+//	{
+//		for (int b = -11; b < 11; b++)
+//		{
+//			float choose_mat = Helper::GetRandom01();
+//			Vector3 center(a + 0.9f*Helper::GetRandom01(), 0.2, b + 0.9*Helper::GetRandom01());
+//			if ((center - Vector3(4, 0.2, 0)).length() > 0.9f)
+//			{
+//				if (choose_mat < 0.8f)
+//				{
+//					// diffuse
+//					list[i++] = new Sphere(center, 0.2f, new Lambertian(Vector3(Helper::GetRandom01()*Helper::GetRandom01(), Helper::GetRandom01()*Helper::GetRandom01(), Helper::GetRandom01()*Helper::GetRandom01())));
+//				}
+//				else if (choose_mat < 0.95)
+//				{
+//					// Metal
+//					list[i++] = new Sphere(center, 0.2f, new Metal(Vector3(0.5f*(1 + Helper::GetRandom01()), 0.5f*(1 + Helper::GetRandom01()), 0.5f*(1 + Helper::GetRandom01())), Helper::GetRandom01()));
+//				}
+//				else
+//				{
+//					// glass
+//					list[i++] = new Sphere(center, 0.2f, new Transparent(1.5f));
+//				}
+//			}
+//		}
+//	}
+//
+//	list[i++] = new Sphere(Vector3(0, 1, 0), 1.0f, new Transparent(1.5f));
+//	list[i++] = new Sphere(Vector3(-4, 1, 0), 1.0f, new Lambertian(Vector3(0.4f, 0.2f, 0.1f)));
+//	list[i++] = new Sphere(Vector3(4, 1, 0), 1.0f, new Metal(Vector3(0.7f, 0.6f, 0.5f), 0.0f));
+//
+//	return new HitableList(list, i);
+//}
+//
+//Hitable* world = BasicTestScene();
 Vector3 TraceColor(const Ray& r, int depth)
 {
 	HitRecord rec;
 
 	++numRays;
-	if (world->hit(r, 0.001f, FLT_MAX, rec))
+	if (Scene::getInstance().Trace(r, 0.001f, FLT_MAX, rec))
 	{
 		Ray scatteredRay;
 		Vector3 attenuation;
@@ -328,7 +327,7 @@ int APIENTRY wWinMain(_In_ HINSTANCE hInstance,
 
     HACCEL hAccelTable = LoadAccelerators(hInstance, MAKEINTRESOURCE(IDC_WINDOWSRAYTRACER));
 
-    MSG msg;
+    MSG msg;	
 
     // Main message loop:
     while (GetMessage(&msg, nullptr, 0, 0))
```

## `befe602` — 2018-09-22 _(master)_

> Added Scene class.

```diff
diff --git a/RayTracer/Scene.cpp b/RayTracer/Scene.cpp
index b33c05c..9a1d498 100644
--- a/RayTracer/Scene.cpp
+++ b/RayTracer/Scene.cpp
@@ -9,7 +9,8 @@
 Scene::Scene()
 {
 	vecHitables.clear();
-	InitScene();
+	//InitScene();
+	InitRandomScene();
 }
 
 void Scene::InitScene()
@@ -38,6 +39,53 @@ void Scene::InitScene()
 	vecHitables.push_back(pTriangle0);
 }
 
+void Scene::InitRandomScene()
+{
+	Sphere* pSphere0 = new Sphere(Vector3(0, -1000, 0), 1000, new Lambertian(Vector3(0.5, 0.5, 0.5)));
+	vecHitables.push_back(pSphere0);
+
+	int i = 1;
+
+	for (int a = -11; a < 11; a++)
+	{
+		for (int b = -11; b < 11; b++)
+		{
+			float choose_mat = Helper::GetRandom01();
+
+			Vector3 center(a + 0.9f * Helper::GetRandom01(), 0.2, b + 0.9 * Helper::GetRandom01());
+			if ((center - Vector3(4, 0.2, 0)).length() > 0.9f)
+			{
+				if (choose_mat < 0.8f)
+				{
+					// diffuse
+					Sphere* temp = new Sphere(center, 0.2f, new Lambertian(Vector3(Helper::GetRandom01() * Helper::GetRandom01(), Helper::GetRandom01() * Helper::GetRandom01(), Helper::GetRandom01() * Helper::GetRandom01())));
+					vecHitables.push_back(temp);
+				}
+				else if (choose_mat < 0.95f)
+				{
+					// Metal
+					Sphere* temp = new Sphere(center, 0.2f, new Metal(Vector3(0.5f*(1 + Helper::GetRandom01()), 0.5f*(1 + Helper::GetRandom01()), 0.5f*(1 + Helper::GetRandom01())), Helper::GetRandom01()));
+					vecHitables.push_back(temp);
+				}
+				else
+				{
+					// glass
+					Sphere* temp = new Sphere(center, 0.2f, new Transparent(1.5f));
+					vecHitables.push_back(temp);
+				}
+			}
+		}
+	}
+
+	Sphere* pSphere1 = new Sphere(Vector3(0, 1, 0), 1.0f, new Transparent(1.5f));
+	Sphere* pSphere2 = new Sphere(Vector3(-4, 1, 0), 1.0f, new Lambertian(Vector3(0.4f, 0.2f, 0.1f)));
+	Sphere* pSphere3 = new Sphere(Vector3(4, 1, 0), 1.0f, new Metal(Vector3(0.7f, 0.6f, 0.5f), 0.0f));
+
+	vecHitables.push_back(pSphere1);
+	vecHitables.push_back(pSphere2);
+	vecHitables.push_back(pSphere3);
+}
+
 bool Scene::Trace(const Ray& r, float tmin, float tmax, HitRecord& rec)
 {
 	bool hit_anything = false;
diff --git a/RayTracer/Scene.h b/RayTracer/Scene.h
index 7189699..b36c02c 100644
--- a/RayTracer/Scene.h
+++ b/RayTracer/Scene.h
@@ -13,11 +13,13 @@ public:
 		return instance;
 	}
 
-	void InitScene();
+	
 	bool Trace(const Ray& r, float tmin, float tmax, HitRecord& rec);
 
 private:
 	Scene();
+	void InitScene();
+	void InitRandomScene();
 
 	std::vector<Hitable*> vecHitables;
 };
\ No newline at end of file
```

## `01bee25` — 2019-05-01 _(master)_

> - Minor code management - Camera is part of Scene instead of singleton - Scene is part of Application instead of singleton - Added Cornell box scene

```diff
diff --git a/.gitignore b/.gitignore
index 2e8af79..39204bf 100644
--- a/.gitignore
+++ b/.gitignore
@@ -42,3 +42,4 @@
 /carRender.jpg
 /carReflection.jpg
 *.hdr
+*.jpg
diff --git a/Application.cpp b/Application.cpp
index 80433c1..73b59f1 100644
--- a/Application.cpp
+++ b/Application.cpp
@@ -8,8 +8,8 @@
 #include "RayTracer/Hitable.h"
 #include "RayTracer/Material.h"
 #include "RayTracer/Scene.h"
-#include "RayTracer/Helper.h"
 #include "RayTracer/Camera.h"
+#include "RayTracer/Helper.h"
 #include "Profiler.h"
 #include "Application.h"
 
@@ -19,10 +19,11 @@
 ///////////////////////////////////////////////////////////////////////////////////////////////////
 Application::Application()
 {
-	m_iBackbufferWidth = 960;
-	m_iBackbufferHeight = 540;
-	m_iNumSamples = 10;
+	m_iBackbufferWidth = 480;
+	m_iBackbufferHeight = 270;
+	m_iNumSamples = 50;
 	m_dTotalRenderTime = 0;
+	m_dDenoiserTime = 0;
 	m_bThreaded = false;
 
 	m_iRayCount = 0;
@@ -38,7 +39,11 @@ Application::Application()
 ///////////////////////////////////////////////////////////////////////////////////////////////////
 Application::~Application()
 {
-	delete m_pCamera;
+	if (m_pScene)
+	{
+		delete m_pScene;
+		m_pScene = nullptr;
+	}
 }
 
 ///////////////////////////////////////////////////////////////////////////////////////////////////
@@ -49,8 +54,8 @@ void Application::Initialize(HWND hwnd, bool _threaded)
 
 	_threaded ? m_iMaxThreads = std::thread::hardware_concurrency() : 0;
 
-	m_pCamera = &(Camera::getInstance());
-	m_pCamera->InitCamera(m_iBackbufferWidth, m_iBackbufferHeight);
+	m_pScene = new Scene();
+	m_pScene->InitCornellScene(m_iBackbufferWidth, m_iBackbufferHeight);
 
 	// Create Open Image Denoise Device
 	m_oidnDevice = oidn::newDevice();
@@ -135,47 +140,58 @@ void Application::DenoiseImage()
 	float* outData   = (float*)malloc(3 * m_iBackbufferWidth * m_iBackbufferHeight * sizeof(float));
 	if (pixelData && outData)
 	{
-		memset(pixelData, 0, sizeof(3 * m_iBackbufferWidth * m_iBackbufferHeight * sizeof(float)));
-		memset(outData,   0, sizeof(3 * m_iBackbufferWidth * m_iBackbufferHeight * sizeof(float)));
-	}
-
-	// Below logic can be improved!!
-	float* origData = pixelData;
-	for (int j = 0; j < m_iBackbufferHeight; j++)
-	{
-		for (int i = 0; i < m_iBackbufferWidth; i++)
+		// Below logic can be improved!!
+		float* origData = pixelData;
+		for (int j = 0; j < m_iBackbufferHeight; j++)
 		{
-			COLORREF refColor = GetPixel(hdc, i, j);
-			float rVal = (float)GetRValue(refColor);
-			float gVal = (float)GetGValue(refColor);
-			float bVal = (float)GetBValue(refColor);
-
-			*pixelData = rVal / 255.0f; ++pixelData;
-			*pixelData = gVal / 255.0f; ++pixelData;
-			*pixelData = bVal / 255.0f; ++pixelData;
+			for (int i = 0; i < m_iBackbufferWidth; i++)
+			{
+				COLORREF refColor = GetPixel(hdc, i, j);
+				float rVal = (float)GetRValue(refColor);
+				float gVal = (float)GetGValue(refColor);
+				float bVal = (float)GetBValue(refColor);
+
+				*pixelData = rVal / 255.0f; ++pixelData;
+				*pixelData = gVal / 255.0f; ++pixelData;
+				*pixelData = bVal / 255.0f; ++pixelData;
+			}
 		}
-	}
 
-	// Write down orginal image in HDR format
-	stbi_write_hdr("debug.hdr", m_iBackbufferWidth, m_iBackbufferHeight, 3, origData);
-
-	// Create a denoising filter
- 	m_oidnFilter = m_oidnDevice.newFilter("RT");
-	m_oidnFilter.setImage("color", origData, oidn::Format::Float3, m_iBackbufferWidth, m_iBackbufferHeight);
-	m_oidnFilter.setImage("output", outData, oidn::Format::Float3, m_iBackbufferWidth, m_iBackbufferHeight);
-	m_oidnFilter.set("hdr", true);
-	m_oidnFilter.commit();
-	m_oidnFilter.execute();
+#if defined _DEBUG
+		// Write down orginal image in HDR format
+		stbi_write_hdr("debug.hdr", m_iBackbufferWidth, m_iBackbufferHeight, 3, origData);
+#endif
+
+		// Create a denoising filter
+		m_oidnFilter = m_oidnDevice.newFilter("RT");
+		m_oidnFilter.setImage("color", origData, oidn::Format::Float3, m_iBackbufferWidth, m_iBackbufferHeight);
+		m_oidnFilter.setImage("output", outData, oidn::Format::Float3, m_iBackbufferWidth, m_iBackbufferHeight);
+		m_oidnFilter.set("hdr", true);
+		m_oidnFilter.set("numThreads", m_iMaxThreads);
+		m_oidnFilter.set("setAffinity", true);
+		m_oidnFilter.commit();
+
+
+		const clock_t begin_time = clock();
+		
+		m_oidnFilter.execute();
+
+		const clock_t end_time = clock();
+		m_dDenoiserTime = (end_time - begin_time) / (float)CLOCKS_PER_SEC;
+		Profiler::getInstance().WriteToProfiler("Denoiser Time: ", m_dDenoiserTime);
+
+#if defined _DEBUG
+		// Check for errors
+		const char* errorMessage;
+		if (m_oidnDevice.getError(errorMessage) != oidn::Error::None)
+		{
+			Profiler::getInstance().WriteToProfiler(errorMessage);
+		}
+#endif
 
-	// Check for errors
-	const char* errorMessage;
-	if (m_oidnDevice.getError(errorMessage) != oidn::Error::None)
-	{
-		Profiler::getInstance().WriteToProfiler(errorMessage);
+		// Write down denoised image in HDR format!!
+		stbi_write_hdr("Denoise.hdr", m_iBackbufferWidth, m_iBackbufferHeight, 3, outData);
 	}
-
-	// Write down denoised image in HDR format!!
-	stbi_write_hdr("Denoise.hdr", m_iBackbufferWidth, m_iBackbufferHeight, 3, outData);
 }
 
 ///////////////////////////////////////////////////////////////////////////////////////////////////
@@ -184,7 +200,7 @@ glm::vec3 Application::TraceColor(const Ray & r, int depth, int& rayCount)
 	HitRecord rec;
 	glm::vec3 traceColor = glm::vec3(0.0f, 0.0f, 0.0f);
 
-	if (Scene::getInstance().Trace(r, rayCount, 0.001f, FLT_MAX, rec))
+	if (m_pScene->Trace(r, rayCount, 0.001f, FLT_MAX, rec))
 	{
 		Ray scatteredRay;
 
@@ -208,7 +224,7 @@ glm::vec3 Application::TraceColor(const Ray & r, int depth, int& rayCount)
 		//glm::vec3 unit_direction = glm::normalize(r.GetRayDirection());
 		//float t = 0.5f * (unit_direction[1] + 1.0f);
 		//traceColor = Helper::LerpVector(glm::vec3(1.0f, 1.0f, 1.0f), glm::vec3(0.5f, 0.7f, 1.0f), t);
-		return glm::vec3(0.0f, 0.0f, 0.0f);
+		return glm::vec3(0.01f);
 	}
 
 	// debug info...
@@ -270,7 +286,7 @@ void Application::ParallelTrace(std::mutex * threadMutex, int i)
 					float u = float(i + Helper::GetRandom01()) / float(backBufferWidth);
 					float v = float(j + Helper::GetRandom01()) / float(backBufferHeight);
 
-					Ray r = m_pCamera->get_ray(u, v);
+					Ray r = m_pScene->getCamera()->get_ray(u, v);
 
 					color = color + TraceColor(r, 0, rayCount);
 				}
@@ -297,7 +313,7 @@ void Application::ParallelTrace(std::mutex * threadMutex, int i)
 ///////////////////////////////////////////////////////////////////////////////////////////////////
 void Application::Trace()
 {
-	if (m_pCamera == nullptr)
+	if (m_pScene == nullptr)
 		return;
 
 	if (m_bThreaded)
@@ -335,7 +351,7 @@ void Application::Trace()
 					float u = float(i + Helper::GetRandom01()) / float(m_iBackbufferWidth);
 					float v = float(j + Helper::GetRandom01()) / float(m_iBackbufferHeight);
 
-					Ray r = m_pCamera->get_ray(u, v);
+					Ray r = m_pScene->getCamera()->get_ray(u, v);
 
 					color = color + TraceColor(r, 0, rayCount);
 				}
diff --git a/Application.h b/Application.h
index 88efe10..c31a5c3 100644
--- a/Application.h
+++ b/Application.h
@@ -8,7 +8,7 @@
 #include <vector>
 
 class Ray;
-class Camera;
+class Scene;
 
 class Application
 {
@@ -36,6 +36,7 @@ private:
 	int				m_iNumSamples;
 	int				m_iMaxThreads;
 	float			m_dTotalRenderTime;
+	float			m_dDenoiserTime;
 	bool			m_bThreaded;
 
 	std::atomic<uint64_t>	m_iRayCount;
@@ -46,7 +47,7 @@ private:
 	std::atomic<uint64_t>    m_iTriangleCount;
 
 	HWND			m_hWnd;
-	Camera*			m_pCamera;
+	Scene*			m_pScene;
 
 	oidn::DeviceRef	m_oidnDevice;
 	oidn::FilterRef m_oidnFilter;
diff --git a/RayTracer/Camera.cpp b/RayTracer/Camera.cpp
index 98588a3..85d4870 100644
--- a/RayTracer/Camera.cpp
+++ b/RayTracer/Camera.cpp
@@ -2,23 +2,29 @@
 #include <Windows.h>
 #include "Camera.h"
 
+///////////////////////////////////////////////////////////////////////////////////////////////////
 Camera::Camera()
 {
+	position = glm::vec3(0.0f, 2.0f, 0.0f);
+	lookAt = glm::vec3(0.0f, 0.0f, 0.0f);
+	Up = glm::vec3(0.0f, 1.0f, 0.0f);
+
 	aperture = 0.0f;
 	focus_dist = 1.0f;
 	vfov = 45.0f;
 }
 
+///////////////////////////////////////////////////////////////////////////////////////////////////
 Camera::~Camera()
 {
 
 }
 
-void Camera::InitCamera(float screenWidth, float screenHeight)
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void Camera::InitCamera(const glm::vec3& _position, const glm::vec3& _lookAt, float screenWidth, float screenHeight)
 {
-	lookFrom = glm::vec3(5.0f, 3.0f, 5.0f);
-	lookAt = glm::vec3(0.0f, 0.0f, 0.0f);
-	Up = glm::vec3(0.0f, 1.0f, 0.0f);
+	position = _position;
+	lookAt = _lookAt;
 
 	lens_radius = aperture / 2.0f;
 	 
@@ -26,20 +32,20 @@ void Camera::InitCamera(float screenWidth, float screenHeight)
 	float half_height = tan(theta / 2);
 	float half_width = (screenWidth / screenHeight) * half_height;
 
-	origin = lookFrom;
-	w = glm::normalize(lookFrom - lookAt);
+	w = glm::normalize(position - lookAt);
 	u = glm::normalize(glm::cross(Up, w));
 	v = glm::normalize(glm::cross(w, u));
 
-	lower_left_corner = origin - half_width * focus_dist * u - half_height * focus_dist * v - focus_dist * w;
+	lower_left_corner = position - half_width * focus_dist * u - half_height * focus_dist * v - focus_dist * w;
 	horizontal = 2 * half_width * focus_dist * u;
 	vertical = 2 * half_height * focus_dist * v;
 }
 
+///////////////////////////////////////////////////////////////////////////////////////////////////
 Ray Camera::get_ray(float s, float t)
 {
 	glm::vec3 rd = lens_radius * Helper::GetRandomInUnitDisk();
 	glm::vec3 offset = rd[0] * u + rd[1] * v;
-	return Ray(origin + offset, lower_left_corner + s * horizontal + t * vertical - origin - offset);
+	return Ray(position + offset, lower_left_corner + s * horizontal + t * vertical - position - offset);
 }
 
diff --git a/RayTracer/Camera.h b/RayTracer/Camera.h
index 093450f..8b093bc 100644
--- a/RayTracer/Camera.h
+++ b/RayTracer/Camera.h
@@ -6,20 +6,14 @@
 class Camera
 {
 public:
-	static Camera& getInstance()
-	{
-		static Camera instance;
-		return instance;
-	}
-
+	Camera();
 	~Camera();
 
-	void InitCamera(float screenWidth, float screenHeight);
+	void InitCamera(const glm::vec3& _position, const glm::vec3& _lookAt, float _screenWidth, float _screenHeight);
 	Ray get_ray(float s, float t);
 
 private:
-	Camera();
-	glm::vec3 lookFrom, lookAt, Up;
+	glm::vec3 position, lookAt, Up;
 	glm::vec3 origin;
 	glm::vec3 lower_left_corner;
 	glm::vec3 horizontal;
diff --git a/RayTracer/Scene.cpp b/RayTracer/Scene.cpp
index baef714..61a6a1c 100644
--- a/RayTracer/Scene.cpp
+++ b/RayTracer/Scene.cpp
@@ -10,22 +10,36 @@
 #include "Texture.h"
 #include "Triangle.h"
 #include "TriangleMesh.h"
+#include "Camera.h"
 #include "../Profiler.h"
 
+///////////////////////////////////////////////////////////////////////////////////////////////////
 Scene::Scene()
 {
 	vecHitables.clear();
-	InitScene();
-	//InitRandomScene();
+	m_pCamera = nullptr;
 }
 
+///////////////////////////////////////////////////////////////////////////////////////////////////
 Scene::~Scene()
 {
 	vecHitables.clear();
+	if (m_pCamera)
+	{
+		delete m_pCamera;
+		m_pCamera = nullptr;
+	}
 }
 
-void Scene::InitScene()
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void Scene::InitScene(float screenWidth, float screenHeight)
 {
+	// Initialize Camera first...!!!
+	glm::vec3 cameraPosition = glm::vec3(5.0f, 2.5f, 5.0f);
+	glm::vec3 cameraLookAt = glm::vec3(0.0f, 0.0f, 0.0f);
+	m_pCamera = new Camera();
+	m_pCamera->InitCamera(cameraPosition, cameraLookAt, screenWidth, screenHeight);
+
 	// Sphere Ground
 	glm::vec3 center1(0.0f, -100.5f, 0.0f);
 	glm::vec3 albedo1(0.2f, 0.2f, 0.2f);
@@ -43,7 +57,7 @@ void Scene::InitScene()
 
 	Texture* baseTexture = new ImageTexture("models/Body_Color.jpg");
 	Material* pMatMesh = new Lambertian(baseTexture);
-	TriangleMesh* pMesh0 = new TriangleMesh("models/barb1.fbx", pMatMesh);
+	TriangleMesh* pMesh0 = new TriangleMesh("models/barb1.fbx", pMatMesh, 1024);
 
 	Profiler::getInstance().WriteToProfiler("Triangle Count:", pMesh0->GetTriangleCount());
 
@@ -55,8 +69,38 @@ void Scene::InitScene()
 	vecHitables.push_back(pMesh0);
 }
 
-void Scene::InitRandomScene()
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void Scene::InitCornellScene(float screenWidth, float screenHeight)
+{
+	// Initialize Camera first...!!!
+	glm::vec3 cameraPosition = glm::vec3(0.0f, 2.5f, 8.5f);
+	glm::vec3 cameraLookAt = glm::vec3(0.0f, 2.5f, 0.0f);
+	m_pCamera = new Camera();
+	m_pCamera->InitCamera(cameraPosition, cameraLookAt, screenWidth, screenHeight);
+
+	// Sphere Ground
+	
+	Sphere* pSphereLight = new Sphere(glm::vec3(0.0f, 1.0f, 1.0f), 1.0f, new DiffuseLight(new ConstantTexture(glm::vec3(1.0f, 1.0f, 1.0f))));
+	
+
+	Material* pMatMesh = new Lambertian(new ConstantTexture(glm::vec3(0.8f, 0.8f, 0.8f)));
+	TriangleMesh* pMesh0 = new TriangleMesh("models/Cornell.fbx", pMatMesh, 10);
+
+	Profiler::getInstance().WriteToProfiler("Triangle Count:", pMesh0->GetTriangleCount());
+
+	vecHitables.push_back(pSphereLight);
+	vecHitables.push_back(pMesh0);
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void Scene::InitRandomScene(float screenWidth, float screenHeight)
 {
+	// Initialize Camera first...!!!
+	glm::vec3 cameraPosition = glm::vec3(5.0f, 2.5f, 5.0f);
+	glm::vec3 cameraLookAt = glm::vec3(0.0f, 0.0f, 0.0f);
+	m_pCamera = new Camera();
+	m_pCamera->InitCamera(cameraPosition, cameraLookAt, screenWidth, screenHeight);
+
 	Sphere* pSphere0 = new Sphere(glm::vec3(0, -1000.0f, 0), 1000, new Lambertian(new ConstantTexture (glm::vec3(0.5, 0.5, 0.5))));
 	vecHitables.push_back(pSphere0);
 
@@ -102,6 +146,7 @@ void Scene::InitRandomScene()
 	vecHitables.push_back(pSphere3);
 }
 
+///////////////////////////////////////////////////////////////////////////////////////////////////
 bool Scene::Trace(const Ray& r, int& rayCount, float tmin, float tmax, HitRecord& rec)
 {
 	++rayCount;
diff --git a/RayTracer/Scene.h b/RayTracer/Scene.h
index dadb9a9..8de198d 100644
--- a/RayTracer/Scene.h
+++ b/RayTracer/Scene.h
@@ -8,20 +8,18 @@ class Camera;
 class Scene
 {
 public:
+	Scene();
 	~Scene();
-	
-	static Scene& getInstance()
-	{
-		static Scene instance;
-		return instance;
-	}
 
 	bool Trace(const Ray& r, int& rayCount, float tmin, float tmax, HitRecord& rec);
 
-private:
-	Scene();
-	void InitScene();
-	void InitRandomScene();
-	
+	void InitScene(float screenWidth, float screenHeight);
+	void InitCornellScene(float screenWidth, float screenHeight);
+	void InitRandomScene(float screenWidth, float screenHeight);
+
+	inline Camera* getCamera() { if(m_pCamera) return m_pCamera; }
+
+private:	
+	Camera*				  m_pCamera;
 	std::vector<Hitable*> vecHitables;
 };
\ No newline at end of file
diff --git a/RayTracer/TriangleMesh.cpp b/RayTracer/TriangleMesh.cpp
index ae99476..f116584 100644
--- a/RayTracer/TriangleMesh.cpp
+++ b/RayTracer/TriangleMesh.cpp
@@ -32,7 +32,7 @@ TriangleMesh::~TriangleMesh()
 }
 
 ///////////////////////////////////////////////////////////////////////////////////////////////////
-TriangleMesh::TriangleMesh(const std::string& path, Material* ptr_mat)
+TriangleMesh::TriangleMesh(const std::string& path, Material* ptr_mat, uint32_t _leafSize)
 {
 	m_vecTriangles.clear();
 	m_ptrMaterial = ptr_mat;
@@ -43,8 +43,9 @@ TriangleMesh::TriangleMesh(const std::string& path, Material* ptr_mat)
 
 	m_iTriangleCount = m_vecTriangles.size();
 
+	m_iLeafSize = _leafSize;
 	m_ptrBVH = new BVHTree();
-	m_ptrBVH->BuildBVHTree(&m_vecTriangles, m_iTriangleCount/8);
+	m_ptrBVH->BuildBVHTree(&m_vecTriangles, m_iLeafSize);
 }
 
 ///////////////////////////////////////////////////////////////////////////////////////////////////
diff --git a/RayTracer/TriangleMesh.h b/RayTracer/TriangleMesh.h
index 0a509fd..4e87b9b 100644
--- a/RayTracer/TriangleMesh.h
+++ b/RayTracer/TriangleMesh.h
@@ -17,7 +17,7 @@ class TriangleMesh : public Hitable
 public:
 	TriangleMesh();
 	~TriangleMesh();
-	TriangleMesh(const std::string& path, Material* ptr_mat);
+	TriangleMesh(const std::string& path, Material* ptr_mat, uint32_t _leafSize);
 
 	virtual bool hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const;
 	virtual void BoundingBox(AABB& box) const;
@@ -36,5 +36,6 @@ private:
 
 	BVHTree*			   m_ptrBVH;
 
+	uint32_t			   m_iLeafSize;
 	uint64_t			   m_iTriangleCount;
 };
diff --git a/WindowsRayTracer.cpp b/WindowsRayTracer.cpp
index d0f23f4..7934f9e 100644
--- a/WindowsRayTracer.cpp
+++ b/WindowsRayTracer.cpp
@@ -177,9 +177,9 @@ LRESULT CALLBACK WndProc(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam)
 
 			case ID_FILE_DENOISEIMAGE:
 			{
-				OutputDebugString(L"Denoising...");
+				OutputDebugString(L"\nDenoising...");
 				pApp->DenoiseImage();
-				OutputDebugString(L"Denoising Done!");
+				OutputDebugString(L"\nDenoising Done!");
 				break;
 			}
 		
```

