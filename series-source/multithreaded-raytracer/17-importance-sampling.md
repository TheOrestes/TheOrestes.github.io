# Post 17 â€” Importance sampling: the failed attempt, then the real one

## `44dd135` â€” 2020-04-11 _(OpenGL branch)_

> Failed attempt at Importance Sampling, added other minor tweaks.

```diff
diff --git a/ClassDiagram.cd b/ClassDiagram.cd
new file mode 100644
index 0000000..77c376d
--- /dev/null
+++ b/ClassDiagram.cd
@@ -0,0 +1,263 @@
+ï»¿<?xml version="1.0" encoding="utf-8"?>
+<ClassDiagram MajorVersion="1" MinorVersion="1">
+  <Class Name="AABB" Collapsed="true">
+    <Position X="9.75" Y="0.5" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AAACAAAAAAIAAgAAABAAAAACgAAAAAAAAAACAEAAAgA=</HashCode>
+      <FileName>RayTracer\AABB.h</FileName>
+    </TypeIdentifier>
+  </Class>
+  <Class Name="Camera" Collapsed="true">
+    <Position X="13.25" Y="0.5" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AAACAgAAAACAgAgAQAgAIAAAAAAAAABABBoEQIAgAAI=</HashCode>
+      <FileName>RayTracer\Camera.h</FileName>
+    </TypeIdentifier>
+  </Class>
+  <Class Name="Emissive" Collapsed="true">
+    <Position X="5" Y="4.75" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AABAAAAAAAgAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAA=</HashCode>
+      <FileName>RayTracer\Emissive.h</FileName>
+    </TypeIdentifier>
+  </Class>
+  <Class Name="Hitable" Collapsed="true">
+    <Position X="3.75" Y="6.5" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AAAAAAAAAAAAAgAAAAAAAAAAACAAAAAAAAAAAAAAAAA=</HashCode>
+      <FileName>RayTracer\Hitable.h</FileName>
+    </TypeIdentifier>
+  </Class>
+  <Class Name="Lambertian" Collapsed="true">
+    <Position X="0.5" Y="4.75" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AABAAAAAAAAAAABAAAAAAAAAAAAAAAACAAAAAAAAAAA=</HashCode>
+      <FileName>RayTracer\Lambertian.h</FileName>
+    </TypeIdentifier>
+  </Class>
+  <Class Name="BVHTree" Collapsed="true">
+    <Position X="0.5" Y="7.75" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AAAQCAIAAAARAgAAIAIAAAAAACAAAAAAAAACABAIACA=</HashCode>
+      <FileName>RayTracer\LameBVH.h</FileName>
+    </TypeIdentifier>
+  </Class>
+  <Class Name="Material" Collapsed="true">
+    <Position X="3.75" Y="3.5" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AABAAAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAA=</HashCode>
+      <FileName>RayTracer\Material.h</FileName>
+    </TypeIdentifier>
+  </Class>
+  <Class Name="Metal" Collapsed="true">
+    <Position X="7.25" Y="4.75" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AABAAAAAAAAAAABAAAAAAAAAgAgAAAAAAAAAAAAAAAA=</HashCode>
+      <FileName>RayTracer\Metal.h</FileName>
+    </TypeIdentifier>
+  </Class>
+  <Class Name="Ray" Collapsed="true">
+    <Position X="13.25" Y="1.5" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>CAAAAAAAQAAAKAAAAAAAAAAAAAAAAAAAAAACAAAAAAA=</HashCode>
+      <FileName>RayTracer\Ray.h</FileName>
+    </TypeIdentifier>
+  </Class>
+  <Class Name="Sampler" Collapsed="true">
+    <Position X="2.75" Y="9.5" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AACAAAAAAAgAIwACAAAABAAIAAAAAABQAAAgAAAARAA=</HashCode>
+      <FileName>RayTracer\Sampler.h</FileName>
+    </TypeIdentifier>
+  </Class>
+  <Class Name="RandomSampler" Collapsed="true">
+    <Position X="0.5" Y="10.75" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>QAAAAAAAAAAAAAACAAAAAAAAAAAAAAAAAAAAAAEAAAA=</HashCode>
+      <FileName>RayTracer\Sampler.h</FileName>
+    </TypeIdentifier>
+  </Class>
+  <Class Name="RegularSampler" Collapsed="true">
+    <Position X="2.75" Y="10.75" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AAAAAAAAAAAAAAACAAAAAAAAAAAAAYAAAAAAAAAAAAA=</HashCode>
+      <FileName>RayTracer\Sampler.h</FileName>
+    </TypeIdentifier>
+  </Class>
+  <Class Name="JitteredSampler" Collapsed="true">
+    <Position X="5" Y="10.75" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AAAAAAAAAAAAAAACAAAAAAAAIAAAAAAAAAAAAAAAEAA=</HashCode>
+      <FileName>RayTracer\Sampler.h</FileName>
+    </TypeIdentifier>
+  </Class>
+  <Class Name="Scene" Collapsed="true">
+    <Position X="9.75" Y="2.5" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AAMAACBAAEAAAEAggAABAAAAQAAAADAAgAAAAAAAAAA=</HashCode>
+      <FileName>RayTracer\Scene.h</FileName>
+    </TypeIdentifier>
+  </Class>
+  <Class Name="Sphere" Collapsed="true">
+    <Position X="2.75" Y="7.75" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AAgAAAAACAAgAgAAAASAAAAAACAAAAAAAAAAAAAAAAA=</HashCode>
+      <FileName>RayTracer\Sphere.h</FileName>
+    </TypeIdentifier>
+  </Class>
+  <Class Name="Texture" Collapsed="true">
+    <Position X="3.75" Y="0.5" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAAAAAAAAAAAA=</HashCode>
+      <FileName>RayTracer\Texture.h</FileName>
+    </TypeIdentifier>
+  </Class>
+  <Class Name="ConstantTexture" Collapsed="true">
+    <Position X="7.25" Y="1.75" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AAAgAAAAAAAAAAAAAAAAAAAAAAAAACCAAAAAAAAAAAA=</HashCode>
+      <FileName>RayTracer\Texture.h</FileName>
+    </TypeIdentifier>
+  </Class>
+  <Class Name="CheckeredTexture" Collapsed="true">
+    <Position X="0.5" Y="1.75" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AAAAAAAAAAAAAAAAAAAAAAAAAAAAACDAAAAAAAAAAgA=</HashCode>
+      <FileName>RayTracer\Texture.h</FileName>
+    </TypeIdentifier>
+  </Class>
+  <Class Name="HDRITexture" Collapsed="true">
+    <Position X="2.75" Y="1.75" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AAAAAAQAAAAAAAQAQAACAAAAAAAAACCAAQAQAAAAAAA=</HashCode>
+      <FileName>RayTracer\Texture.h</FileName>
+    </TypeIdentifier>
+  </Class>
+  <Class Name="ImageTexture" Collapsed="true">
+    <Position X="5" Y="1.75" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AAAAAAAAAAAAAAQARAACAAAAAAAAACCAAQAQAAAAAAA=</HashCode>
+      <FileName>RayTracer\Texture.h</FileName>
+    </TypeIdentifier>
+  </Class>
+  <Class Name="Transparent" Collapsed="true">
+    <Position X="2.75" Y="4.75" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AABAAEAAAABAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAA=</HashCode>
+      <FileName>RayTracer\Transparent.h</FileName>
+    </TypeIdentifier>
+  </Class>
+  <Class Name="Triangle" Collapsed="true">
+    <Position X="5" Y="7.75" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AAAAAAAAAAAAAoABAICAAAAAADQAAAAAAAIAAAAAAAA=</HashCode>
+      <FileName>RayTracer\Triangle.h</FileName>
+    </TypeIdentifier>
+  </Class>
+  <Class Name="TriangleMesh" Collapsed="true">
+    <Position X="7.25" Y="7.75" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AAEIAAABABAAAgAAAIAIAAAAwCAAAAAAEAAAAIAAEEE=</HashCode>
+      <FileName>RayTracer\TriangleMesh.h</FileName>
+    </TypeIdentifier>
+  </Class>
+  <Class Name="Application" Collapsed="true">
+    <Position X="11.5" Y="0.5" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>EIAABAAACBEAAQSAAJAAAkBCAIACgBgAKSEAgBAggBE=</HashCode>
+      <FileName>Main\Application.h</FileName>
+    </TypeIdentifier>
+  </Class>
+  <Class Name="GLSLShader" Collapsed="true">
+    <Position X="9.75" Y="1.5" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AIDAAAAAAAAAAAAAACCAAAAAAAAEAAAAAAAAAAAAgAA=</HashCode>
+      <FileName>Main\GLSLShader.h</FileName>
+    </TypeIdentifier>
+  </Class>
+  <Class Name="Profiler" Collapsed="true">
+    <Position X="11.5" Y="1.5" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AAAAAAAAAAAAAAQAAAAAAAABAAAAAAQAEAACAAAAAAQ=</HashCode>
+      <FileName>Main\Profiler.h</FileName>
+    </TypeIdentifier>
+  </Class>
+  <Class Name="ScreenAlignedQuad" Collapsed="true">
+    <Position X="11.5" Y="2.5" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>ABAAAoAAAEAAAFAAAAAMAQAAAAAAEoAAABACAAAAAAA=</HashCode>
+      <FileName>Main\ScreenAlignedQuad.h</FileName>
+    </TypeIdentifier>
+  </Class>
+  <Struct Name="HitRecord" Collapsed="true">
+    <Position X="11.5" Y="3.75" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AACAAAAAAAQAAAAgAACAAAAAAAACAAACAAQAABBAAgA=</HashCode>
+      <FileName>RayTracer\Hitable.h</FileName>
+    </TypeIdentifier>
+  </Struct>
+  <Struct Name="BVHNode" Collapsed="true">
+    <Position X="9.75" Y="3.75" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AgAAEAAAAAAAAAEABAAAAAABABAAAAAAACCAAAAAAAA=</HashCode>
+      <FileName>RayTracer\LameBVH.h</FileName>
+    </TypeIdentifier>
+  </Struct>
+  <Struct Name="VertexP" Collapsed="true">
+    <Position X="13.25" Y="3.75" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AAAAAAAAAAAAAAAAAAABIAAAAAAAAAAAAAAAAAAAAAA=</HashCode>
+      <FileName>Main\VertexStructures.h</FileName>
+    </TypeIdentifier>
+  </Struct>
+  <Struct Name="VertexPC" Collapsed="true">
+    <Position X="9.75" Y="4.75" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AAAAAAAAAAAACAAAAAAAIAAAAAAAAACAAAAAAAAAAAA=</HashCode>
+      <FileName>Main\VertexStructures.h</FileName>
+    </TypeIdentifier>
+  </Struct>
+  <Struct Name="VertexPT" Collapsed="true">
+    <Position X="9.75" Y="5.75" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AAAAAAAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAAAAAEgA=</HashCode>
+      <FileName>Main\VertexStructures.h</FileName>
+    </TypeIdentifier>
+  </Struct>
+  <Struct Name="VertexPN" Collapsed="true">
+    <Position X="11.5" Y="4.75" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AAAAAAAAAAAAAAQAAAAAIAgAAAAAAAAAAAAAAAAAAAA=</HashCode>
+      <FileName>Main\VertexStructures.h</FileName>
+    </TypeIdentifier>
+  </Struct>
+  <Struct Name="VertexPNT" Collapsed="true">
+    <Position X="13.25" Y="4.75" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AAAAAAAAAAAAAAQAAAAAIAgAAAAAAAAAAAAAAAAAAgA=</HashCode>
+      <FileName>Main\VertexStructures.h</FileName>
+    </TypeIdentifier>
+  </Struct>
+  <Struct Name="VertexPTNBT" Collapsed="true">
+    <Position X="11.5" Y="5.75" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AAAAAAAAAAAAQAAAAAAAIAgAAAAAAAAgAAAAAgAAAgA=</HashCode>
+      <FileName>Main\VertexStructures.h</FileName>
+    </TypeIdentifier>
+  </Struct>
+  <Enum Name="eLongestAxis" Collapsed="true">
+    <Position X="9.75" Y="7" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AAAABAAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAEAAAAAA=</HashCode>
+      <FileName>RayTracer\AABB.h</FileName>
+    </TypeIdentifier>
+  </Enum>
+  <Enum Name="eProjectionType" Collapsed="true">
+    <Position X="11.5" Y="7" Width="1.5" />
+    <TypeIdentifier>
+      <HashCode>AAAAAAAABAAAAAAIAAAAAAAAAAAAAAAAQAEAAAAAAAA=</HashCode>
+      <FileName>RayTracer\Camera.h</FileName>
+    </TypeIdentifier>
+  </Enum>
+  <Font Name="Segoe UI" Size="9" />
+</ClassDiagram>
\ No newline at end of file
diff --git a/Main/Application.cpp b/Main/Application.cpp
index 77e3a2d..4a3dfa1 100644
--- a/Main/Application.cpp
+++ b/Main/Application.cpp
@@ -200,12 +200,12 @@ glm::vec3 Application::TraceColor(const Ray & r, int depth, int& rayCount)
 	{
 		Ray scatteredRay;
 
-		glm::vec3 attenuation = glm::vec3(0.0f, 0.0f, 0.0f);
+		glm::vec3 albedo = glm::vec3(0.0f, 0.0f, 0.0f);
 		glm::vec3 emitted = rec.mat_ptr->Emitted(rec.uv);
 
-		if (depth < 50 && rec.mat_ptr->Scatter(r, rec, rayCount, attenuation, scatteredRay))
+		if (depth < 50 && rec.mat_ptr->Scatter(r, rec, rayCount, albedo, scatteredRay))
 		{
-			traceColor = emitted + (attenuation * (TraceColor(scatteredRay, depth + 1, rayCount)));
+			traceColor = emitted + (albedo * TraceColor(scatteredRay, depth + 1, rayCount));
 		}
 		else
 		{
diff --git a/RayTracer/Camera.cpp b/RayTracer/Camera.cpp
index b7d6054..dbfc297 100644
--- a/RayTracer/Camera.cpp
+++ b/RayTracer/Camera.cpp
@@ -55,7 +55,7 @@ void Camera::InitCamera(const glm::vec3& _position, const glm::vec3& _lookAt, fl
 			// or
 			// d = screenHeight / 2 * tan(fov/2)
 			// We will be using "d" for the sake of it. 
-			viewPlaneDistance = 400.0f;
+			viewPlaneDistance = 600.0f;
 			break;
 		}
 
diff --git a/RayTracer/DiffuseLight.h b/RayTracer/Emissive.h
similarity index 60%
rename from RayTracer/DiffuseLight.h
rename to RayTracer/Emissive.h
index 6b37b79..ba1898f 100644
--- a/RayTracer/DiffuseLight.h
+++ b/RayTracer/Emissive.h
@@ -5,19 +5,24 @@
 #include "Material.h"
 #include "Texture.h"
 
-class DiffuseLight : public Material
+class Emissive : public Material
 {
 public:
-	DiffuseLight(Texture* _emission)
+	Emissive(Texture* _emission)
 	{
 		Emission = _emission;
 	}
 
-	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& attenuation, Ray& scatterd) const
+	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& albedo, Ray& scatterd) const
 	{
 		return false;
 	}
 
+	virtual float PDF(const Ray& r_in, const HitRecord& rec, const Ray& scatterd) const
+	{
+		return 1.0f;
+	}
+
 	virtual glm::vec3 Emitted(const glm::vec2& uv) const
 	{
 		return Emission->value(uv);
diff --git a/RayTracer/Lambertian.cpp b/RayTracer/Lambertian.cpp
index a977d04..cea632e 100644
--- a/RayTracer/Lambertian.cpp
+++ b/RayTracer/Lambertian.cpp
@@ -2,12 +2,13 @@
 #include "Lambertian.h"
 #include "Helper.h"
 
-bool Lambertian::Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& attenuation, Ray& scatterd) const
+bool Lambertian::Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& albedo, Ray& scatterd) const
 {
 	glm::vec3 target = rec.P + rec.N + Helper::RandomUnitVector();
+
 	scatterd = Ray(rec.P, target - rec.P);
 	++rayCount;
 
-	attenuation = Albedo->value(rec.uv);
+	albedo = Albedo->value(rec.uv);
 	return true;
-}
\ No newline at end of file
+}
diff --git a/RayTracer/Lambertian.h b/RayTracer/Lambertian.h
index aceba69..c062fe0 100644
--- a/RayTracer/Lambertian.h
+++ b/RayTracer/Lambertian.h
@@ -10,7 +10,7 @@ class Lambertian : public Material
 public:
 	Lambertian(Texture* _albedo) : Albedo(_albedo) {}
 
-	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& attenuation, Ray& scatterd) const;
+	virtual bool	Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& albedo, Ray& scatterd) const;
 
 private:
 	Texture* Albedo;
diff --git a/RayTracer/Material.h b/RayTracer/Material.h
index def6cbb..80d3754 100644
--- a/RayTracer/Material.h
+++ b/RayTracer/Material.h
@@ -6,9 +6,6 @@
 class Material
 {
 public:
-	virtual bool	  Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& attenuation, Ray& scattered) const = 0;
-	virtual glm::vec3 Emitted(const glm::vec2& uv) const
-	{
-		return glm::vec3(0, 0, 0);
-	}
+	virtual bool		Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& albedo, Ray& scattered) const = 0;
+	virtual glm::vec3	Emitted(const glm::vec2& uv) const { return glm::vec3(0); }
 };
diff --git a/RayTracer/Metal.cpp b/RayTracer/Metal.cpp
index 950519b..3f29136 100644
--- a/RayTracer/Metal.cpp
+++ b/RayTracer/Metal.cpp
@@ -2,12 +2,12 @@
 #include "Metal.h"
 #include "Helper.h"
 
-bool Metal::Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& attenuation, Ray& scatterd) const
+bool Metal::Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& albedo, Ray& scatterd) const
 {
 	glm::vec3 target = glm::normalize(Helper::Reflect(r_in.direction, rec.N));
 	scatterd = Ray(rec.P, target + fuzz * Helper::RandomInUnitSphere());
 	++rayCount;
 
-	attenuation = Albedo->value(rec.uv);
+	albedo = Albedo->value(rec.uv);
 	return (glm::dot(scatterd.direction, rec.N) > 0);
-}
\ No newline at end of file
+}
diff --git a/RayTracer/Scene.cpp b/RayTracer/Scene.cpp
index f07444a..f36f3bc 100644
--- a/RayTracer/Scene.cpp
+++ b/RayTracer/Scene.cpp
@@ -4,7 +4,7 @@
 #include "Sphere.h"
 #include "FlatColor.h"
 #include "Lambertian.h"
-#include "DiffuseLight.h"
+#include "Emissive.h"
 #include "Metal.h"
 #include "Transparent.h"
 #include "Texture.h"
@@ -53,16 +53,16 @@ void Scene::InitSphereScene(float screenWidth, float screenHeight)
 	CheckeredTexture* checksTexture = new CheckeredTexture(glm::vec3(0.2f, 0.9f, 0.5f), glm::vec3(0.03f), 10.0f, 10.0f);
 	glm::vec4 glassColor = glm::vec4(1, 1, 0, 1);
 
-	Sphere* pSphereGlass1 = new Sphere(glm::vec3(-4.0f, 0.4f, 0.0f), 1.0f, new Transparent(new ConstantTexture(glassColor), 1.5f));
-	Sphere* pSphereMetal = new Sphere(glm::vec3(3.5f, 0.5f, 0.0f), 1.0f, new Metal(checksTexture, 0.1f));
-	Sphere* pSphereLight = new Sphere(glm::vec3(-1.5f, 0.5f, 0.0f), 0.75f, new DiffuseLight(new ConstantTexture(glm::vec3(1.0f, 1.0f, 1.0f))));
+	//Sphere* pSphereGlass1 = new Sphere(glm::vec3(-4.0f, 0.4f, 0.0f), 1.0f, new Transparent(new ConstantTexture(glassColor), 1.5f));
+	//Sphere* pSphereMetal = new Sphere(glm::vec3(3.5f, 0.5f, 0.0f), 1.0f, new Metal(checksTexture, 0.1f));
+	Sphere* pSphereLight = new Sphere(glm::vec3(-1.5f, 0.5f, 0.0f), 0.75f, new Emissive(new ConstantTexture(glm::vec3(1.0f, 1.0f, 1.0f))));
 	Sphere* pSphereEarth = new Sphere(glm::vec3(0.5f, 0.0f, 0.0f), 0.5, new Lambertian(new ImageTexture("models/earth.jpg")));
 
 	//Profiler::getInstance().WriteToProfiler("Triangle Count:", pMesh0->GetTriangleCount());
 
 	vecHitables.push_back(pSphereGround);
-	vecHitables.push_back(pSphereGlass1);
-	vecHitables.push_back(pSphereMetal);
+	//vecHitables.push_back(pSphereGlass1);
+	//vecHitables.push_back(pSphereMetal);
 	vecHitables.push_back(pSphereEarth);
 	vecHitables.push_back(pSphereLight);
 }
@@ -119,7 +119,7 @@ void Scene::InitTigerScene(float screenWidth, float screenHeight)
 
 	//Sphere* pSphereGlass1 = new Sphere(glm::vec3(-4.0f, 0.4f, 0.0f), 1.0f, new Transparent(1.3f));
 	Sphere* pSphereMetal = new Sphere(glm::vec3(3.5f, 0.5f, 0.0f), 1.0f, new Metal(new ConstantTexture(glm::vec3(1.0f, 0.1f, 0.0f)), 0.1f));
-	//Sphere* pSphereLight = new Sphere(glm::vec3(-1.5f, 0.5f, 1.25f), 1.0f, new DiffuseLight(new ConstantTexture(glm::vec3(1.0f, 1.0f, 1.0f))));
+	//Sphere* pSphereLight = new Sphere(glm::vec3(-1.5f, 0.5f, 1.25f), 1.0f, new Emissive(new ConstantTexture(glm::vec3(1.0f, 1.0f, 1.0f))));
 	Sphere* pSphereEarth = new Sphere(glm::vec3(2.5f, 0.0f, 0.0f), 0.5, new Lambertian(new ImageTexture("models/earth.jpg")));
 	
 	//MeshInfo barbInfo;
@@ -138,7 +138,7 @@ void Scene::InitTigerScene(float screenWidth, float screenHeight)
 	glassTigerInfo.scale = glm::vec3(0.75f);
 	glassTigerInfo.matInfo.albedoColor = glm::vec4(0.3f, 0.8f, 1.0f, 1);
 	glassTigerInfo.matInfo.refrIndex = 1.4f;
-	//TriangleMesh* pGlassTiger = new TriangleMesh(glassTigerInfo);
+	TriangleMesh* pGlassTiger = new TriangleMesh(glassTigerInfo);
 
 	// Light Quad
 	MeshInfo lightInfo;
@@ -171,14 +171,14 @@ void Scene::InitTigerScene(float screenWidth, float screenHeight)
 	//vecHitables.push_back(pSphereLight);
 	vecHitables.push_back(pBase);
 	vecHitables.push_back(pLight);
-	//vecHitables.push_back(pGlassTiger);
+	vecHitables.push_back(pGlassTiger);
 }
 
 ///////////////////////////////////////////////////////////////////////////////////////////////////
 void Scene::InitCornellScene(float screenWidth, float screenHeight)
 {
 	// Initialize Camera first...!!!
-	glm::vec3 cameraPosition = glm::vec3(0.0f, 2.5f, 6.5f);
+	glm::vec3 cameraPosition = glm::vec3(0.0f, 2.5f, 8.5f);
 	glm::vec3 cameraLookAt = glm::vec3(0.0f, 2.5f, 0.0f);
 	m_pCamera = new Camera();
 	m_pCamera->InitCamera(cameraPosition, cameraLookAt, screenWidth, screenHeight);
@@ -187,7 +187,7 @@ void Scene::InitCornellScene(float screenWidth, float screenHeight)
 	m_colMiss = glm::vec4(0.0f);
 	
 	glm::vec4 glassColor = glm::vec4(0, 1, 0, 1);
-	Sphere* pSphereGlass = new Sphere(glm::vec3(-1.0f, 0.5f, 1.0f), 0.5f, new Transparent(new ConstantTexture(glassColor), 1.4f));
+	Sphere* pSphereGlass = new Sphere(glm::vec3(-1.0f, 0.5f, 1.0f), 0.5f, new Lambertian(new ConstantTexture(glassColor)));
 
 	// Room Mesh
 	MeshInfo roomInfo;
@@ -196,27 +196,40 @@ void Scene::InitCornellScene(float screenWidth, float screenHeight)
 	roomInfo.leafSize = 10;
 	TriangleMesh* pRoom = new TriangleMesh(roomInfo);
 
-	// Cube 1
+	// Cube Left Big
 	MeshInfo cubeLeftInfo;
-	cubeLeftInfo.filePath = "models/CubePhong.fbx";
+	cubeLeftInfo.filePath = "models/Cube.fbx";
 	cubeLeftInfo.isLightSource = false;
 	cubeLeftInfo.leafSize = 12;
-	cubeLeftInfo.position = glm::vec3(1.0f, 1.8f, -1.35f);
+	cubeLeftInfo.position = glm::vec3(0.8f, 1.5f, -1.1f);
 	cubeLeftInfo.rotationAxis = glm::vec3(0, 1, 0);
-	cubeLeftInfo.rotationAngle = 9.0f;
-	cubeLeftInfo.scale = glm::vec3(1.6f, 3.6f, 1.6f);
-	cubeLeftInfo.matInfo.albedoColor = glm::vec4(1,1,1,1);
-	cubeLeftInfo.matInfo.roughness = 0.5f;
+	cubeLeftInfo.rotationAngle = -20.0f;
+	cubeLeftInfo.scale = glm::vec3(1.6f, 3.0f, 1.6f);
+	//cubeLeftInfo.matInfo.albedoColor = glm::vec4(1,1,1,1);
+	//cubeLeftInfo.matInfo.roughness = 0.5f;
 	TriangleMesh* pLeftCube = new TriangleMesh(cubeLeftInfo);
 
+	// Cube Right Small
+	MeshInfo cubeRightInfo;
+	cubeRightInfo.filePath = "models/Cube.fbx";
+	cubeRightInfo.isLightSource = false;
+	cubeRightInfo.leafSize = 12;
+	cubeRightInfo.position = glm::vec3(-0.8f, 0.7f, 1.5f);
+	cubeRightInfo.rotationAxis = glm::vec3(0, 1, 0);
+	cubeRightInfo.rotationAngle = 20.0f;
+	cubeRightInfo.scale = glm::vec3(1.4f, 1.4f, 1.4f);
+	//cubeRightInfo.matInfo.albedoColor = glm::vec4(1,1,1,1);
+	//cubeRightInfo.matInfo.roughness = 0.5f;
+	TriangleMesh* pRightCube = new TriangleMesh(cubeRightInfo);
+
 	// Light Quad
 	MeshInfo lightInfo;
 	lightInfo.filePath = "models/Quad.fbx";
 	lightInfo.isLightSource = true;
 	lightInfo.leafSize = 2;
 	lightInfo.position = glm::vec3(0, 4.99f, 0.5f);
-	lightInfo.scale = glm::vec3(2);
-	lightInfo.matInfo.albedoColor = glm::vec4(glm::vec3(1.5f), 1);
+	lightInfo.scale = glm::vec3(1.2);
+	lightInfo.matInfo.albedoColor = glm::vec4(glm::vec3(15.0f), 1);
 	TriangleMesh* pLight = new TriangleMesh(lightInfo);
 
 	// Glass Mesh
@@ -234,6 +247,7 @@ void Scene::InitCornellScene(float screenWidth, float screenHeight)
 	vecHitables.push_back(pLight);
 	vecHitables.push_back(pRoom);
 	vecHitables.push_back(pLeftCube);
+	vecHitables.push_back(pRightCube);
 	vecHitables.push_back(pSphereGlass);
 	//vecHitables.push_back(pGlassTiger);
 
@@ -334,7 +348,7 @@ void Scene::InitRandomScene(float screenWidth, float screenHeight)
 ////////////////////////////////////////////////////////////////////////////////////////////////////
 glm::vec4 Scene::CalculateMissColor(glm::vec3 rayDirection)
 {
-	return glm::vec4(0.3f, 0.3f, 0.3f, 1.0f);
+	return m_colMiss;
 }
 
 ///////////////////////////////////////////////////////////////////////////////////////////////////
diff --git a/RayTracer/Transparent.cpp b/RayTracer/Transparent.cpp
new file mode 100644
index 0000000..db1c3db
--- /dev/null
+++ b/RayTracer/Transparent.cpp
@@ -0,0 +1,67 @@
+
+#include "Transparent.h"
+#include "Helper.h"
+
+/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+bool Transparent::Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& albedo, Ray& scattered) const
+{
+	glm::vec3 outward_normal;
+	glm::vec3 ray_direction = r_in.direction;
+
+	glm::vec3 reflected = Helper::Reflect(ray_direction, rec.N);
+	float ni_over_nt;
+	albedo = Albedo->value(rec.uv);
+
+	glm::vec3 refracted = glm::vec3(0.0f, 0.0f, 0.0f);
+	float reflect_prob;
+	float cosine;
+
+	// When ray shoots through object back into vacuum,
+	// ni_over_nt = refr_idx, surface normal has to be inverted!
+	if (glm::dot(ray_direction, rec.N) > 0)
+	{
+		outward_normal = -rec.N;
+		ni_over_nt = refr_index;
+		cosine = refr_index * glm::dot(ray_direction, rec.N) / glm::length(ray_direction);
+	}
+	// When ray shoots into the object, 
+	// ni_over_nt = 1 / refr_idx
+	else
+	{
+		outward_normal = rec.N;
+		ni_over_nt = 1 / refr_index;
+		cosine = -glm::dot(ray_direction, rec.N) / glm::length(ray_direction);
+	}
+
+	if (Helper::Refract(ray_direction, outward_normal, ni_over_nt, refracted))
+	{
+		reflect_prob = Helper::schlick(cosine, refr_index);
+	}
+	else
+	{
+		reflect_prob = 1.0f;
+	}
+
+	// this logic is not clear? 
+	// Both reflection and refraction of the light occur for dielectric material, but we can only 
+	// pick 1 scattered ray for next iteration of ray tracing. Since we are shooting multiple rays 
+	// per pixel (multi-sampling) and average the traced color as final pixel color, we can use the 
+	// same idea to get the averaged result through both reflectiona and refraction.
+
+	// Now we generate a random number between 0.0 and 1.0. If it’s smaller than reflective coefficient, 
+	// the scattered ray is recorded as reflected; If it’s bigger than reflective coefficient, 
+	// the scattered ray is recorded as refracted.
+	if (Helper::GetRandom01() < reflect_prob)
+	{
+		scattered = Ray(rec.P, reflected);
+	}
+	else
+	{
+		scattered = Ray(rec.P, refracted);
+	}
+
+	++rayCount;
+
+	return true;
+}
+
diff --git a/RayTracer/Transparent.h b/RayTracer/Transparent.h
index f2f3a24..fa79359 100644
--- a/RayTracer/Transparent.h
+++ b/RayTracer/Transparent.h
@@ -4,73 +4,13 @@
 #include "Hitable.h"
 #include "Helper.h"
 #include "Material.h"
+#include "Texture.h"
 
 class Transparent : public Material
 {
 public:
 	Transparent(Texture* _albedo, float ri) : Albedo(_albedo), refr_index(ri) {}
-
-	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& attenuation, Ray& scattered) const
-	{
-		glm::vec3 outward_normal;
-		glm::vec3 ray_direction = r_in.direction;
-		
-		glm::vec3 reflected = Helper::Reflect(ray_direction, rec.N);
-		float ni_over_nt;
-		attenuation = Albedo->value(rec.uv);
-
-		glm::vec3 refracted = glm::vec3(0.0f, 0.0f, 0.0f);
-		float reflect_prob;
-		float cosine;
-
-		// When ray shoots through object back into vacuum,
-		// ni_over_nt = refr_idx, surface normal has to be inverted!
-		if (glm::dot(ray_direction, rec.N) > 0)
-		{
-			outward_normal = -rec.N;  
-			ni_over_nt = refr_index;
-			cosine = refr_index * glm::dot(ray_direction, rec.N) / glm::length(ray_direction);
-		}
-		// When ray shoots into the object, 
-		// ni_over_nt = 1 / refr_idx
-		else
-		{
-			outward_normal = rec.N;
-			ni_over_nt = 1 / refr_index;
-			cosine = -glm::dot(ray_direction, rec.N) / glm::length(ray_direction);
-		}
-
-		if (Helper::Refract(ray_direction, outward_normal, ni_over_nt, refracted))
-		{
-			reflect_prob = Helper::schlick(cosine, refr_index);
-		}
-		else
-		{
-			reflect_prob = 1.0f;
-		}
-
-		// this logic is not clear? 
-		// Both reflection and refraction of the light occur for dielectric material, but we can only 
-		// pick 1 scattered ray for next iteration of ray tracing. Since we are shooting multiple rays 
-		// per pixel (multi-sampling) and average the traced color as final pixel color, we can use the 
-		// same idea to get the averaged result through both reflectiona and refraction.
-
-		// Now we generate a random number between 0.0 and 1.0. If it’s smaller than reflective coefficient, 
-		// the scattered ray is recorded as reflected; If it’s bigger than reflective coefficient, 
-		// the scattered ray is recorded as refracted.
-		if (Helper::GetRandom01() < reflect_prob)
-		{
-			scattered = Ray(rec.P, reflected);
-		}
-		else
-		{
-			scattered = Ray(rec.P, refracted);
-		}
-
-		++rayCount;
-
-		return true;
-	}
+	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& attenuation, Ray& scattered) const;
 
 private:
 	Texture* Albedo;
diff --git a/RayTracer/TriangleMesh.cpp b/RayTracer/TriangleMesh.cpp
index 9b6606c..91ece4a 100644
--- a/RayTracer/TriangleMesh.cpp
+++ b/RayTracer/TriangleMesh.cpp
@@ -5,7 +5,7 @@
 #include "TriangleMesh.h"
 #include "Material.h"
 #include "Lambertian.h"
-#include "DiffuseLight.h"
+#include "Emissive.h"
 #include "Metal.h"
 #include "Transparent.h"
 #include "Texture.h"
@@ -159,10 +159,11 @@ void TriangleMesh::ProcessMesh(aiMesh* mesh, const aiScene* scene)
 						albedoCol = glm::vec4(diffuseColor.r, diffuseColor.g, diffuseColor.b, diffuseColor.a);
 					}
 
+					// Is this Mesh a light source?
 					if (m_ptrMeshInfo->isLightSource)
 					{
 						textureInfo = new ConstantTexture(albedoCol);
-						m_ptrMaterial = new DiffuseLight(textureInfo);
+						m_ptrMaterial = new Emissive(textureInfo);
 					}
 					else
 					{
```

## `7e8263a` â€” 2020-04-26 _(OpenGL branch)_

> Added changes/framework for Importance sampling.

```diff
diff --git a/Main/Application.cpp b/Main/Application.cpp
index 4a3dfa1..45fb0e1 100644
--- a/Main/Application.cpp
+++ b/Main/Application.cpp
@@ -75,8 +75,8 @@ void Application::Initialize(bool _threaded)
 
 	m_pScene = new Scene();
 	//m_pScene->InitRefractionScene(m_iBackbufferWidth, m_iBackbufferHeight);
-	//m_pScene->InitSphereScene(m_iBackbufferWidth, m_iBackbufferHeight);
-	m_pScene->InitCornellScene(m_iBackbufferWidth, m_iBackbufferHeight);
+	m_pScene->InitSphereScene(m_iBackbufferWidth, m_iBackbufferHeight);
+	//m_pScene->InitCornellScene(m_iBackbufferWidth, m_iBackbufferHeight);
 	//m_pScene->InitTigerScene(m_iBackbufferWidth, m_iBackbufferHeight);
 	//m_pScene->InitTowerScene(m_iBackbufferWidth, m_iBackbufferHeight);
 
@@ -200,12 +200,13 @@ glm::vec3 Application::TraceColor(const Ray & r, int depth, int& rayCount)
 	{
 		Ray scatteredRay;
 
-		glm::vec3 albedo = glm::vec3(0.0f, 0.0f, 0.0f);
+		glm::vec3 outColor = glm::vec3(0.0f, 0.0f, 0.0f);
 		glm::vec3 emitted = rec.mat_ptr->Emitted(rec.uv);
 
-		if (depth < 50 && rec.mat_ptr->Scatter(r, rec, rayCount, albedo, scatteredRay))
+		if (depth < 50 && rec.mat_ptr->Scatter(r, rec, rayCount, outColor, scatteredRay))
 		{
-			traceColor = emitted + (albedo * TraceColor(scatteredRay, depth + 1, rayCount));
+			float pdf = rec.mat_ptr->PDF(r, rec, scatteredRay);
+			traceColor = emitted + ((outColor * TraceColor(scatteredRay, depth + 1, rayCount))) / pdf;
 		}
 		else
 		{
diff --git a/RayTracer/Emissive.h b/RayTracer/Emissive.h
index ba1898f..ed1e65e 100644
--- a/RayTracer/Emissive.h
+++ b/RayTracer/Emissive.h
@@ -13,7 +13,7 @@ public:
 		Emission = _emission;
 	}
 
-	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& albedo, Ray& scatterd) const
+	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& outColor, Ray& scatterd) const
 	{
 		return false;
 	}
diff --git a/RayTracer/Helper.h b/RayTracer/Helper.h
index aaf935f..ffd3a51 100644
--- a/RayTracer/Helper.h
+++ b/RayTracer/Helper.h
@@ -6,6 +6,7 @@
 #include <cstdlib>
 
 const float PI = 3.14159265358f;
+const float INV_PI = 0.3183098861837f;
 
 namespace Helper
 {
diff --git a/RayTracer/Lambertian.cpp b/RayTracer/Lambertian.cpp
index cea632e..4bf28ad 100644
--- a/RayTracer/Lambertian.cpp
+++ b/RayTracer/Lambertian.cpp
@@ -2,13 +2,35 @@
 #include "Lambertian.h"
 #include "Helper.h"
 
-bool Lambertian::Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& albedo, Ray& scatterd) const
+///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+bool Lambertian::Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& outColor, Ray& scatterd) const
 {
 	glm::vec3 target = rec.P + rec.N + Helper::RandomUnitVector();
 
 	scatterd = Ray(rec.P, target - rec.P);
 	++rayCount;
 
-	albedo = Albedo->value(rec.uv);
+	float NdotWi = glm::dot(r_in.direction, rec.N);
+
+	glm::vec3 albedo = Albedo->value(rec.uv);
+
+	// Lambert BRDF = rho * (INV_PI)
+	glm::vec3 brdf = BRDF(r_in, rec, scatterd);
+
+	outColor = albedo * brdf * NdotWi;
+
 	return true;
 }
+
+///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+float Lambertian::PDF(const Ray& r_in, const HitRecord& rec, const Ray& scattered) const
+{
+	float NdotWi = glm::dot(r_in.direction, rec.N);
+	return NdotWi * INV_PI;
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+glm::vec3 Lambertian::BRDF(const Ray& r_in, const HitRecord& rec, const Ray& scattered) const
+{
+	return glm::vec3(INV_PI);
+}
diff --git a/RayTracer/Lambertian.h b/RayTracer/Lambertian.h
index c062fe0..9338bb3 100644
--- a/RayTracer/Lambertian.h
+++ b/RayTracer/Lambertian.h
@@ -10,8 +10,12 @@ class Lambertian : public Material
 public:
 	Lambertian(Texture* _albedo) : Albedo(_albedo) {}
 
-	virtual bool	Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& albedo, Ray& scatterd) const;
+	virtual bool	Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& outColor, Ray& scatterd) const;
+	virtual float	PDF(const Ray& r_in, const HitRecord& rec, const Ray& scattered) const;
 
 private:
-	Texture* Albedo;
+
+	glm::vec3		BRDF(const Ray& r_in, const HitRecord& rec, const Ray& scattered) const;
+
+	Texture*	Albedo;
 };
\ No newline at end of file
diff --git a/RayTracer/Material.h b/RayTracer/Material.h
index 80d3754..e05aa04 100644
--- a/RayTracer/Material.h
+++ b/RayTracer/Material.h
@@ -8,4 +8,6 @@ class Material
 public:
 	virtual bool		Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& albedo, Ray& scattered) const = 0;
 	virtual glm::vec3	Emitted(const glm::vec2& uv) const { return glm::vec3(0); }
+
+	virtual float		PDF(const Ray& r_in, const HitRecord& rec, const Ray& scattered) const = 0;
 };
diff --git a/RayTracer/Metal.cpp b/RayTracer/Metal.cpp
index 3f29136..6534ab2 100644
--- a/RayTracer/Metal.cpp
+++ b/RayTracer/Metal.cpp
@@ -2,12 +2,25 @@
 #include "Metal.h"
 #include "Helper.h"
 
-bool Metal::Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& albedo, Ray& scatterd) const
+///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+bool Metal::Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& outColor, Ray& scatterd) const
 {
 	glm::vec3 target = glm::normalize(Helper::Reflect(r_in.direction, rec.N));
 	scatterd = Ray(rec.P, target + fuzz * Helper::RandomInUnitSphere());
 	++rayCount;
 
-	albedo = Albedo->value(rec.uv);
+	outColor = Albedo->value(rec.uv);
 	return (glm::dot(scatterd.direction, rec.N) > 0);
 }
+
+///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+float Metal::PDF(const Ray& r_in, const HitRecord& rec, const Ray& scattered) const
+{
+	return 0.0f;
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+glm::vec3 Metal::BRDF(const Ray& r_in, const HitRecord& rec, const Ray& scattered) const
+{
+	return glm::vec3();
+}
diff --git a/RayTracer/Metal.h b/RayTracer/Metal.h
index 5a295c4..be5bca5 100644
--- a/RayTracer/Metal.h
+++ b/RayTracer/Metal.h
@@ -16,9 +16,13 @@ public:
 			fuzz = 1;
 	}
 
-	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& attenuation, Ray& scatterd) const;
+	virtual bool		Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& outColor, Ray& scatterd) const;
+	virtual float		PDF(const Ray& r_in, const HitRecord& rec, const Ray& scattered) const;
 
 private:
-	Texture* Albedo;
-	float fuzz;
+
+	glm::vec3			BRDF(const Ray& r_in, const HitRecord& rec, const Ray& scattered) const;
+
+	Texture*	Albedo;
+	float		fuzz;
 };
diff --git a/RayTracer/Scene.cpp b/RayTracer/Scene.cpp
index f36f3bc..e7c2c90 100644
--- a/RayTracer/Scene.cpp
+++ b/RayTracer/Scene.cpp
@@ -36,7 +36,7 @@ Scene::~Scene()
 void Scene::InitSphereScene(float screenWidth, float screenHeight)
 {
 	// Initialize Camera first...!!!
-	glm::vec3 cameraPosition = glm::vec3(0.0f, 3.5f, 7.0f);
+	glm::vec3 cameraPosition = glm::vec3(0.0f, 1.5f, 4.0f);
 	glm::vec3 cameraLookAt = glm::vec3(0.0f, 0.0f, 0.0f);
 	m_pCamera = new Camera();
 	m_pCamera->InitCamera(cameraPosition, cameraLookAt, screenWidth, screenHeight);
@@ -64,7 +64,7 @@ void Scene::InitSphereScene(float screenWidth, float screenHeight)
 	//vecHitables.push_back(pSphereGlass1);
 	//vecHitables.push_back(pSphereMetal);
 	vecHitables.push_back(pSphereEarth);
-	vecHitables.push_back(pSphereLight);
+	//vecHitables.push_back(pSphereLight);
 }
 
 ///////////////////////////////////////////////////////////////////////////////////////////////////
diff --git a/RayTracer/Transparent.cpp b/RayTracer/Transparent.cpp
index db1c3db..be6e4ec 100644
--- a/RayTracer/Transparent.cpp
+++ b/RayTracer/Transparent.cpp
@@ -2,15 +2,15 @@
 #include "Transparent.h"
 #include "Helper.h"
 
-/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
-bool Transparent::Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& albedo, Ray& scattered) const
+///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+bool Transparent::Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& outColor , Ray& scattered) const
 {
 	glm::vec3 outward_normal;
 	glm::vec3 ray_direction = r_in.direction;
 
 	glm::vec3 reflected = Helper::Reflect(ray_direction, rec.N);
 	float ni_over_nt;
-	albedo = Albedo->value(rec.uv);
+	outColor = Albedo->value(rec.uv);
 
 	glm::vec3 refracted = glm::vec3(0.0f, 0.0f, 0.0f);
 	float reflect_prob;
@@ -65,3 +65,15 @@ bool Transparent::Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount,
 	return true;
 }
 
+///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+float Transparent::PDF(const Ray& r_in, const HitRecord& rec, const Ray& scattered) const
+{
+	return 0.0f;
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+glm::vec3 Transparent::BRDF(const Ray& r_in, const HitRecord& rec, const Ray& scattered) const
+{
+	return glm::vec3();
+}
+
diff --git a/RayTracer/Transparent.h b/RayTracer/Transparent.h
index fa79359..28aced1 100644
--- a/RayTracer/Transparent.h
+++ b/RayTracer/Transparent.h
@@ -10,9 +10,14 @@ class Transparent : public Material
 {
 public:
 	Transparent(Texture* _albedo, float ri) : Albedo(_albedo), refr_index(ri) {}
-	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& attenuation, Ray& scattered) const;
+	
+	virtual bool		Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& outColor, Ray& scattered) const;
+	virtual float		PDF(const Ray& r_in, const HitRecord& rec, const Ray& scattered) const;
 
 private:
-	Texture* Albedo;
-	float refr_index;
+
+	glm::vec3			BRDF(const Ray& r_in, const HitRecord& rec, const Ray& scattered) const;
+
+	Texture*	Albedo;
+	float		refr_index;
 };
\ No newline at end of file
```

## `77bad97` â€” 2020-05-04 _(OpenGL branch)_

> - Added Cosine Sampling for Lambertian materials - Implemented Phong material with Importance Sampling.

```diff
diff --git a/Main/Application.cpp b/Main/Application.cpp
index 74b392c..0dff2cb 100644
--- a/Main/Application.cpp
+++ b/Main/Application.cpp
@@ -34,7 +34,7 @@ Application::Application()
 {
 	m_iBackbufferWidth = 500;
 	m_iBackbufferHeight = 500;
-	m_iNumSamples = 1024;
+	m_iNumSamples = 100;
 	m_dTotalRenderTime = 0;
 	m_dDenoiserTime = 0;
 	m_bThreaded = false;
@@ -75,8 +75,8 @@ void Application::Initialize(bool _threaded)
 
 	m_pScene = new Scene();
 	//m_pScene->InitRefractionScene(m_iBackbufferWidth, m_iBackbufferHeight);
-	m_pScene->InitSphereScene(m_iBackbufferWidth, m_iBackbufferHeight);
-	//m_pScene->InitCornellScene(m_iBackbufferWidth, m_iBackbufferHeight);
+	//m_pScene->InitSphereScene(m_iBackbufferWidth, m_iBackbufferHeight);
+	m_pScene->InitCornellScene(m_iBackbufferWidth, m_iBackbufferHeight);
 	//m_pScene->InitTigerScene(m_iBackbufferWidth, m_iBackbufferHeight);
 	//m_pScene->InitTowerScene(m_iBackbufferWidth, m_iBackbufferHeight);
 
@@ -127,11 +127,11 @@ void Application::Execute(GLFWwindow* window)
 ///////////////////////////////////////////////////////////////////////////////////////////////////
 void Application::SaveImage()
 {
-	std::string fileName = m_pSampler->GetName() + std::to_string(m_iBackbufferWidth)
-												 + "x" 
-												 + std::to_string(m_iBackbufferHeight) 
-												 + "_samples_"
-												 + std::to_string(m_iNumSamples) 
+	std::string fileName = m_pSampler->GetName() + "_"
+												 + std::to_string(m_iNumSamples)
+												 + "SPP"
+												 + "_"
+												 + Helper::GetCurrentDateTime()
 												 + ".hdr";
 
 	stbi_flip_vertically_on_write(1);
@@ -179,11 +179,11 @@ void Application::DenoiseImage()
 #endif
 
 		// Write down denoised image in HDR format!!
-		std::string fileName = m_pSampler->GetName() + std::to_string(m_iBackbufferWidth)
-													 + "x"
-													 + std::to_string(m_iBackbufferHeight)
-													 + "_samples_"
-													 + std::to_string(m_iNumSamples)											
+		std::string fileName = m_pSampler->GetName() + "_"
+													 + std::to_string(m_iNumSamples)		
+													 + "SPP"
+													 + "_"		
+													 + Helper::GetCurrentDateTime()
 													 + "_denoised.hdr";
 
 		stbi_write_hdr(fileName.c_str(), m_iBackbufferWidth, m_iBackbufferHeight, 3, outData);
@@ -286,7 +286,7 @@ void Application::ParallelTrace(std::mutex * threadMutex, int i, GLFWwindow* win
 					float u = float(i + samples[s].x);
 					float v = float(j + samples[s].y);
 
-					Ray r = m_pScene->getCamera()->get_ray(u, v);
+					Ray r = Camera::getInstance().get_ray(u, v);
 
 					color = color + TraceColor(r, 0, rayCount);
 				
@@ -314,17 +314,19 @@ void Application::RenderPixel(int rowIndex, int columnIndex)
 	glm::vec3 color(0, 0, 0);
 	int rayCount = 0;
 
+	std::vector<glm::vec2> samples = m_pSampler->GetSamples();
+
 	for (int s = 0; s < m_iNumSamples; s++)
 	{
-		float u = float(columnIndex + Helper::GetRandom01()) / float(m_iBackbufferWidth);
-		float v = float(rowIndex + Helper::GetRandom01()) / float(m_iBackbufferHeight);
+		float u = float(columnIndex + samples[s].x);
+		float v = float(rowIndex + samples[s].y);
 
-		Ray r = m_pScene->getCamera()->get_ray(u, v);
+		Ray r = Camera::getInstance().get_ray(u, v);
 
 		color = color + TraceColor(r, 0, rayCount);
 	}
 
-	color = color / float(m_iNumSamples);
+	//color = color / float(m_iNumSamples);
 	color = glm::vec3(sqrt(color.x), sqrt(color.y), sqrt(color.z));
 
 	int index = columnIndex + m_iBackbufferWidth * rowIndex;
@@ -376,7 +378,7 @@ void Application::Trace(GLFWwindow* window)
 				float u = float(i + samples[s].x);
 				float v = float(j + samples[s].y);
 
-				Ray r = m_pScene->getCamera()->get_ray(u, v);
+				Ray r = Camera::getInstance().get_ray(u, v);
 
 				color = color + TraceColor(r, 0, rayCount);
 			}
diff --git a/RayTracer/Camera.cpp b/RayTracer/Camera.cpp
index dbfc297..6458c34 100644
--- a/RayTracer/Camera.cpp
+++ b/RayTracer/Camera.cpp
@@ -177,3 +177,4 @@ Ray Camera::get_ray(float s, float t)
 	return ray;
 }
 
+
diff --git a/RayTracer/Camera.h b/RayTracer/Camera.h
index b7bc438..a2df629 100644
--- a/RayTracer/Camera.h
+++ b/RayTracer/Camera.h
@@ -14,16 +14,30 @@ enum eProjectionType
 class Camera
 {
 public:
-	Camera();
+	static Camera& getInstance()
+	{
+		static Camera inst;
+		return inst;
+	}
+
 	~Camera();
 
-	void InitCamera(const glm::vec3& _position, const glm::vec3& _lookAt, float _screenWidth, float _screenHeight);
-	Ray get_ray(float s, float t);
+	void			InitCamera(const glm::vec3& _position, const glm::vec3& _lookAt, float _screenWidth, float _screenHeight);
+	Ray				get_ray(float s, float t);
+
+	inline glm::vec3 GetViewDirection(const glm::vec3& _pos) { return glm::normalize(_pos - position); }
+
 
 private:
+	Camera();
+	Camera(const Camera&);
+	void operator=(const Camera&);
+
+public:
 	// Camera vectors
 	glm::vec3		position, lookAt, Up;
 
+private:
 	// basis vectors
 	glm::vec3		u, v, w;
 
diff --git a/RayTracer/Helper.h b/RayTracer/Helper.h
index ffd3a51..815e7a4 100644
--- a/RayTracer/Helper.h
+++ b/RayTracer/Helper.h
@@ -4,22 +4,41 @@
 #define GLM_ENABLE_EXPERIMENTAL
 #include "glm/gtx/norm.hpp"
 #include <cstdlib>
+#include <time.h>
+#include <string>
 
 const float PI = 3.14159265358f;
+const float TWO_PI = 6.283185307179f;
+const float PI_OVER_TWO = 1.570796326794f;
 const float INV_PI = 0.3183098861837f;
 
 namespace Helper
 {
+	inline std::string GetCurrentDateTime()
+	{
+		time_t now = time(0);
+		struct tm tstruct;
+		char buf[80];
+
+		tstruct = *localtime(&now);
+		strftime(buf, sizeof(buf), "%d_%B_%Y_%H_%M_%S", &tstruct);
+
+		return buf;
+	}
+
+	////////////////////////////////////////////////////////////////////////////////////////////////////////////
 	inline glm::vec3 LerpVector(const glm::vec3& vec1, const glm::vec3& vec2, float t)
 	{
 		return (1.0f - t) * vec1 + t * vec2;
 	}
 
+	////////////////////////////////////////////////////////////////////////////////////////////////////////////
 	inline float GetRandom01()
 	{
 		return ((float)rand() / (RAND_MAX + 1));
 	}
 
+	////////////////////////////////////////////////////////////////////////////////////////////////////////////
 	inline glm::vec3 GetRandomInUnitDisk()
 	{
 		glm::vec3 p;
@@ -31,6 +50,7 @@ namespace Helper
 		return p;
 	}
 
+	////////////////////////////////////////////////////////////////////////////////////////////////////////////
 	inline glm::vec3 RandomInUnitSphere()
 	{
 		glm::vec3 P;
@@ -43,6 +63,130 @@ namespace Helper
 		return P;
 	}
 
+	////////////////////////////////////////////////////////////////////////////////////////////////////////////
+	inline glm::vec3 CosineSamplingUpperHemisphere(glm::vec3 Normal)
+	{
+		float rand1 = GetRandom01();
+		float rand2 = GetRandom01();
+		
+		float phi = TWO_PI * rand2;	// phi = 2PI * esp2
+		float y = sqrtf(rand1);		// y = sqrt(eps1)
+
+		float theta = acosf(y);
+
+		// Generate random sample
+		float X = sinf(theta) * cosf(phi);
+		float Y = cosf(theta);
+		float Z = sinf(theta) * sinf(phi);
+
+		//return glm::vec3(X, Y, Z);
+
+		// This sample is oriented towards Local Y axis instead of oriented as per the hitpoint normal
+		// need to do that before actually using it!
+		glm::vec3 Up;
+		if (fabsf(Normal.y > 0.9f))
+			Up = glm::vec3(1, 0, 0);
+		else
+			Up = glm::vec3(0, 1, 0);
+
+		glm::vec3 v = glm::normalize(Normal);
+		glm::vec3 u = glm::normalize(glm::cross(Up, v));
+		glm::vec3 w = glm::cross(v, u);
+		
+		return X * u + Y * v + Z * w;
+	}
+
+	////////////////////////////////////////////////////////////////////////////////////////////////////////////
+	inline glm::vec3 PhongImportanceSampling(glm::vec3 Normal, glm::vec3 Reflection, float Ks, float SpecularPower)
+	{
+		float rand1 = GetRandom01();
+		float rand2 = GetRandom01();
+
+		float theta = acosf(powf(rand1, (1.0f / (SpecularPower + 1.0f))));
+		float phi = rand2 * TWO_PI;
+
+		// Generate random sample
+		float X = sinf(theta) * cosf(phi);
+		float Y = cosf(theta);
+		float Z = sinf(theta) * sinf(phi);
+
+		//return glm::vec3(X, Y, Z);
+
+		// This sample is oriented towards Local Y axis instead of oriented as per the reflection vector
+		// need to do that before actually using it!
+		glm::vec3 Up;
+		if (fabsf(Reflection.y > 0.9f))
+			Up = glm::vec3(1, 0, 0);
+		else
+			Up = glm::vec3(0, 1, 0);
+
+		glm::vec3 v = glm::normalize(Reflection);
+		glm::vec3 u = glm::normalize(glm::cross(Up, v));
+		glm::vec3 w = glm::cross(v, u);
+
+		return X * u + Y * v + Z * w;
+	}
+
+	////////////////////////////////////////////////////////////////////////////////////////////////////////////
+	inline glm::vec3 ModifiedPhongImportanceSampling(glm::vec3 Normal, glm::vec3 Reflection, float Ks, float SpecularPower)
+	{
+		float rand1 = GetRandom01();
+		float rand2 = GetRandom01();
+		float rand3 = GetRandom01();
+
+		float phi = rand3 * TWO_PI;
+
+		if (rand1 < 1-Ks)
+		{
+			// Diffuse
+			float theta = acosf(sqrtf(rand2));
+
+			// Generate random sample
+			float X = sinf(theta) * cosf(phi);
+			float Y = cosf(theta);
+			float Z = sinf(theta) * sinf(phi);
+
+			// This sample is oriented towards Local Y axis instead of oriented as per the normal vector
+			// need to do that before actually using it!
+			glm::vec3 Up;
+			if (fabsf(Normal.y > 0.9f))
+				Up = glm::vec3(1, 0, 0);
+			else
+				Up = glm::vec3(0, 1, 0);
+
+			glm::vec3 v = glm::normalize(Normal);
+			glm::vec3 u = glm::normalize(glm::cross(Up, v));
+			glm::vec3 w = glm::cross(v, u);
+
+			return X * u + Y * v + Z * w;
+		}
+		else
+		{
+			// Specular
+			float theta = acosf(powf(rand2, (1.0f / (SpecularPower + 1.0f))));
+
+			// Generate random sample
+			float X = sinf(theta) * cosf(phi);
+			float Y = cosf(theta);
+			float Z = sinf(theta) * sinf(phi);
+
+			// This sample is oriented towards Local Y axis instead of oriented as per the reflection vector
+			// need to do that before actually using it!
+			glm::vec3 Up;
+			if (fabsf(Reflection.y > 0.9f))
+				Up = glm::vec3(1, 0, 0);
+			else
+				Up = glm::vec3(0, 1, 0);
+
+			glm::vec3 v = glm::normalize(Reflection);
+			glm::vec3 u = glm::normalize(glm::cross(Up, v));
+			glm::vec3 w = glm::cross(v, u);
+
+			return X * u + Y * v + Z * w;
+		}
+	}
+
+	////////////////////////////////////////////////////////////////////////////////////////////////////////////
 	inline glm::vec3 RandomUnitVector()
 	{
 		float z = GetRandom01() * 2.0f - 1.0f;
@@ -54,11 +198,13 @@ namespace Helper
 		return glm::vec3(x, y, z);
 	}
 
+	////////////////////////////////////////////////////////////////////////////////////////////////////////////
 	inline glm::vec3 Reflect(const glm::vec3& dir, const glm::vec3& normal)
 	{
 		return (dir - 2.0f * glm::dot(dir, normal) * normal);
 	}
 
+	////////////////////////////////////////////////////////////////////////////////////////////////////////////
 	inline bool Refract(const glm::vec3& v, const glm::vec3& n, float ni_over_nt, glm::vec3& refracted)
 	{
 		glm::vec3 unit_v = glm::normalize(v);
@@ -74,6 +220,7 @@ namespace Helper
 			return false;
 	}
 
+	////////////////////////////////////////////////////////////////////////////////////////////////////////////
 	inline float schlick(float cosine, float ref_idx)
 	{
 		float r0 = (1 - ref_idx) / (1 + ref_idx);
diff --git a/RayTracer/Lambertian.cpp b/RayTracer/Lambertian.cpp
index 4bf28ad..30655e7 100644
--- a/RayTracer/Lambertian.cpp
+++ b/RayTracer/Lambertian.cpp
@@ -5,12 +5,11 @@
 ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
 bool Lambertian::Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& outColor, Ray& scatterd) const
 {
-	glm::vec3 target = rec.P + rec.N + Helper::RandomUnitVector();
-
-	scatterd = Ray(rec.P, target - rec.P);
+	glm::vec3 direction = Helper::CosineSamplingUpperHemisphere(rec.N);
+	scatterd = Ray(rec.P, glm::normalize(direction));
 	++rayCount;
 
-	float NdotWi = glm::dot(r_in.direction, rec.N);
+	float NdotWi = glm::dot(glm::normalize(r_in.direction), rec.N);
 
 	glm::vec3 albedo = Albedo->value(rec.uv);
 
@@ -25,7 +24,7 @@ bool Lambertian::Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, g
 ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
 float Lambertian::PDF(const Ray& r_in, const HitRecord& rec, const Ray& scattered) const
 {
-	float NdotWi = glm::dot(r_in.direction, rec.N);
+	float NdotWi = glm::dot(glm::normalize(r_in.direction), rec.N);
 	return NdotWi * INV_PI;
 }
 
diff --git a/RayTracer/Phong.cpp b/RayTracer/Phong.cpp
new file mode 100644
index 0000000..16a4fa6
--- /dev/null
+++ b/RayTracer/Phong.cpp
@@ -0,0 +1,50 @@
+
+#include "Phong.h"
+#include "Helper.h"
+
+///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+bool Phong::Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& outColor, Ray& scatterd) const
+{
+	glm::vec3 PerfectReflDir = glm::normalize(Helper::Reflect(r_in.direction, rec.N));
+
+	glm::vec3 direction = Helper::ModifiedPhongImportanceSampling(rec.N, PerfectReflDir, Ks, SpecularPower);
+	scatterd = Ray(rec.P, glm::normalize(direction));
+
+	++rayCount;
+
+	glm::vec3 brdf = BRDF(r_in, rec, scatterd);
+	outColor = brdf * Albedo->value(rec.uv);
+
+	bool flag = (glm::dot(scatterd.direction, rec.N) > 0);
+	return flag;
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+float Phong::PDF(const Ray& r_in, const HitRecord& rec, const Ray& scattered) const
+{
+	// Lambertian PDF
+	float NdotWi = glm::clamp(glm::dot(r_in.direction, rec.N), 0.0f, 1.0f);
+	float lambertPDF = Kd * INV_PI;
+	
+	// Specular PDF
+	glm::vec3 PerfectReflDir = glm::normalize(Helper::Reflect(r_in.direction, rec.N));
+	float alpha = glm::clamp(glm::dot(scattered.direction, PerfectReflDir), 0.0f, PI_OVER_TWO);
+	float specularPDF = Ks * (SpecularPower + 1) / TWO_PI * powf(alpha, SpecularPower);
+
+	return glm::clamp(lambertPDF + specularPDF, 0.0f, 1.0f);
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+glm::vec3 Phong::BRDF(const Ray& r_in, const HitRecord& rec, const Ray& scattered) const
+{
+	// Diffuse BRDF
+	float diffuseBRDF = Kd * INV_PI; 
+
+	// Specular BRDF
+	glm::vec3 PerfectReflDir = glm::normalize(Helper::Reflect(r_in.direction, rec.N));
+	float alpha = glm::dot(scattered.direction, PerfectReflDir);
+
+	float specBRDF = Ks * powf(alpha, SpecularPower) * ((alpha + 2) / TWO_PI);
+
+	return glm::vec3(diffuseBRDF + specBRDF);
+}
diff --git a/RayTracer/Phong.h b/RayTracer/Phong.h
new file mode 100644
index 0000000..cc4ecd8
--- /dev/null
+++ b/RayTracer/Phong.h
@@ -0,0 +1,31 @@
+#pragma once
+
+#include "Ray.h"
+#include "Hitable.h"
+#include "Material.h"
+#include "Texture.h"
+
+class Phong : public Material
+{
+public:
+	Phong(Texture* _albedo, float _power, float _ks) 
+			:	Albedo(_albedo), 
+				SpecularPower(_power),
+				Ks(_ks)
+	{
+		Kd = 1.0f - Ks;
+	}
+
+	virtual bool		Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& outColor, Ray& scatterd) const;
+	virtual float		PDF(const Ray& r_in, const HitRecord& rec, const Ray& scattered) const;
+
+private:
+
+	glm::vec3			BRDF(const Ray& r_in, const HitRecord& rec, const Ray& scattered) const;
+
+	Texture*	Albedo;
+	float		SpecularPower;
+
+	float		Ks;
+	float		Kd;
+};
diff --git a/RayTracer/Scene.cpp b/RayTracer/Scene.cpp
index 266b50c..096641a 100644
--- a/RayTracer/Scene.cpp
+++ b/RayTracer/Scene.cpp
@@ -4,6 +4,7 @@
 #include "Sphere.h"
 #include "FlatColor.h"
 #include "Lambertian.h"
+#include "Phong.h"
 #include "Emissive.h"
 #include "Metal.h"
 #include "Transparent.h"
@@ -18,18 +19,12 @@ Scene::Scene()
 {
 	m_colMiss = glm::vec4(0.5f);
 	vecHitables.clear();
-	m_pCamera = nullptr;
 }
 
 ///////////////////////////////////////////////////////////////////////////////////////////////////
 Scene::~Scene()
 {
 	vecHitables.clear();
-	if (m_pCamera)
-	{
-		delete m_pCamera;
-		m_pCamera = nullptr;
-	}
 }
 
 ///////////////////////////////////////////////////////////////////////////////////////////////////
@@ -38,8 +33,8 @@ void Scene::InitSphereScene(float screenWidth, float screenHeight)
 	// Initialize Camera first...!!!
 	glm::vec3 cameraPosition = glm::vec3(0.0f, 1.5f, 4.0f);
 	glm::vec3 cameraLookAt = glm::vec3(0.0f, 0.0f, 0.0f);
-	m_pCamera = new Camera();
-	m_pCamera->InitCamera(cameraPosition, cameraLookAt, screenWidth, screenHeight);
+
+	Camera::getInstance().InitCamera(cameraPosition, cameraLookAt, screenWidth, screenHeight);
 
 	// Override miss color to black
 	m_colMiss = glm::vec4(0.78f, 0.88f, 1.0f, 1.0f);
@@ -56,7 +51,7 @@ void Scene::InitSphereScene(float screenWidth, float screenHeight)
 	//Sphere* pSphereGlass1 = new Sphere(glm::vec3(-4.0f, 0.4f, 0.0f), 1.0f, new Transparent(new ConstantTexture(glassColor), 1.5f));
 	//Sphere* pSphereMetal = new Sphere(glm::vec3(3.5f, 0.5f, 0.0f), 1.0f, new Metal(checksTexture, 0.1f));
 	Sphere* pSphereLight = new Sphere(glm::vec3(-1.5f, 0.5f, 0.0f), 0.75f, new Emissive(new ConstantTexture(glm::vec3(1.0f, 1.0f, 1.0f))));
-	Sphere* pSphereEarth = new Sphere(glm::vec3(0.5f, 0.0f, 0.0f), 0.5, new Lambertian(new ImageTexture("models/earth.jpg")));
+	Sphere* pSphereEarth = new Sphere(glm::vec3(0.5f, 0.0f, 0.0f), 0.5, new Phong(new ImageTexture("models/earth.jpg"), 32.0f, 1.0f));
 
 	//Profiler::getInstance().WriteToProfiler("Triangle Count:", pMesh0->GetTriangleCount());
 
@@ -73,8 +68,8 @@ void Scene::InitRefractionScene(float screenWidth, float screenHeight)
 	// Initialize Camera first...!!!
 	glm::vec3 cameraPosition = glm::vec3(0.0f, 3.5f, 7.0f);
 	glm::vec3 cameraLookAt = glm::vec3(0.0f, 0.0f, 0.0f);
-	m_pCamera = new Camera();
-	m_pCamera->InitCamera(cameraPosition, cameraLookAt, screenWidth, screenHeight);
+	
+	Camera::getInstance().InitCamera(cameraPosition, cameraLookAt, screenWidth, screenHeight);
 
 	// Override miss color to black
 	m_colMiss = glm::vec4(0.78f, 0.88f, 1.0f, 1.0f);
@@ -104,8 +99,8 @@ void Scene::InitTigerScene(float screenWidth, float screenHeight)
 	// Initialize Camera first...!!!
 	glm::vec3 cameraPosition = glm::vec3(0.0f, 1.5f, 5.0f);
 	glm::vec3 cameraLookAt = glm::vec3(0.0f, 0.0f, 0.0f);
-	m_pCamera = new Camera();
-	m_pCamera->InitCamera(cameraPosition, cameraLookAt, screenWidth, screenHeight);
+	
+	Camera::getInstance().InitCamera(cameraPosition, cameraLookAt, screenWidth, screenHeight);
 
 	// Override miss color to black
 	m_colMiss = glm::vec4(0.78f, 0.88f, 1.0f, 1.0f);
@@ -180,14 +175,17 @@ void Scene::InitCornellScene(float screenWidth, float screenHeight)
 	// Initialize Camera first...!!!
 	glm::vec3 cameraPosition = glm::vec3(0.0f, 2.5f, 8.5f);
 	glm::vec3 cameraLookAt = glm::vec3(0.0f, 2.5f, 0.0f);
-	m_pCamera = new Camera();
-	m_pCamera->InitCamera(cameraPosition, cameraLookAt, screenWidth, screenHeight);
+	
+	Camera::getInstance().InitCamera(cameraPosition, cameraLookAt, screenWidth, screenHeight);
 
 	// Override miss color to black
-	m_colMiss = glm::vec4(0.0f);
+	m_colMiss = glm::vec4(0.1f,0.1f,0.1f, 1.0f);
 	
-	glm::vec4 glassColor = glm::vec4(0, 1, 0, 1);
-	Sphere* pSphereGlass = new Sphere(glm::vec3(-1.0f, 0.5f, 1.0f), 0.5f, new Lambertian(new ConstantTexture(glassColor)));
+	glm::vec4 glassColor = glm::vec4(1, 1, 1, 1);
+	Sphere* pSphereGlass = new Sphere(glm::vec3(1.0f, 1.0f, 0.0f), 1.0f, new Phong(new ConstantTexture(glassColor), 512.0f, 1.0f));
+
+	glm::vec4 lightColor = glm::vec4(10, 10, 0, 0);
+	Sphere* pLightSphere = new Sphere(glm::vec3(-1.0f, 1.0f, 1.0f), 0.5f, new Emissive(new ConstantTexture(lightColor)));
 
 	// Room Mesh
 	MeshInfo roomInfo;
@@ -229,7 +227,7 @@ void Scene::InitCornellScene(float screenWidth, float screenHeight)
 	lightInfo.leafSize = 2;
 	lightInfo.position = glm::vec3(0, 4.99f, 0.5f);
 	lightInfo.scale = glm::vec3(1.2);
-	lightInfo.matInfo.albedoColor = glm::vec4(glm::vec3(15.0f), 1);
+	lightInfo.matInfo.albedoColor = glm::vec4(glm::vec3(50.0f), 1);
 	TriangleMesh* pLight = new TriangleMesh(lightInfo);
 
 	// Glass Mesh
@@ -246,9 +244,10 @@ void Scene::InitCornellScene(float screenWidth, float screenHeight)
 
 	vecHitables.push_back(pLight);
 	vecHitables.push_back(pRoom);
-	vecHitables.push_back(pLeftCube);
-	vecHitables.push_back(pRightCube);
+	//vecHitables.push_back(pLeftCube);
+	//vecHitables.push_back(pRightCube);
 	vecHitables.push_back(pSphereGlass);
+	vecHitables.push_back(pLightSphere);
 	//vecHitables.push_back(pGlassTiger);
 
 	Profiler::getInstance().WriteToProfiler("Triangle Count:", pRoom->GetTriangleCount() + pLight->GetTriangleCount() + pLeftCube->GetTriangleCount());
@@ -260,8 +259,8 @@ void Scene::InitTowerScene(float screenWidth, float screenHeight)
 	// Initialize Camera first...!!!
 	glm::vec3 cameraPosition = glm::vec3(5.0f, 2.5f, 5.0f);
 	glm::vec3 cameraLookAt = glm::vec3(0.0f, 0.0f, 0.0f);
-	m_pCamera = new Camera();
-	m_pCamera->InitCamera(cameraPosition, cameraLookAt, screenWidth, screenHeight);
+
+	Camera::getInstance().InitCamera(cameraPosition, cameraLookAt, screenWidth, screenHeight);
 
 	// Override miss color to black
 	m_colMiss = glm::vec4(0.01f);
@@ -296,8 +295,8 @@ void Scene::InitRandomScene(float screenWidth, float screenHeight)
 	// Initialize Camera first...!!!
 	glm::vec3 cameraPosition = glm::vec3(5.0f, 2.5f, 5.0f);
 	glm::vec3 cameraLookAt = glm::vec3(0.0f, 0.0f, 0.0f);
-	m_pCamera = new Camera();
-	m_pCamera->InitCamera(cameraPosition, cameraLookAt, screenWidth, screenHeight);
+	
+	Camera::getInstance().InitCamera(cameraPosition, cameraLookAt, screenWidth, screenHeight);
 
 	Sphere* pSphere0 = new Sphere(glm::vec3(0, -1000.0f, 0), 1000, new Lambertian(new ConstantTexture (glm::vec3(0.5, 0.5, 0.5))));
 	vecHitables.push_back(pSphere0);
diff --git a/RayTracer/Scene.h b/RayTracer/Scene.h
index a2dfdbc..ac70269 100644
--- a/RayTracer/Scene.h
+++ b/RayTracer/Scene.h
@@ -11,22 +11,19 @@ public:
 	Scene();
 	~Scene();
 
-	bool Trace(const Ray& r, int& rayCount, float tmin, float tmax, HitRecord& rec);
-
-	void InitSphereScene(float screenWidth, float screenHeight);
-	void InitRefractionScene(float screenWidth, float screenHeight);
-	void InitTigerScene(float screenWidth, float screenHeight);
-	void InitCornellScene(float screenWidth, float screenHeight);
-	void InitTowerScene(float screenWidth, float screenHeight);
-	void InitRandomScene(float screenWidth, float screenHeight);
-
-	inline Camera* getCamera() { if(m_pCamera) return m_pCamera; }
+	bool		Trace(const Ray& r, int& rayCount, float tmin, float tmax, HitRecord& rec);
+
+	void		InitSphereScene(float screenWidth, float screenHeight);
+	void		InitRefractionScene(float screenWidth, float screenHeight);
+	void		InitTigerScene(float screenWidth, float screenHeight);
+	void		InitCornellScene(float screenWidth, float screenHeight);
+	void		InitTowerScene(float screenWidth, float screenHeight);
+	void		InitRandomScene(float screenWidth, float screenHeight);
 	
 	glm::vec4	CalculateMissColor(glm::vec3 rayDirection);
 
 private:	
 	glm::vec4			  m_colMiss;
-	Camera*				  m_pCamera;
 	std::vector<Hitable*> vecHitables;
 
 };
\ No newline at end of file
```

