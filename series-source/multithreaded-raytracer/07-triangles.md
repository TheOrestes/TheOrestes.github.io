# Post 7 — Triangles

## `06912d4` — 2018-08-26 _(master)_

> Added Triangle primitive support.

```diff
diff --git a/RayTracer/Triangle.h b/RayTracer/Triangle.h
new file mode 100644
index 0000000..d882297
--- /dev/null
+++ b/RayTracer/Triangle.h
@@ -0,0 +1,103 @@
+#pragma once
+
+#pragma once
+
+#include "Hitable.h"
+
+class Material;
+
+class Triangle : public Hitable
+{
+public:
+	Triangle() {}
+	Triangle(Vector3 _v0, Vector3 _v1, Vector3 _v2, Material* ptr_mat) :
+		V0(_v0),
+		V1(_v1),
+		V2(_v2),
+		mat_ptr(ptr_mat) {};
+
+	virtual bool hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const;
+
+private:
+	Vector3 V0;
+	Vector3 V1;
+	Vector3 V2;
+	Material* mat_ptr;
+};
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
diff --git a/RayTracer/Vector3.cpp b/RayTracer/Vector3.cpp
index 0c9d583..c2b4460 100644
--- a/RayTracer/Vector3.cpp
+++ b/RayTracer/Vector3.cpp
@@ -60,13 +60,3 @@ inline Vector3& Vector3::operator/=(const float v)
 
 	return *this;
 }
-
-///////////////////////////////////////////////////////////////////////////////////////////////////
-inline void Vector3::MakeUnitVector()
-{
-	float k = 1.0 / sqrt(x * x + y * y + z * z);
-	x *= k;
-	y *= k;
-	z *= k;
-}
-/////////////////////////////////////////////////////////////////////////////////////////
\ No newline at end of file
diff --git a/RayTracer/Vector3.h b/RayTracer/Vector3.h
index eb5cdd8..4b5e77a 100644
--- a/RayTracer/Vector3.h
+++ b/RayTracer/Vector3.h
@@ -22,8 +22,7 @@ public:
 
 	inline float length() const { return sqrt(x * x + y * y + z * z); }
 	inline float squaredLength() const { return(x*x + y * y + z * z); }
-	inline void  MakeUnitVector();
-
+	
 	float x, y, z;
 };
 
diff --git a/WindowsRayTracer.cpp b/WindowsRayTracer.cpp
index 341bb42..c72f8b3 100644
--- a/WindowsRayTracer.cpp
+++ b/WindowsRayTracer.cpp
@@ -13,6 +13,7 @@
 #include "./RayTracer/Vector3.h"
 #include "./RayTracer/Ray.h"
 #include "./RayTracer/Sphere.h"
+#include "./RayTracer/Triangle.h"
 #include "./RayTracer/HitableList.h"
 #include "./RayTracer/Camera.h"
 #include "./RayTracer/Helper.h"
@@ -26,7 +27,7 @@
 const int COLOR_CHANNELS = 3; // RGB
 const int gBackbufferWidth = 960;
 const int gBackbufferHeight = 540;
-const int nSamples = 50;
+const int nSamples = 100;
 
 unsigned long long int numRays = 0;
 
@@ -40,13 +41,13 @@ double TotalRenderTime = 0;
 #include "enkiTS\TaskScheduler.h"
 #endif
 
-Vector3 lookFrom(0, 1.5, 6);
+Vector3 lookFrom(0, 5, 5);
 Vector3 lookAt(0, 0, 0);
 float dist_to_focus = 1.0f;	// set this to 1.0 & apertue to 0.0f to stop DOF effect!
 float aperture = 0.0f;
 
 
-Camera cam(lookFrom, lookAt, Vector3(0, 1, 0), 20, float(gBackbufferWidth) / float(gBackbufferHeight), aperture, dist_to_focus);
+Camera cam(lookFrom, lookAt, Vector3(0, 1, 0), 40, float(gBackbufferWidth) / float(gBackbufferHeight), aperture, dist_to_focus);
 
 #define MAX_LOADSTRING 100
 
@@ -67,18 +68,17 @@ INT_PTR CALLBACK    About(HWND, UINT, WPARAM, LPARAM);
 
 Hitable* BasicTestScene()
 {
-	Hitable** list = new Hitable*[5];
+	Hitable** list = new Hitable*[6];
 	list[0] = new Sphere(Vector3(1.05f, 0, 0), 0.5, new Metal(Vector3(0.5, 0.2, 0.1), 0.5));
 	list[1] = new Sphere(Vector3(0, -100.5, 0), 100, new Lambertian(Vector3(0.2, 0.2, 0.2)));
-	list[2] = new Sphere(Vector3(0, 0, 0.1), 0.5, new Transparent(1.5f));
+	list[2] = new Sphere(Vector3(0, 0, 2), 0.5, new Lambertian(Vector3(1.0f, 0.0f, 0.0f)));
 	list[3] = new Sphere(Vector3(-1.05f, 0, 0), 0.5, new Metal(Vector3(1.0, 0.2, 0.0), 0));
 	list[4] = new Sphere(Vector3(0.0f, 0, -3), 0.5, new Lambertian(Vector3(1.0, 1.0, 0.0)));
+	list[5] = new Triangle(Vector3(-2.0f, 0.0f, -1.0f), Vector3(2.0f, 0.0f, -1.0f), Vector3(0.0f, 2.0f, -1.0f), new Lambertian(Vector3(0.0f, 1.0f, 0.0f)));
 
-	return new HitableList(list, 5);
+	return new HitableList(list, 6);
 }
 
-Hitable* world = BasicTestScene();
-
 Hitable* random_scene()
 {
 	int n = 500;
@@ -119,6 +119,8 @@ Hitable* random_scene()
 	return new HitableList(list, i);
 }
 
+Hitable* world = BasicTestScene();
+
 Vector3 TraceColor(const Ray& r, int depth)
 {
 	HitRecord rec;
@@ -212,7 +214,8 @@ void ParallelTrace(std::mutex* threadMutex, int i)
 void Trace()
 {
 #pragma region OLD_CODE
-	//for (int j = 0; j <= gBackbufferHeight; j++)
+	//HDC hdc = GetDC(hWnd);
+	//for (int j = gBackbufferHeight; j >= 0; j--)
 	//{
 	//	for (int i = 0; i <= gBackbufferWidth; i++)
 	//	{
@@ -225,7 +228,7 @@ void Trace()
 	//
 	//			Ray r = cam.get_ray(u, v);
 	//
-	//			color = color + TraceColor(r, world, 0);
+	//			color = color + TraceColor(r, 0);
 	//		}
 	//
 	//		color = color / float(nSamples);
```

