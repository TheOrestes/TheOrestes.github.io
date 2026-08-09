# Post 10 — Textures: stb_image and barycentric UVs

## `589f360` — 2018-12-20 _(master)_

> Added Constant Color Texture support.

```diff
diff --git a/RayTracer/AABB.cpp b/RayTracer/AABB.cpp
index 9356763..e15e200 100644
--- a/RayTracer/AABB.cpp
+++ b/RayTracer/AABB.cpp
@@ -27,7 +27,7 @@ bool AABB::hit(const Ray & r, float tmin, float tmax)
 	glm::vec3 rayDirection = r.GetRayDirection();
 	glm::vec3 rayInvDirection = r.GetInvRayDirection();
 	
-	// X Direction
+	// Direction X
 	float t0x = (minBound.x - rayOrigin.x) * rayInvDirection.x;
 	float t1x = (maxBound.x - rayOrigin.x) * rayInvDirection.x;
 	if (rayInvDirection.x < 0.0f)
diff --git a/RayTracer/Lambertian.cpp b/RayTracer/Lambertian.cpp
index 5846f10..cac5215 100644
--- a/RayTracer/Lambertian.cpp
+++ b/RayTracer/Lambertian.cpp
@@ -6,6 +6,6 @@ bool Lambertian::Scatter(const Ray& r_in, const HitRecord& rec, glm::vec3& atten
 {
 	glm::vec3 target = rec.P + rec.N + Helper::RandomInUnitSphere();
 	scatterd = Ray(rec.P, target - rec.P);
-	attenuation = Albedo;
+	attenuation = Albedo->value(0,0);
 	return true;
 }
\ No newline at end of file
diff --git a/RayTracer/Lambertian.h b/RayTracer/Lambertian.h
index 2568613..89d60ad 100644
--- a/RayTracer/Lambertian.h
+++ b/RayTracer/Lambertian.h
@@ -3,14 +3,15 @@
 #include "Ray.h"
 #include "Hitable.h"
 #include "Material.h"
+#include "Texture.h"
 
 class Lambertian : public Material
 {
 public:
-	Lambertian(const glm::vec3& _albedo) : Albedo(_albedo) {}
+	Lambertian(Texture* _albedo) : Albedo(_albedo) {}
 
 	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, glm::vec3& attenuation, Ray& scatterd) const;
 
 private:
-	glm::vec3 Albedo;
+	Texture* Albedo;
 };
\ No newline at end of file
diff --git a/RayTracer/Metal.cpp b/RayTracer/Metal.cpp
index 92c8e8d..918cff0 100644
--- a/RayTracer/Metal.cpp
+++ b/RayTracer/Metal.cpp
@@ -6,6 +6,6 @@ bool Metal::Scatter(const Ray& r_in, const HitRecord& rec, glm::vec3& attenuatio
 {
 	glm::vec3 target = glm::reflect(glm::normalize(r_in.GetRayDirection()), rec.N);
 	scatterd = Ray(rec.P, target + fuzz * Helper::RandomInUnitSphere());
-	attenuation = Albedo;
+	attenuation = Albedo->value(0,0);
 	return (glm::dot(scatterd.GetRayDirection(), rec.N) > 0);
 }
\ No newline at end of file
diff --git a/RayTracer/Metal.h b/RayTracer/Metal.h
index 33a761e..cf228cd 100644
--- a/RayTracer/Metal.h
+++ b/RayTracer/Metal.h
@@ -3,11 +3,12 @@
 #include "Ray.h"
 #include "Hitable.h"
 #include "Material.h"
+#include "Texture.h"
 
 class Metal : public Material
 {
 public:
-	Metal (const glm::vec3& _albedo, float f) : Albedo(_albedo) 
+	Metal (Texture* _albedo, float f) : Albedo(_albedo) 
 	{
 		if (f < 1)
 			fuzz = f;
@@ -18,6 +19,6 @@ public:
 	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, glm::vec3& attenuation, Ray& scatterd) const;
 
 private:
-	glm::vec3 Albedo;
+	Texture* Albedo;
 	float fuzz;
 };
diff --git a/RayTracer/Scene.cpp b/RayTracer/Scene.cpp
index b6a065b..7eaecf0 100644
--- a/RayTracer/Scene.cpp
+++ b/RayTracer/Scene.cpp
@@ -5,6 +5,7 @@
 #include "Lambertian.h"
 #include "Metal.h"
 #include "Transparent.h"
+#include "Texture.h"
 #include "Triangle.h"
 #include "TriangleMesh.h"
 
@@ -24,21 +25,21 @@ void Scene::InitScene()
 {
 	glm::vec3 center0(-3.0f, 0, 0);
 	glm::vec3 albedo0(1, 0, 0);
-	Material* pMatSphere0 = new Metal(albedo0, 0.2f);
+	Material* pMatSphere0 = new Metal(new ConstantTexture(albedo0), 0.2f);
 	Sphere* pSphere0 = new Sphere(center0, 0.5f, pMatSphere0);
 
 	// Sphere2
 	glm::vec3 center1(0, -100.5, 0);
 	glm::vec3 albedo1(0.3, 0.3, 0.3);
-	Material* pMatSphere1 = new Lambertian(albedo1);
+	Material* pMatSphere1 = new Lambertian(new ConstantTexture(albedo1));
 	Sphere* pSphere1 = new Sphere(center1, 100.0f, pMatSphere1);
 
 	Sphere* pSphere2 = new Sphere(glm::vec3(0, 0.0f, 2.05f), 0.5f, new Transparent(1.5f));
-	Sphere* pSphere3 = new Sphere(glm::vec3(1.05f, 0.5f, -2.05), 1, new Metal(glm::vec3(1.0, 0.2, 0.0), 0));
-	Sphere* pSphere4 = new Sphere(glm::vec3(2.05f, 0.0f, 0), 0.5, new Lambertian(glm::vec3(0.0f, 0.4f, 1.0f)));
-	Triangle* pTriangle0  = new Triangle(glm::vec3(-2.0f, 0.0f, -1.0f), glm::vec3(2.0f, 0.0f, -1.0f), glm::vec3(0.0f, 2.0f, -1.0f), new Metal(glm::vec3(0.0, 1.0f, 0.0f), 0.5f));
+	Sphere* pSphere3 = new Sphere(glm::vec3(1.05f, 0.5f, -2.05), 1, new Metal(new ConstantTexture(glm::vec3(1.0, 0.2, 0.0)), 0));
+	Sphere* pSphere4 = new Sphere(glm::vec3(2.05f, 0.0f, 0), 0.5, new Lambertian(new ConstantTexture(glm::vec3(0.0f, 0.4f, 1.0f))));
+	Triangle* pTriangle0  = new Triangle(glm::vec3(-2.0f, 0.0f, -1.0f), glm::vec3(2.0f, 0.0f, -1.0f), glm::vec3(0.0f, 2.0f, -1.0f), new Metal(new ConstantTexture(glm::vec3(0.0, 1.0f, 0.0f)), 0.5f));
 
-	TriangleMesh* pMesh0 = new TriangleMesh("models/deer.obj", new Metal(glm::vec3(0.0f, 0.85f, 0.25f), 0.2f));
+	TriangleMesh* pMesh0 = new TriangleMesh("models/deer.obj", new Metal(new ConstantTexture(glm::vec3(0.0f, 0.85f, 0.25f)), 0.2f));
 
 	vecHitables.push_back(pSphere0);
 	vecHitables.push_back(pSphere1);
@@ -51,7 +52,7 @@ void Scene::InitScene()
 
 void Scene::InitRandomScene()
 {
-	Sphere* pSphere0 = new Sphere(glm::vec3(0, -1000, 0), 1000, new Lambertian(glm::vec3(0.5, 0.5, 0.5)));
+	Sphere* pSphere0 = new Sphere(glm::vec3(0, -1000, 0), 1000, new Lambertian(new ConstantTexture (glm::vec3(0.5, 0.5, 0.5))));
 	vecHitables.push_back(pSphere0);
 
 	int i = 1;
@@ -68,13 +69,13 @@ void Scene::InitRandomScene()
 				if (choose_mat < 0.8f)
 				{
 					// diffuse
-					Sphere* temp = new Sphere(center, 0.2f, new Lambertian(glm::vec3(Helper::GetRandom01() * Helper::GetRandom01(), Helper::GetRandom01() * Helper::GetRandom01(), Helper::GetRandom01() * Helper::GetRandom01())));
+					Sphere* temp = new Sphere(center, 0.2f, new Lambertian(new ConstantTexture(glm::vec3(Helper::GetRandom01() * Helper::GetRandom01(), Helper::GetRandom01() * Helper::GetRandom01(), Helper::GetRandom01() * Helper::GetRandom01()))));
 					vecHitables.push_back(temp);
 				}
 				else if (choose_mat < 0.95f)
 				{
 					// Metal
-					Sphere* temp = new Sphere(center, 0.2f, new Metal(glm::vec3(0.5f*(1 + Helper::GetRandom01()), 0.5f*(1 + Helper::GetRandom01()), 0.5f*(1 + Helper::GetRandom01())), Helper::GetRandom01()));
+					Sphere* temp = new Sphere(center, 0.2f, new Metal(new ConstantTexture(glm::vec3(0.5f*(1 + Helper::GetRandom01()), 0.5f*(1 + Helper::GetRandom01()), 0.5f*(1 + Helper::GetRandom01()))), Helper::GetRandom01()));
 					vecHitables.push_back(temp);
 				}
 				else
@@ -88,8 +89,8 @@ void Scene::InitRandomScene()
 	}
 
 	Sphere* pSphere1 = new Sphere(glm::vec3(0, 1, 0), 1.0f, new Transparent(1.5f));
-	Sphere* pSphere2 = new Sphere(glm::vec3(-4, 1, 0), 1.0f, new Lambertian(glm::vec3(0.4f, 0.2f, 0.1f)));
-	Sphere* pSphere3 = new Sphere(glm::vec3(4, 1, 0), 1.0f, new Metal(glm::vec3(0.7f, 0.6f, 0.5f), 0.0f));
+	Sphere* pSphere2 = new Sphere(glm::vec3(-4, 1, 0), 1.0f, new Lambertian(new ConstantTexture(glm::vec3(0.4f, 0.2f, 0.1f))));
+	Sphere* pSphere3 = new Sphere(glm::vec3(4, 1, 0), 1.0f, new Metal(new ConstantTexture(glm::vec3(0.7f, 0.6f, 0.5f)), 0.0f));
 
 	vecHitables.push_back(pSphere1);
 	vecHitables.push_back(pSphere2);
diff --git a/RayTracer/Texture.h b/RayTracer/Texture.h
new file mode 100644
index 0000000..259fa63
--- /dev/null
+++ b/RayTracer/Texture.h
@@ -0,0 +1,24 @@
+#pragma once
+
+#include "glm/vec3.hpp"
+
+class Texture
+{
+public:
+	virtual glm::vec3 value(float u, float v) const = 0;
+};
+
+class ConstantTexture : public Texture
+{
+public:
+	ConstantTexture() {}
+	ConstantTexture(glm::vec3 col) : color(col) {}
+
+	virtual glm::vec3 value(float u, float v) const
+	{
+		return color;
+	}
+
+private:
+	glm::vec3 color;
+};
\ No newline at end of file
```

## `2aadee0` — 2018-12-24 _(master)_

> - Added Texture loading using stb_image.h - Added Vertex structure - Modified materials to support textures - Added code for non optimized barycentric co-ordinates calculation.

```diff
diff --git a/RayTracer/Hitable.h b/RayTracer/Hitable.h
index 3e5f970..2b6233c 100644
--- a/RayTracer/Hitable.h
+++ b/RayTracer/Hitable.h
@@ -9,6 +9,7 @@ struct HitRecord
 	float t;
 	glm::vec3 P;
 	glm::vec3 N;
+	glm::vec2 uv;
 	Material* mat_ptr;
 };
 
diff --git a/RayTracer/Lambertian.cpp b/RayTracer/Lambertian.cpp
index cac5215..d6736be 100644
--- a/RayTracer/Lambertian.cpp
+++ b/RayTracer/Lambertian.cpp
@@ -6,6 +6,6 @@ bool Lambertian::Scatter(const Ray& r_in, const HitRecord& rec, glm::vec3& atten
 {
 	glm::vec3 target = rec.P + rec.N + Helper::RandomInUnitSphere();
 	scatterd = Ray(rec.P, target - rec.P);
-	attenuation = Albedo->value(0,0);
+	attenuation = Albedo->value(rec.uv);
 	return true;
 }
\ No newline at end of file
diff --git a/RayTracer/Metal.cpp b/RayTracer/Metal.cpp
index 918cff0..e22f2b6 100644
--- a/RayTracer/Metal.cpp
+++ b/RayTracer/Metal.cpp
@@ -6,6 +6,6 @@ bool Metal::Scatter(const Ray& r_in, const HitRecord& rec, glm::vec3& attenuatio
 {
 	glm::vec3 target = glm::reflect(glm::normalize(r_in.GetRayDirection()), rec.N);
 	scatterd = Ray(rec.P, target + fuzz * Helper::RandomInUnitSphere());
-	attenuation = Albedo->value(0,0);
+	attenuation = Albedo->value(rec.uv);
 	return (glm::dot(scatterd.GetRayDirection(), rec.N) > 0);
 }
\ No newline at end of file
diff --git a/RayTracer/Scene.cpp b/RayTracer/Scene.cpp
index 7eaecf0..f3c2d7b 100644
--- a/RayTracer/Scene.cpp
+++ b/RayTracer/Scene.cpp
@@ -36,10 +36,12 @@ void Scene::InitScene()
 
 	Sphere* pSphere2 = new Sphere(glm::vec3(0, 0.0f, 2.05f), 0.5f, new Transparent(1.5f));
 	Sphere* pSphere3 = new Sphere(glm::vec3(1.05f, 0.5f, -2.05), 1, new Metal(new ConstantTexture(glm::vec3(1.0, 0.2, 0.0)), 0));
-	Sphere* pSphere4 = new Sphere(glm::vec3(2.05f, 0.0f, 0), 0.5, new Lambertian(new ConstantTexture(glm::vec3(0.0f, 0.4f, 1.0f))));
+	Sphere* pSphere4 = new Sphere(glm::vec3(2.05f, 0.0f, 0), 0.5, new Lambertian(new ImageTexture("models/earth.jpg")));
 	Triangle* pTriangle0  = new Triangle(glm::vec3(-2.0f, 0.0f, -1.0f), glm::vec3(2.0f, 0.0f, -1.0f), glm::vec3(0.0f, 2.0f, -1.0f), new Metal(new ConstantTexture(glm::vec3(0.0, 1.0f, 0.0f)), 0.5f));
 
-	TriangleMesh* pMesh0 = new TriangleMesh("models/deer.obj", new Metal(new ConstantTexture(glm::vec3(0.0f, 0.85f, 0.25f)), 0.2f));
+	Texture* metalTexture = new ImageTexture("models/512.jpg");
+	Material* pMatMesh = new Metal(metalTexture, 0.2f);
+	TriangleMesh* pMesh0 = new TriangleMesh("models/deer.obj", pMatMesh);
 
 	vecHitables.push_back(pSphere0);
 	vecHitables.push_back(pSphere1);
diff --git a/RayTracer/Sphere.cpp b/RayTracer/Sphere.cpp
index 130688c..b0bbe83 100644
--- a/RayTracer/Sphere.cpp
+++ b/RayTracer/Sphere.cpp
@@ -1,5 +1,6 @@
 
 #include "Sphere.h"
+#include "Helper.h"
 
 /////////////////////////////////////////////////////////////////////////////////////////
 bool Sphere::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
@@ -23,6 +24,8 @@ bool Sphere::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
 			rec.t = t;
 			rec.P = r.GetPointAt(t);
 			rec.N = (rec.P - center) / radius;
+			rec.uv = GetSphereUV((rec.P - center) / radius);
+
 			rec.mat_ptr = mat_ptr;
 			return true;
 		}
@@ -33,10 +36,24 @@ bool Sphere::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
 			rec.t = t;
 			rec.P = r.GetPointAt(t);
 			rec.N = (rec.P - center) / radius;
+			rec.uv = GetSphereUV((rec.P - center) / radius);
+
 			rec.mat_ptr = mat_ptr;
 			return true;
 		}
 	}
 
 	return false;
-}
\ No newline at end of file
+}
+
+/////////////////////////////////////////////////////////////////////////////////////////
+glm::vec2 Sphere::GetSphereUV(const glm::vec3& p) const
+{
+	float phi = std::atan2(p.z, p.x);
+	float theta = std::asin(p.y);
+
+	float x = 1 - (phi + PI) / (2 * PI);
+	float y = (theta + PI / 2) / PI;
+
+	return glm::vec2(x, y);
+}
diff --git a/RayTracer/Sphere.h b/RayTracer/Sphere.h
index 5be8f14..b81fa54 100644
--- a/RayTracer/Sphere.h
+++ b/RayTracer/Sphere.h
@@ -14,6 +14,7 @@ public:
 		mat_ptr(ptr_mat) {};
 
 	virtual bool hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const;
+	glm::vec2 GetSphereUV(const glm::vec3& p) const;
 
 private:
 	glm::vec3 center;
diff --git a/RayTracer/Texture.cpp b/RayTracer/Texture.cpp
new file mode 100644
index 0000000..8a16a50
--- /dev/null
+++ b/RayTracer/Texture.cpp
@@ -0,0 +1,37 @@
+
+#define STB_IMAGE_IMPLEMENTATION
+#include "stb_image.h"
+
+#include "Texture.h"
+
+ImageTexture::ImageTexture(const std::string & _path)
+{
+	path = _path;
+	LoadImage();
+}
+
+glm::vec3 ImageTexture::value(glm::vec2 uv) const
+{
+	// Images with alpha channels not supported yet!
+	if (channels > 3)
+		return glm::vec3(1, 0, 0.8f);
+
+	int i = uv.x * width;
+	int j = (1 - uv.y) * height;
+
+	if (i < 0) i = 0;
+	if (j < 0) j = 0;
+	if (i > width - 1) i = width - 1;
+	if (j > height - 1) j = height - 1;
+
+	float r = int(data[channels * i + channels * width * j]    ) / 255.0f;
+	float g = int(data[channels * i + channels * width * j + 1]) / 255.0f;
+	float b = int(data[channels * i + channels * width * j + 2]) / 255.0f;
+
+	return glm::vec3(r, g, b);
+}
+
+void ImageTexture::LoadImage()
+{
+	data = stbi_load(path.c_str(), &width, &height, &channels, 0);
+}
diff --git a/RayTracer/Texture.h b/RayTracer/Texture.h
index 259fa63..119c351 100644
--- a/RayTracer/Texture.h
+++ b/RayTracer/Texture.h
@@ -1,11 +1,12 @@
 #pragma once
 
-#include "glm/vec3.hpp"
+#include "glm/glm.hpp"
+#include <string>
 
 class Texture
 {
 public:
-	virtual glm::vec3 value(float u, float v) const = 0;
+	virtual glm::vec3 value(glm::vec2 uv) const = 0;
 };
 
 class ConstantTexture : public Texture
@@ -14,11 +15,29 @@ public:
 	ConstantTexture() {}
 	ConstantTexture(glm::vec3 col) : color(col) {}
 
-	virtual glm::vec3 value(float u, float v) const
+	virtual glm::vec3 value(glm::vec2 uv) const
 	{
 		return color;
 	}
 
 private:
 	glm::vec3 color;
+};
+
+class ImageTexture : public Texture
+{
+public:
+	ImageTexture() {}
+	ImageTexture(const std::string& _path);
+
+	virtual glm::vec3 value(glm::vec2 uv) const;
+
+private:
+	glm::vec3 color;
+	std::string path;
+
+	void LoadImage();
+
+	int width, height, channels;
+	unsigned char* data;
 };
\ No newline at end of file
diff --git a/RayTracer/Triangle.cpp b/RayTracer/Triangle.cpp
index 4db6edc..8802a62 100644
--- a/RayTracer/Triangle.cpp
+++ b/RayTracer/Triangle.cpp
@@ -9,7 +9,13 @@ bool Triangle::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
 	glm::vec3 edge1 = V2 - V1;
 	glm::vec3 edge2 = V0 - V2;
 
-	glm::vec3 N = glm::normalize(glm::cross(edge0, edge1));
+	// NOTE that we are not normalizing the normal vector
+	// as we need to take it's area.
+	glm::vec3 NormalWithMagnitude = glm::cross(edge0, edge1);
+	float area = NormalWithMagnitude.length() / 2;
+
+	// Normalize normal now!
+	glm::vec3 N = glm::normalize(NormalWithMagnitude);
 
 	glm::vec3 rayDirection = r.GetRayDirection();
 	glm::vec3 rayOrigin = r.GetRayOrigin();
@@ -37,12 +43,18 @@ bool Triangle::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
 	glm::vec3 P1 = P - V1;
 	glm::vec3 P2 = P - V2;
 
-	if (glm::dot(N, glm::cross(edge0, P0)) >= 0 && glm::dot(N, glm::cross(edge1, P1)) >= 0 && glm::dot(N, glm::cross(edge2, P2)) >= 0)
+	glm::vec3 C0 = glm::cross(edge0, P0);
+	glm::vec3 C1 = glm::cross(edge1, P1);
+	glm::vec3 C2 = glm::cross(edge2, P2);
+
+	if (glm::dot(N, C0) >= 0 && glm::dot(N, C1) >= 0 && glm::dot(N, C2) >= 0)
 	{
 		// Record hit data!!!
 		rec.t = t;
 		rec.P = P;
 		rec.N = N;
+		rec.uv.x = (C1.length() * 0.5f) / area;
+		rec.uv.y = (C2.length() * 0.5f) / area;
 		rec.mat_ptr = mat_ptr;
 
 		return true;
diff --git a/RayTracer/Triangle.h b/RayTracer/Triangle.h
index 71c5e25..bff4e89 100644
--- a/RayTracer/Triangle.h
+++ b/RayTracer/Triangle.h
@@ -4,6 +4,7 @@
 #include "Hitable.h"
 
 class Material;
+struct VertexPNT;
 
 class Triangle : public Hitable
 {
diff --git a/RayTracer/TriangleMesh.h b/RayTracer/TriangleMesh.h
index 581cb93..dcf3e6b 100644
--- a/RayTracer/TriangleMesh.h
+++ b/RayTracer/TriangleMesh.h
@@ -15,7 +15,7 @@ class TriangleMesh : public Hitable
 {
 public:
 	TriangleMesh();
-	~TriangleMesh();
+	~TriangleMesh() {}
 	TriangleMesh(const std::string& path, Material* ptr_mat);
 
 	virtual bool hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const;
diff --git a/RayTracer/VertexStructures.h b/RayTracer/VertexStructures.h
new file mode 100644
index 0000000..7fea28c
--- /dev/null
+++ b/RayTracer/VertexStructures.h
@@ -0,0 +1,38 @@
+#pragma once
+
+#include "glm/glm.hpp"
+
+/////////////////////////////////////////////////////////////////////////////////////////
+struct VertexP
+{
+	VertexP() {}
+	VertexP(const glm::vec3& _pos) : position(_pos) {}
+
+	glm::vec3 position;
+};
+
+/////////////////////////////////////////////////////////////////////////////////////////
+struct VertexPN
+{
+	VertexPN() {}
+	VertexPN(const glm::vec3& _pos, const glm::vec3& _normal) :	
+		position(_pos),
+		normal(_normal) {}
+
+	glm::vec3 position;
+	glm::vec3 normal;
+};
+
+/////////////////////////////////////////////////////////////////////////////////////////
+struct VertexPNT
+{
+	VertexPNT() {}
+	VertexPNT(const glm::vec3& _pos, const glm::vec3& _normal, const glm::vec3 _uv) :
+		position(_pos),
+		normal(_normal),
+		uv(_uv) {}
+
+	glm::vec3 position;
+	glm::vec3 normal;
+	glm::vec3 uv;
+};
diff --git a/WindowsRayTracer.cpp b/WindowsRayTracer.cpp
index eee7040..6f18efe 100644
--- a/WindowsRayTracer.cpp
+++ b/WindowsRayTracer.cpp
@@ -25,9 +25,9 @@
 #define C11_THREADS
 
 const int COLOR_CHANNELS = 3; // RGB
-const int gBackbufferWidth = 960;
-const int gBackbufferHeight = 480;
-const int nSamples = 1;
+const int gBackbufferWidth = 480;
+const int gBackbufferHeight = 270;
+const int nSamples = 5;
 
 unsigned long long int numRays = 0;
 
@@ -123,7 +123,7 @@ glm::vec3 TraceColor(const Ray& r, int depth)
 	if (Scene::getInstance().Trace(r, 0.001f, FLT_MAX, rec))
 	{
 		Ray scatteredRay;
-		glm::vec3 attenuation;
+		glm::vec3 attenuation = glm::vec3(0);
 
 		if (depth < 50 && rec.mat_ptr->Scatter(r, rec, attenuation, scatteredRay))
 		{
```

## `8f14d49` — 2018-12-31 _(master)_

> Added Barycentric coordinates for texture lookup UVs

```diff
diff --git a/RayTracer/Camera.cpp b/RayTracer/Camera.cpp
index 5fe3ee0..0132b56 100644
--- a/RayTracer/Camera.cpp
+++ b/RayTracer/Camera.cpp
@@ -16,8 +16,8 @@ Camera::~Camera()
 
 void Camera::InitCamera(float screenWidth, float screenHeight)
 {
-	lookFrom = glm::vec3(4.0f, 4.0f, 7.0f);
-	lookAt = glm::vec3(0.0f, 2.0f, 0.0f);
+	lookFrom = glm::vec3(5.0f, 3.0f, 5.0f);
+	lookAt = glm::vec3(0.0f, 0.0f, 0.0f);
 	Up = glm::vec3(0.0f, 1.0f, 0.0f);
 
 	lens_radius = aperture / 2.0f;
diff --git a/RayTracer/Scene.cpp b/RayTracer/Scene.cpp
index f3c2d7b..0d346b7 100644
--- a/RayTracer/Scene.cpp
+++ b/RayTracer/Scene.cpp
@@ -23,29 +23,29 @@ Scene::~Scene()
 
 void Scene::InitScene()
 {
-	glm::vec3 center0(-3.0f, 0, 0);
+	glm::vec3 center0(-3.0f, 0.15f, 0);
 	glm::vec3 albedo0(1, 0, 0);
-	Material* pMatSphere0 = new Metal(new ConstantTexture(albedo0), 0.2f);
-	Sphere* pSphere0 = new Sphere(center0, 0.5f, pMatSphere0);
+	Material* pMatSphere0 = new Metal(new ConstantTexture(glm::vec3(1.0, 0.3, 0.0)), 0);
+	Sphere* pSphere0 = new Sphere(center0, 0.8f, pMatSphere0);
 
 	// Sphere2
 	glm::vec3 center1(0, -100.5, 0);
-	glm::vec3 albedo1(0.3, 0.3, 0.3);
+	glm::vec3 albedo1(0.2);
 	Material* pMatSphere1 = new Lambertian(new ConstantTexture(albedo1));
 	Sphere* pSphere1 = new Sphere(center1, 100.0f, pMatSphere1);
 
-	Sphere* pSphere2 = new Sphere(glm::vec3(0, 0.0f, 2.05f), 0.5f, new Transparent(1.5f));
-	Sphere* pSphere3 = new Sphere(glm::vec3(1.05f, 0.5f, -2.05), 1, new Metal(new ConstantTexture(glm::vec3(1.0, 0.2, 0.0)), 0));
-	Sphere* pSphere4 = new Sphere(glm::vec3(2.05f, 0.0f, 0), 0.5, new Lambertian(new ImageTexture("models/earth.jpg")));
-	Triangle* pTriangle0  = new Triangle(glm::vec3(-2.0f, 0.0f, -1.0f), glm::vec3(2.0f, 0.0f, -1.0f), glm::vec3(0.0f, 2.0f, -1.0f), new Metal(new ConstantTexture(glm::vec3(0.0, 1.0f, 0.0f)), 0.5f));
+	Sphere* pSphere2 = new Sphere(glm::vec3(-1.0, 0.0f, 1.5f), 0.5f, new Transparent(1.5f));
+	Sphere* pSphere3 = new Sphere(glm::vec3(-4.0f, 0.4f, 0.0f), 1.0f, new Metal(new ConstantTexture(glm::vec3(1.0, 0.1, 0.0)), 0));
+	Sphere* pSphere4 = new Sphere(glm::vec3(2.5f, 0.0f, 0), 0.5, new Lambertian(new ImageTexture("models/earth.jpg")));
+	//Triangle* pTriangle0  = new Triangle(glm::vec3(-2.0f, 0.0f, -1.0f), glm::vec3(2.0f, 0.0f, -1.0f), glm::vec3(0.0f, 2.0f, -1.0f), new Metal(new ConstantTexture(glm::vec3(0.0, 1.0f, 0.0f)), 0.5f));
+	Texture* baseTexture = new ImageTexture("models/car.jpg");
+	Material* pMatMesh = new Lambertian(baseTexture);
+	//TriangleMesh* pMesh0 = new TriangleMesh("models/UVCube5.fbx", pMatMesh);
+	TriangleMesh* pMesh0 = new TriangleMesh("models/car.fbx", pMatMesh);
 
-	Texture* metalTexture = new ImageTexture("models/512.jpg");
-	Material* pMatMesh = new Metal(metalTexture, 0.2f);
-	TriangleMesh* pMesh0 = new TriangleMesh("models/deer.obj", pMatMesh);
-
-	vecHitables.push_back(pSphere0);
+	//vecHitables.push_back(pSphere0);
 	vecHitables.push_back(pSphere1);
-	vecHitables.push_back(pSphere2);
+	//vecHitables.push_back(pSphere2);
 	vecHitables.push_back(pSphere3);
 	vecHitables.push_back(pSphere4);
 	//vecHitables.push_back(pTriangle0);
@@ -66,7 +66,7 @@ void Scene::InitRandomScene()
 			float choose_mat = Helper::GetRandom01();
 
 			glm::vec3 center(a + 0.9f * Helper::GetRandom01(), 0.2, b + 0.9 * Helper::GetRandom01());
-			if ((center - glm::vec3(4, 0.2, 0)).length() > 0.9f)
+			if (glm::length((center - glm::vec3(4, 0.2, 0))) > 0.9f)
 			{
 				if (choose_mat < 0.8f)
 				{
diff --git a/RayTracer/Texture.cpp b/RayTracer/Texture.cpp
index 8a16a50..e63a72a 100644
--- a/RayTracer/Texture.cpp
+++ b/RayTracer/Texture.cpp
@@ -16,7 +16,7 @@ glm::vec3 ImageTexture::value(glm::vec2 uv) const
 	if (channels > 3)
 		return glm::vec3(1, 0, 0.8f);
 
-	int i = uv.x * width;
+	int i = (uv.x) * width;
 	int j = (1 - uv.y) * height;
 
 	if (i < 0) i = 0;
diff --git a/RayTracer/Transparent.h b/RayTracer/Transparent.h
index 88fd031..e1e106e 100644
--- a/RayTracer/Transparent.h
+++ b/RayTracer/Transparent.h
@@ -27,13 +27,13 @@ public:
 		{
 			outward_normal = -rec.N;  // because we want inverted image for refraction? 
 			ni_over_nt = refr_index;
-			cosine = refr_index * glm::dot(ray_direction, rec.N) / ray_direction.length();
+			cosine = refr_index * glm::dot(ray_direction, rec.N) / glm::length(ray_direction);
 		}
 		else
 		{
 			outward_normal = rec.N;
 			ni_over_nt = 1 / refr_index;
-			cosine = -glm::dot(ray_direction, rec.N) / ray_direction.length();
+			cosine = -glm::dot(ray_direction, rec.N) / glm::length(ray_direction);
 		}
 
 		if (Helper::Refract(ray_direction, outward_normal, ni_over_nt, refracted))
diff --git a/RayTracer/Triangle.cpp b/RayTracer/Triangle.cpp
index 8802a62..aae7a94 100644
--- a/RayTracer/Triangle.cpp
+++ b/RayTracer/Triangle.cpp
@@ -1,32 +1,72 @@
 
 #include "Triangle.h"
 
+//#define MOLLER_TRUMBORE
+
 /////////////////////////////////////////////////////////////////////////////////////////
 bool Triangle::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
 {
+	glm::vec3 rayDirection = r.GetRayDirection();
+	glm::vec3 rayOrigin = r.GetRayOrigin();
+
 	// Compute Plane Normal
-	glm::vec3 edge0 = V1 - V0;
-	glm::vec3 edge1 = V2 - V1;
-	glm::vec3 edge2 = V0 - V2;
+	glm::vec3 edge0 = v1.position - v0.position;
+	glm::vec3 edge1 = v2.position - v1.position;
+	glm::vec3 edge2 = v0.position - v2.position;
+
+	glm::vec3 barycentric;
+
+#ifdef MOLLER_TRUMBORE
+	glm::vec3 pvec = glm::cross(rayDirection, edge2);
+	float det = glm::dot(edge0, pvec);
 
+	if (fabs(det) < 0.0001f) 
+		return false;
+
+	float invDet = 1 / det;
+
+	glm::vec3 tvec = rayOrigin - v0.position;
+	barycentric.x = glm::dot(tvec, pvec) * invDet;
+
+	if (barycentric.x < 0 || barycentric.x > 1)
+		return false;
+
+	glm::vec3 qvec = glm::cross(tvec, edge0);
+	barycentric.y = glm::dot(rayDirection, qvec) * invDet;
+
+	if (barycentric.y < 0 || barycentric.x + barycentric.y > 1)
+		return false;
+
+	barycentric.z = 1 - barycentric.x - barycentric.y; //glm::dot(edge2, qvec) * invDet;
+
+	// Got barycentric, now calculate P,N & UV coordinates
+	// Record hit data!!!
+	rec.t = 100.0f;
+	rec.P = v0.position * barycentric.x + v1.position * barycentric.y + v2.position * barycentric.z;
+	rec.N = v0.normal * barycentric.x +   v1.normal * barycentric.y +   v2.normal * barycentric.z;
+	rec.uv =v0.uv * barycentric.x +       v1.uv * barycentric.y +       v2.uv * barycentric.z;
+	rec.mat_ptr = mat_ptr;
+
+	return true;
+#else
 	// NOTE that we are not normalizing the normal vector
 	// as we need to take it's area.
-	glm::vec3 NormalWithMagnitude = glm::cross(edge0, edge1);
-	float area = NormalWithMagnitude.length() / 2;
+	// cross product's magnitude is area of parallelogram formed by two vectors
+	glm::vec3 area = glm::cross(edge0, edge1);
+	float areaOfParellogram = glm::length(area);
 
 	// Normalize normal now!
-	glm::vec3 N = glm::normalize(NormalWithMagnitude);
-
-	glm::vec3 rayDirection = r.GetRayDirection();
-	glm::vec3 rayOrigin = r.GetRayOrigin();
+	// cross product's vector direction represents new vector perpendicular to 
+	// plane formed by those two vectors!
+	glm::vec3 N = glm::normalize(area);
 
 	// Check if ray & plane are parallel
-	float NDotRayDirection = glm::dot(N, rayDirection); 
+	float NDotRayDirection = glm::dot(N, rayDirection);
 	if (fabs(NDotRayDirection) < 0.001f)
 		return false;
 
 	// Compute plane distance from origin
-	float d = glm::dot(V0, N); 
+	float d = glm::dot(v0.position, N);
 
 	// Compute t at which intersection happens!
 	float t = (d - glm::dot(N, rayOrigin)) / NDotRayDirection;
@@ -39,9 +79,9 @@ bool Triangle::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
 
 	// Perform tests if this P is inside triangle or outside
 	glm::vec3 C;
-	glm::vec3 P0 = P - V0;
-	glm::vec3 P1 = P - V1;
-	glm::vec3 P2 = P - V2;
+	glm::vec3 P0 = P - v0.position;
+	glm::vec3 P1 = P - v1.position;
+	glm::vec3 P2 = P - v2.position;
 
 	glm::vec3 C0 = glm::cross(edge0, P0);
 	glm::vec3 C1 = glm::cross(edge1, P1);
@@ -49,18 +89,25 @@ bool Triangle::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
 
 	if (glm::dot(N, C0) >= 0 && glm::dot(N, C1) >= 0 && glm::dot(N, C2) >= 0)
 	{
+		float length0 = glm::length(C0);
+		float length1 = glm::length(C1);
+		barycentric.x = length0 / areaOfParellogram;
+		barycentric.y = length1 / areaOfParellogram;
+		barycentric.z = 1 - barycentric.x - barycentric.y;
+
 		// Record hit data!!!
 		rec.t = t;
 		rec.P = P;
 		rec.N = N;
-		rec.uv.x = (C1.length() * 0.5f) / area;
-		rec.uv.y = (C2.length() * 0.5f) / area;
+		rec.uv = barycentric.x * v2.uv + barycentric.y * v0.uv + barycentric.z * v1.uv;
 		rec.mat_ptr = mat_ptr;
 
 		return true;
 	}
 	else
 		return false;
+#endif
+	
 
 	//auto edge0 = V1 - V0;
 	//auto edge1 = V2 - V1;
diff --git a/RayTracer/Triangle.h b/RayTracer/Triangle.h
index bff4e89..8b735bc 100644
--- a/RayTracer/Triangle.h
+++ b/RayTracer/Triangle.h
@@ -2,25 +2,23 @@
 
 #include "glm\glm.hpp"
 #include "Hitable.h"
+#include "VertexStructures.h"
 
 class Material;
-struct VertexPNT;
 
 class Triangle : public Hitable
 {
 public:
 	Triangle() {}
-	Triangle(const glm::vec3& _v0, const glm::vec3& _v1, const glm::vec3& _v2, Material* ptr_mat) :
-		V0(_v0),
-		V1(_v1),
-		V2(_v2),
+	Triangle(const VertexPNT& _v0, const VertexPNT& _v1, const VertexPNT& _v2, Material* ptr_mat) :
+		v0(_v0), v1(_v1), v2(_v2),
 		mat_ptr(ptr_mat) {};
 
 	virtual bool hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const;
 
 private:
-	glm::vec3 V0;
-	glm::vec3 V1;
-	glm::vec3 V2;
+	VertexPNT v0;
+	VertexPNT v1;
+	VertexPNT v2;
 	Material* mat_ptr;
 };
diff --git a/RayTracer/TriangleMesh.cpp b/RayTracer/TriangleMesh.cpp
index 85c27a7..59a4035 100644
--- a/RayTracer/TriangleMesh.cpp
+++ b/RayTracer/TriangleMesh.cpp
@@ -54,29 +54,40 @@ void TriangleMesh::ProcessNode(aiNode* node, const aiScene* scene)
 
 void TriangleMesh::ProcessMesh(aiMesh* mesh, const aiScene* scene)
 {
-	std::vector<aiVector3D> vecVertices;
+	std::vector<VertexPNT> vecVertices;
 	vecVertices.reserve(mesh->mNumVertices);
 
 	for (unsigned int i = 0; i < mesh->mNumVertices; i++)
 	{
-		vecVertices.push_back(mesh->mVertices[i]);
-		m_ptrAABB->UpdateBB(glm::vec3(mesh->mVertices[i].x, mesh->mVertices[i].y, mesh->mVertices[i].z));
+		VertexPNT vertex;
+
+		vertex.position = glm::vec3(mesh->mVertices[i].x, mesh->mVertices[i].y, mesh->mVertices[i].z);
+		vertex.normal = glm::vec3(mesh->mNormals[i].x, mesh->mNormals[i].y, mesh->mNormals[i].z);
+
+		if (mesh->mTextureCoords[0])
+		{
+			//vertex.uv = glm::clamp(glm::vec2(mesh->mTextureCoords[0][i].x, mesh->mTextureCoords[0][i].y), 0.0f, 1.0f);
+			vertex.uv = glm::vec2(mesh->mTextureCoords[0][i].x, mesh->mTextureCoords[0][i].y);
+		}
+		
+		vecVertices.push_back(vertex);
+		m_ptrAABB->UpdateBB(vertex.position);
 	}
 
 	for (unsigned int i = 0; i < mesh->mNumFaces; i++)
 	{
-		aiFace* face = &(mesh->mFaces[i]);
-		int numIndices = face->mNumIndices;
+		aiFace face = mesh->mFaces[i];
+		int numIndices = face.mNumIndices;
 
-		unsigned int index0 = face->mIndices[0];
-		unsigned int index1 = face->mIndices[1]; 
-		unsigned int index2 = face->mIndices[2];
+		unsigned int index0 = face.mIndices[0];
+		unsigned int index1 = face.mIndices[1]; 
+		unsigned int index2 = face.mIndices[2];
 
-		glm::vec3 pos0(vecVertices.at(index0).x, vecVertices.at(index0).y, vecVertices.at(index0).z);
-		glm::vec3 pos1(vecVertices.at(index1).x, vecVertices.at(index1).y, vecVertices.at(index1).z);
-		glm::vec3 pos2(vecVertices.at(index2).x, vecVertices.at(index2).y, vecVertices.at(index2).z);
+		VertexPNT vert0 = vecVertices.at(index0);
+		VertexPNT vert1 = vecVertices.at(index1);
+		VertexPNT vert2 = vecVertices.at(index2);
 
-		Triangle* tri = new Triangle(pos0, pos1, pos2, m_ptrMaterial);
+		Triangle* tri = new Triangle(vert0, vert1, vert2, m_ptrMaterial);
 
 		m_vecTriangles.push_back(tri);
 	}
diff --git a/RayTracer/VertexStructures.h b/RayTracer/VertexStructures.h
index 7fea28c..0012dd2 100644
--- a/RayTracer/VertexStructures.h
+++ b/RayTracer/VertexStructures.h
@@ -5,7 +5,7 @@
 /////////////////////////////////////////////////////////////////////////////////////////
 struct VertexP
 {
-	VertexP() {}
+	VertexP() { position = glm::vec3(0); }
 	VertexP(const glm::vec3& _pos) : position(_pos) {}
 
 	glm::vec3 position;
@@ -14,7 +14,12 @@ struct VertexP
 /////////////////////////////////////////////////////////////////////////////////////////
 struct VertexPN
 {
-	VertexPN() {}
+	VertexPN()
+	{ 
+		position = glm::vec3(0);
+		normal = glm::vec3(0);
+	}
+
 	VertexPN(const glm::vec3& _pos, const glm::vec3& _normal) :	
 		position(_pos),
 		normal(_normal) {}
@@ -26,13 +31,19 @@ struct VertexPN
 /////////////////////////////////////////////////////////////////////////////////////////
 struct VertexPNT
 {
-	VertexPNT() {}
-	VertexPNT(const glm::vec3& _pos, const glm::vec3& _normal, const glm::vec3 _uv) :
+	VertexPNT() 
+	{
+		position = glm::vec3(0);
+		normal = glm::vec3(0);
+		uv = glm::vec2(0);
+	}
+
+	VertexPNT(const glm::vec3& _pos, const glm::vec3& _normal, const glm::vec2 _uv) :
 		position(_pos),
 		normal(_normal),
 		uv(_uv) {}
 
 	glm::vec3 position;
 	glm::vec3 normal;
-	glm::vec3 uv;
+	glm::vec2 uv;
 };
diff --git a/WindowsRayTracer.cpp b/WindowsRayTracer.cpp
index 6f18efe..c271851 100644
--- a/WindowsRayTracer.cpp
+++ b/WindowsRayTracer.cpp
@@ -27,7 +27,7 @@
 const int COLOR_CHANNELS = 3; // RGB
 const int gBackbufferWidth = 480;
 const int gBackbufferHeight = 270;
-const int nSamples = 5;
+const int nSamples = 1;
 
 unsigned long long int numRays = 0;
 
```

