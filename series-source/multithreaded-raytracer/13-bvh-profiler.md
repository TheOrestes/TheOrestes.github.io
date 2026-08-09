# Post 13 — LameBVH and the Profiler system

## `c5e1a44` — 2019-03-04 _(master)_

> Added Profiling data capturing

```diff
diff --git a/Application.cpp b/Application.cpp
index b17d3b9..05fb198 100644
--- a/Application.cpp
+++ b/Application.cpp
@@ -9,6 +9,7 @@
 #include "RayTracer/Scene.h"
 #include "RayTracer/Helper.h"
 #include "RayTracer/Camera.h"
+#include "Profiler.h"
 #include "Application.h"
 
 ///////////////////////////////////////////////////////////////////////////////////////////////////
@@ -21,6 +22,10 @@ Application::Application()
 	m_bThreaded = false;
 
 	m_iRayCount = 0;
+	m_iRayTriangleTest = 0;
+	m_iRayTriangleIntersections = 0;
+	m_iRayBoxTest = 0;
+	m_iTriangleCount = 0;
 
 	m_hWnd = NULL;
 }
@@ -37,7 +42,7 @@ void Application::Initialize(HWND hwnd, bool _threaded)
 	m_bThreaded = _threaded;
 	m_hWnd = hwnd;
 
-	_threaded ? m_iMaxThreads = std::thread::hardware_concurrency() : 0;
+	_threaded ? m_iMaxThreads = std::thread::hardware_concurrency() - 2 : 0;
 
 	m_pCamera = &(Camera::getInstance());
 	m_pCamera->InitCamera(m_iBackbufferWidth, m_iBackbufferHeight);
@@ -56,12 +61,12 @@ void Application::Execute()
 	const clock_t end_time = clock();
 	m_dTotalRenderTime = (end_time - begin_time) / (double)CLOCKS_PER_SEC;
 
-	int rayCount = m_iRayCount;
-
-	const size_t len = 256;
-	wchar_t buffer[len] = {};
-	swprintf(buffer, L"[Time : %0.2f seconds!] [Ray Count : %d rays]", m_dTotalRenderTime, rayCount);
-	SetWindowText(m_hWnd, buffer);
+	// Write into Profiler...
+	Profiler::getInstance().WriteToProfiler("Total Render Time: ", m_dTotalRenderTime);
+	Profiler::getInstance().WriteToProfiler("Ray Count: ", m_iRayCount);
+	Profiler::getInstance().WriteToProfiler("Ray Triangle Tests : ", m_iRayTriangleTest);
+	Profiler::getInstance().WriteToProfiler("Ray Triangle Intersections : ", m_iRayTriangleIntersections);
+	Profiler::getInstance().WriteToProfiler("Ray Box Tests : ", m_iRayBoxTest);
 }
 
 ///////////////////////////////////////////////////////////////////////////////////////////////////
@@ -113,6 +118,7 @@ void Application::SaveImage()
 glm::vec3 Application::TraceColor(const Ray & r, int depth, int& rayCount)
 {
 	HitRecord rec;
+	glm::vec3 traceColor = glm::vec3(0);
 
 	if (Scene::getInstance().Trace(r, rayCount, 0.001f, FLT_MAX, rec))
 	{
@@ -122,21 +128,24 @@ glm::vec3 Application::TraceColor(const Ray & r, int depth, int& rayCount)
 		if (depth < 50 && rec.mat_ptr->Scatter(r, rec, rayCount, attenuation, scatteredRay))
 		{
 			if (glm::distance(scatteredRay.GetRayOrigin(), scatteredRay.GetRayDirection()) < 0.0000001f)
-				return attenuation;
+				traceColor = attenuation;
 			else
-				return attenuation * TraceColor(scatteredRay, depth + 1, rayCount);
-		}
-		else
-		{
-			return glm::vec3(0, 0, 0);
+				traceColor = attenuation * TraceColor(scatteredRay, depth + 1, rayCount);
 		}
 	}
 	else
 	{
 		glm::vec3 unit_direction = glm::normalize(r.GetRayDirection());
 		float t = 0.5f * (unit_direction.y + 1.0f);
-		return Helper::LerpVector(glm::vec3(1.0f, 1.0f, 1.0f), glm::vec3(0.5f, 0.7f, 1.0f), t);
+		traceColor = Helper::LerpVector(glm::vec3(1.0f, 1.0f, 1.0f), glm::vec3(0.5f, 0.7f, 1.0f), t);
 	}
+
+	// debug info...
+	m_iRayTriangleTest += rec.rayTriangleTestCount;
+	m_iRayTriangleIntersections += rec.rayTriangleIntersectionCount;
+	m_iRayBoxTest += rec.rayBoxTestCount;
+
+	return traceColor;
 }
 
 ///////////////////////////////////////////////////////////////////////////////////////////////////
@@ -152,10 +161,22 @@ void Application::ParallelTrace(std::mutex * threadMutex, int i)
 	int backBufferHeight = m_iBackbufferHeight;
 	int backBufferWidth = m_iBackbufferWidth;
 	int quarterHeight = m_iBackbufferHeight / m_iMaxThreads;
+	
 	int startWidth = 0;
-	int startHeight = i * quarterHeight;
 	int endWidth = m_iBackbufferWidth;
-	int endHeight = (i + 1) * quarterHeight;
+	
+	int startHeight, endHeight;
+	
+	if (i == 0)
+		startHeight = (i * quarterHeight);
+	else
+		startHeight = (i * quarterHeight) + i;
+
+	if (i < m_iMaxThreads - 1)
+		endHeight = startHeight + quarterHeight;
+	else
+		endHeight = backBufferHeight;
+
 	int ns = m_iNumSamples;
 	HDC hdc = GetDC(m_hWnd);
 
@@ -166,7 +187,7 @@ void Application::ParallelTrace(std::mutex * threadMutex, int i)
 	// Error check for bounds!
 	if (startWidth < endWidth && startHeight < endHeight)
 	{
-		for (int j = startHeight; j <= endHeight; j++)
+		for (int j = startHeight ; j <= endHeight; j++)
 		{
 			for (int i = startWidth; i <= endWidth; i++)
 			{
diff --git a/Application.h b/Application.h
index d2ecc1e..897d5d0 100644
--- a/Application.h
+++ b/Application.h
@@ -36,6 +36,10 @@ private:
 	bool			m_bThreaded;
 
 	std::atomic<int>	m_iRayCount;
+	std::atomic<int>    m_iRayTriangleTest;
+	std::atomic<int>    m_iRayTriangleIntersections;
+	std::atomic<int>    m_iRayBoxTest;
+	std::atomic<int>    m_iTriangleCount;
 
 	HWND			m_hWnd;
 	Camera*			m_pCamera;
diff --git a/Profiler.cpp b/Profiler.cpp
new file mode 100644
index 0000000..99b65dd
--- /dev/null
+++ b/Profiler.cpp
@@ -0,0 +1,49 @@
+#include "Profiler.h"
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+Profiler::Profiler()
+{
+	m_strInfo.clear();
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+Profiler::~Profiler()
+{
+	m_strInfo.clear();
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void Profiler::WriteToProfiler(const std::string & _inputStr)
+{
+	m_strInfo.append("\n" + _inputStr);
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void Profiler::WriteToProfiler(const std::string & _inputStr, float _value)
+{
+	char buffer[64];
+	sprintf(buffer, "%.2f", _value);
+
+	m_strInfo.append("\n" + _inputStr);
+	m_strInfo.append(buffer);
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void Profiler::WriteToProfiler(const std::string & _inputStr, double _value)
+{
+	char buffer[64];
+	sprintf(buffer, "%.2f", _value);
+
+	m_strInfo.append("\n" + _inputStr);
+	m_strInfo.append(buffer);
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void Profiler::WriteToProfiler(const std::string & _inputStr, int _value)
+{
+	char buffer[64];
+	sprintf(buffer, "%d", _value);
+
+	m_strInfo.append("\n" + _inputStr);
+	m_strInfo.append(buffer);
+}
diff --git a/Profiler.h b/Profiler.h
new file mode 100644
index 0000000..ee89c3e
--- /dev/null
+++ b/Profiler.h
@@ -0,0 +1,27 @@
+#pragma once
+
+#include <string>
+
+class Profiler
+{
+public:
+	static Profiler& getInstance()
+	{
+		static Profiler instance;
+		return instance;
+	}
+
+	~Profiler();
+
+	std::string GetProfilerTexts() { return m_strInfo; }
+
+	void WriteToProfiler(const std::string& _inputStr);
+	void WriteToProfiler(const std::string& _inputStr, float _value);
+	void WriteToProfiler(const std::string& _inputStr, double _value);
+	void WriteToProfiler(const std::string& _inputStr, int _value);
+
+private:
+	Profiler();
+
+	std::string m_strInfo;
+};
diff --git a/RayTracer/AABB.cpp b/RayTracer/AABB.cpp
index e15e200..6d649dd 100644
--- a/RayTracer/AABB.cpp
+++ b/RayTracer/AABB.cpp
@@ -1,4 +1,5 @@
 
+#include "Hitable.h"
 #include "AABB.h"
 #include <algorithm>
 
@@ -21,8 +22,10 @@ void AABB::UpdateBB(const glm::vec3& _pos)
 	if (_pos.z > maxBound.z) { maxBound.z = _pos.z; }
 }
 
-bool AABB::hit(const Ray & r, float tmin, float tmax)
+bool AABB::hit(const Ray & r, float tmin, float tmax, HitRecord& rec)
 {
+	++rec.rayBoxTestCount;
+
 	glm::vec3 rayOrigin = r.GetRayOrigin();
 	glm::vec3 rayDirection = r.GetRayDirection();
 	glm::vec3 rayInvDirection = r.GetInvRayDirection();
diff --git a/RayTracer/AABB.h b/RayTracer/AABB.h
index 7bcd84d..5b6e8d4 100644
--- a/RayTracer/AABB.h
+++ b/RayTracer/AABB.h
@@ -3,6 +3,8 @@
 #include "glm\glm.hpp"
 #include "Ray.h"
 
+struct HitRecord;
+
 class AABB
 {
 public:
@@ -13,7 +15,7 @@ public:
 		maxBound(_max) {}
 
 	void UpdateBB(const glm::vec3& _pos);
-	bool hit(const Ray& r, float tmin, float tmax);
+	bool hit(const Ray& r, float tmin, float tmax, HitRecord& rec);
 
 private:
 	glm::vec3 minBound;
diff --git a/RayTracer/Hitable.h b/RayTracer/Hitable.h
index 2b6233c..fb8fc83 100644
--- a/RayTracer/Hitable.h
+++ b/RayTracer/Hitable.h
@@ -6,11 +6,29 @@ class Material;
 
 struct HitRecord
 {
+	HitRecord()
+	{
+		t = 0.0f;
+		P = glm::vec3(0);
+		N = glm::vec3(0);
+		uv = glm::vec2(0);
+		mat_ptr = nullptr;
+
+		rayTriangleTestCount = 0;
+		rayTriangleIntersectionCount = 0;
+		rayBoxTestCount = 0;
+	}
+
 	float t;
 	glm::vec3 P;
 	glm::vec3 N;
 	glm::vec2 uv;
 	Material* mat_ptr;
+
+	// Debug...
+	int rayTriangleTestCount;
+	int rayTriangleIntersectionCount;
+	int rayBoxTestCount;
 };
 
 class Hitable
diff --git a/RayTracer/Scene.cpp b/RayTracer/Scene.cpp
index fdfa74a..736b798 100644
--- a/RayTracer/Scene.cpp
+++ b/RayTracer/Scene.cpp
@@ -9,6 +9,7 @@
 #include "Texture.h"
 #include "Triangle.h"
 #include "TriangleMesh.h"
+#include "../Profiler.h"
 
 Scene::Scene()
 {
@@ -42,8 +43,10 @@ void Scene::InitScene()
 	Texture* baseTexture = new ImageTexture("models/car.jpg");
 	Material* pMatMesh = new Lambertian(baseTexture);
 	//Material* pMatMesh = new FlatColor (new ConstantTexture(glm::vec3(1,1,0)));
-	//TriangleMesh* pMesh0 = new TriangleMesh("models/UVCube5.fbx", pMatMesh);
-	TriangleMesh* pMesh0 = new TriangleMesh("models/car.fbx", pMatMesh);
+	TriangleMesh* pMesh0 = new TriangleMesh("models/UVCube5.fbx", pMatMesh);
+	//TriangleMesh* pMesh0 = new TriangleMesh("models/car.fbx", pMatMesh);
+
+	Profiler::getInstance().WriteToProfiler("Triangle Count:", pMesh0->GetTriangleCount());
 
 	vecHitables.push_back(pSphere0);
 	vecHitables.push_back(pSphere1);
diff --git a/RayTracer/Triangle.cpp b/RayTracer/Triangle.cpp
index aae7a94..4c0fd38 100644
--- a/RayTracer/Triangle.cpp
+++ b/RayTracer/Triangle.cpp
@@ -6,6 +6,8 @@
 /////////////////////////////////////////////////////////////////////////////////////////
 bool Triangle::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
 {
+	++rec.rayTriangleTestCount;
+
 	glm::vec3 rayDirection = r.GetRayDirection();
 	glm::vec3 rayOrigin = r.GetRayOrigin();
 
@@ -102,6 +104,8 @@ bool Triangle::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
 		rec.uv = barycentric.x * v2.uv + barycentric.y * v0.uv + barycentric.z * v1.uv;
 		rec.mat_ptr = mat_ptr;
 
+		++rec.rayTriangleIntersectionCount;
+
 		return true;
 	}
 	else
diff --git a/RayTracer/TriangleMesh.cpp b/RayTracer/TriangleMesh.cpp
index 59a4035..b141c62 100644
--- a/RayTracer/TriangleMesh.cpp
+++ b/RayTracer/TriangleMesh.cpp
@@ -16,6 +16,8 @@ TriangleMesh::TriangleMesh(const std::string& path, Material* ptr_mat)
 
 	m_ptrAABB = new AABB();
 
+	m_iTriangleCount = 0;
+
 	LoadModel(path);
 }
 
@@ -91,6 +93,9 @@ void TriangleMesh::ProcessMesh(aiMesh* mesh, const aiScene* scene)
 
 		m_vecTriangles.push_back(tri);
 	}
+
+	// Hold count for triangles...
+	m_iTriangleCount = m_vecTriangles.size();
 }
 
 /////////////////////////////////////////////////////////////////////////////////////////
@@ -99,7 +104,7 @@ bool TriangleMesh::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) con
 	bool isIntersection = false;
 	float closestSoFar = tmax;
 
-	if (m_ptrAABB->hit(r, tmin, tmax))
+	if (m_ptrAABB->hit(r, tmin, tmax, rec))
 	{
 		for (int i = 0; i < m_vecTriangles.size(); i++)
 		{
diff --git a/RayTracer/TriangleMesh.h b/RayTracer/TriangleMesh.h
index dcf3e6b..18f250f 100644
--- a/RayTracer/TriangleMesh.h
+++ b/RayTracer/TriangleMesh.h
@@ -20,6 +20,8 @@ public:
 
 	virtual bool hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const;
 
+	inline int GetTriangleCount() { return m_iTriangleCount; }
+
 private:
 
 	void LoadModel(const std::string& path);
@@ -29,4 +31,6 @@ private:
 	std::vector<Triangle*> m_vecTriangles;
 	AABB*				   m_ptrAABB;
 	Material*			   m_ptrMaterial;
+
+	int					   m_iTriangleCount;
 };
diff --git a/WindowsRayTracer.cpp b/WindowsRayTracer.cpp
index d60e1f2..79f8afe 100644
--- a/WindowsRayTracer.cpp
+++ b/WindowsRayTracer.cpp
@@ -5,6 +5,7 @@
 #include "header.h"
 #include "WindowsRayTracer.h"
 #include "Application.h"
+#include "Profiler.h"
 #include <stdint.h>
 
 #define MAX_LOADSTRING 100
@@ -166,17 +167,23 @@ LRESULT CALLBACK WndProc(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam)
 				pApp->SaveImage();
 				break;
 			}
-			case ID_FILE_RENDERTIME:
+		
+			case ID_PROFILER_RENDERSTATS:
 			{
-				const size_t len = 256;
-				wchar_t buffer[len] = {};
-				swprintf(buffer, L"Total Render Time : %0.2f seconds!", pApp->GetTotalRenderTime());
-				MessageBox(hWnd, buffer, L"Render Time", 0);
+				std::string debugInfo = Profiler::getInstance().GetProfilerTexts();
+			
+				wchar_t wBuffer[1024];
+				mbstowcs(wBuffer, debugInfo.c_str(), debugInfo.size() + 1);
+			
+				MessageBox(hWnd, wBuffer, L"====== PROFILER ======", 0);
 				break;
 			}
+			
             case IDM_EXIT:
-                DestroyWindow(hWnd);
-                break;
+			{
+				DestroyWindow(hWnd);
+				break;
+			}
             default:
                 return DefWindowProc(hWnd, message, wParam, lParam);
             }
diff --git a/WindowsRayTracer.rc b/WindowsRayTracer.rc
index 15a2250..96efcc0 100644
--- a/WindowsRayTracer.rc
+++ b/WindowsRayTracer.rc
@@ -45,9 +45,12 @@ BEGIN
     POPUP "&File"
     BEGIN
         MENUITEM "&Save Image",                 ID_FILE_SAVEIMAGE
-        MENUITEM "&Render Time",                ID_FILE_RENDERTIME
         MENUITEM "E&xit",                       IDM_EXIT
     END
+    POPUP "Profiler"
+    BEGIN
+        MENUITEM "Render Stats",                ID_PROFILER_RENDERSTATS
+    END
     POPUP "&Help"
     BEGIN
         MENUITEM "&About ...",                  IDM_ABOUT
diff --git a/resource.h b/resource.h
index c917536..85a6a1a 100644
--- a/resource.h
+++ b/resource.h
@@ -14,7 +14,7 @@
 #define IDC_WINDOWSRAYTRACER            109
 #define IDR_MAINFRAME                   128
 #define ID_FILE_SAVEIMAGE               32771
-#define ID_FILE_RENDERTIME              32772
+#define ID_PROFILER_RENDERSTATS         32780
 #define IDC_STATIC                      -1
 
 // Next default values for new objects
@@ -23,7 +23,7 @@
 #ifndef APSTUDIO_READONLY_SYMBOLS
 #define _APS_NO_MFC                     1
 #define _APS_NEXT_RESOURCE_VALUE        129
-#define _APS_NEXT_COMMAND_VALUE         32773
+#define _APS_NEXT_COMMAND_VALUE         32781
 #define _APS_NEXT_CONTROL_VALUE         1000
 #define _APS_NEXT_SYMED_VALUE           110
 #endif
```

## `d783830` — 2019-03-04 _(master)_

> Added More data for profiling with uint64_t support.

```diff
diff --git a/Application.cpp b/Application.cpp
index 05fb198..d314dd9 100644
--- a/Application.cpp
+++ b/Application.cpp
@@ -22,9 +22,10 @@ Application::Application()
 	m_bThreaded = false;
 
 	m_iRayCount = 0;
-	m_iRayTriangleTest = 0;
-	m_iRayTriangleIntersections = 0;
-	m_iRayBoxTest = 0;
+	m_iRayTriangleQuery = 0;
+	m_iRayTriangleSuccess = 0;
+	m_iRayBoxQuery = 0;
+	m_iRayBoxSuccess = 0;
 	m_iTriangleCount = 0;
 
 	m_hWnd = NULL;
@@ -64,9 +65,10 @@ void Application::Execute()
 	// Write into Profiler...
 	Profiler::getInstance().WriteToProfiler("Total Render Time: ", m_dTotalRenderTime);
 	Profiler::getInstance().WriteToProfiler("Ray Count: ", m_iRayCount);
-	Profiler::getInstance().WriteToProfiler("Ray Triangle Tests : ", m_iRayTriangleTest);
-	Profiler::getInstance().WriteToProfiler("Ray Triangle Intersections : ", m_iRayTriangleIntersections);
-	Profiler::getInstance().WriteToProfiler("Ray Box Tests : ", m_iRayBoxTest);
+	Profiler::getInstance().WriteToProfiler("Ray Triangle Queries : ", m_iRayTriangleQuery);
+	Profiler::getInstance().WriteToProfiler("Ray Triangle Success : ", m_iRayTriangleSuccess);
+	Profiler::getInstance().WriteToProfiler("Ray Box Queries : ", m_iRayBoxQuery);
+	Profiler::getInstance().WriteToProfiler("Ray Box Success : ", m_iRayBoxSuccess);
 }
 
 ///////////////////////////////////////////////////////////////////////////////////////////////////
@@ -141,9 +143,10 @@ glm::vec3 Application::TraceColor(const Ray & r, int depth, int& rayCount)
 	}
 
 	// debug info...
-	m_iRayTriangleTest += rec.rayTriangleTestCount;
-	m_iRayTriangleIntersections += rec.rayTriangleIntersectionCount;
-	m_iRayBoxTest += rec.rayBoxTestCount;
+	m_iRayTriangleQuery += rec.rayTriangleQuery;
+	m_iRayTriangleSuccess += rec.rayTriangleSuccess;
+	m_iRayBoxQuery += rec.rayBoxQuery;
+	m_iRayBoxSuccess += rec.rayBoxSuccess;
 
 	return traceColor;
 }
diff --git a/Application.h b/Application.h
index 897d5d0..694f1c5 100644
--- a/Application.h
+++ b/Application.h
@@ -35,11 +35,12 @@ private:
 	double			m_dTotalRenderTime;
 	bool			m_bThreaded;
 
-	std::atomic<int>	m_iRayCount;
-	std::atomic<int>    m_iRayTriangleTest;
-	std::atomic<int>    m_iRayTriangleIntersections;
-	std::atomic<int>    m_iRayBoxTest;
-	std::atomic<int>    m_iTriangleCount;
+	std::atomic<uint64_t>	m_iRayCount;
+	std::atomic<uint64_t>    m_iRayTriangleQuery;
+	std::atomic<uint64_t>    m_iRayTriangleSuccess;
+	std::atomic<uint64_t>    m_iRayBoxQuery;
+	std::atomic<uint64_t>	m_iRayBoxSuccess;
+	std::atomic<uint64_t>    m_iTriangleCount;
 
 	HWND			m_hWnd;
 	Camera*			m_pCamera;
diff --git a/Profiler.cpp b/Profiler.cpp
index 99b65dd..6651d04 100644
--- a/Profiler.cpp
+++ b/Profiler.cpp
@@ -1,3 +1,5 @@
+
+#include <inttypes.h>
 #include "Profiler.h"
 
 ///////////////////////////////////////////////////////////////////////////////////////////////////
@@ -39,10 +41,10 @@ void Profiler::WriteToProfiler(const std::string & _inputStr, double _value)
 }
 
 ///////////////////////////////////////////////////////////////////////////////////////////////////
-void Profiler::WriteToProfiler(const std::string & _inputStr, int _value)
+void Profiler::WriteToProfiler(const std::string & _inputStr, uint64_t _value)
 {
 	char buffer[64];
-	sprintf(buffer, "%d", _value);
+	sprintf(buffer, "%" PRId64, _value);
 
 	m_strInfo.append("\n" + _inputStr);
 	m_strInfo.append(buffer);
diff --git a/Profiler.h b/Profiler.h
index ee89c3e..535a708 100644
--- a/Profiler.h
+++ b/Profiler.h
@@ -18,7 +18,7 @@ public:
 	void WriteToProfiler(const std::string& _inputStr);
 	void WriteToProfiler(const std::string& _inputStr, float _value);
 	void WriteToProfiler(const std::string& _inputStr, double _value);
-	void WriteToProfiler(const std::string& _inputStr, int _value);
+	void WriteToProfiler(const std::string& _inputStr, uint64_t _value);
 
 private:
 	Profiler();
diff --git a/RayTracer/AABB.cpp b/RayTracer/AABB.cpp
index 6d649dd..1f76e80 100644
--- a/RayTracer/AABB.cpp
+++ b/RayTracer/AABB.cpp
@@ -24,7 +24,11 @@ void AABB::UpdateBB(const glm::vec3& _pos)
 
 bool AABB::hit(const Ray & r, float tmin, float tmax, HitRecord& rec)
 {
-	++rec.rayBoxTestCount;
+	++rec.rayBoxQuery;
+
+	bool xHit = true; 
+	bool yHit = true;
+	bool zHit = true;
 
 	glm::vec3 rayOrigin = r.GetRayOrigin();
 	glm::vec3 rayDirection = r.GetRayDirection();
@@ -39,7 +43,7 @@ bool AABB::hit(const Ray & r, float tmin, float tmax, HitRecord& rec)
 	tmin = (t0x > tmin) ? t0x : tmin;
 	tmax = (t1x < tmax) ? t1x : tmax;
 	if (tmax <= tmin)
-		return false;
+		xHit = false;
 	
 	// Y Direction
 	float t0y = (minBound.y - rayOrigin.y) * rayInvDirection.y;
@@ -50,7 +54,7 @@ bool AABB::hit(const Ray & r, float tmin, float tmax, HitRecord& rec)
 	tmin = (t0y > tmin) ? t0y : tmin;
 	tmax = (t1y < tmax) ? t1y : tmax;
 	if (tmax <= tmin)
-		return false;
+		yHit = false;
 	
 	// Z Direction
 	float t0z = (minBound.z - rayOrigin.z) * rayInvDirection.z;
@@ -61,7 +65,13 @@ bool AABB::hit(const Ray & r, float tmin, float tmax, HitRecord& rec)
 	tmin = (t0z > tmin) ? t0z : tmin;
 	tmax = (t1z < tmax) ? t1z : tmax;
 	if (tmax <= tmin)
-		return false;
+		zHit = false;
 
-	return true;
+	if (xHit && yHit && zHit)
+	{
+		++rec.rayBoxSuccess;
+		return true;
+	}
+	else
+		return false;
 }
diff --git a/RayTracer/Hitable.h b/RayTracer/Hitable.h
index fb8fc83..7f03a08 100644
--- a/RayTracer/Hitable.h
+++ b/RayTracer/Hitable.h
@@ -14,9 +14,10 @@ struct HitRecord
 		uv = glm::vec2(0);
 		mat_ptr = nullptr;
 
-		rayTriangleTestCount = 0;
-		rayTriangleIntersectionCount = 0;
-		rayBoxTestCount = 0;
+		rayTriangleQuery = 0;
+		rayTriangleSuccess = 0;
+		rayBoxQuery = 0;
+		rayBoxSuccess = 0;
 	}
 
 	float t;
@@ -26,9 +27,10 @@ struct HitRecord
 	Material* mat_ptr;
 
 	// Debug...
-	int rayTriangleTestCount;
-	int rayTriangleIntersectionCount;
-	int rayBoxTestCount;
+	uint64_t rayTriangleQuery;
+	uint64_t rayTriangleSuccess;
+	uint64_t rayBoxQuery;
+	uint64_t rayBoxSuccess;
 };
 
 class Hitable
diff --git a/RayTracer/Scene.cpp b/RayTracer/Scene.cpp
index 736b798..4c07e71 100644
--- a/RayTracer/Scene.cpp
+++ b/RayTracer/Scene.cpp
@@ -43,8 +43,8 @@ void Scene::InitScene()
 	Texture* baseTexture = new ImageTexture("models/car.jpg");
 	Material* pMatMesh = new Lambertian(baseTexture);
 	//Material* pMatMesh = new FlatColor (new ConstantTexture(glm::vec3(1,1,0)));
-	TriangleMesh* pMesh0 = new TriangleMesh("models/UVCube5.fbx", pMatMesh);
-	//TriangleMesh* pMesh0 = new TriangleMesh("models/car.fbx", pMatMesh);
+	//TriangleMesh* pMesh0 = new TriangleMesh("models/UVCube5.fbx", pMatMesh);
+	TriangleMesh* pMesh0 = new TriangleMesh("models/car.fbx", pMatMesh);
 
 	Profiler::getInstance().WriteToProfiler("Triangle Count:", pMesh0->GetTriangleCount());
 
@@ -120,6 +120,13 @@ bool Scene::Trace(const Ray& r, int& rayCount, float tmin, float tmax, HitRecord
 			closest_so_far = temp_rec.t;
 			rec = temp_rec;
 		}
+		else
+		{
+			// This is needed for Profile information
+			// If ray doesn't hit anything, still it could have done BBox query or
+			// Traiangle Query which needs to be accumulated..!
+			rec = temp_rec;
+		}
 	}
 
 	return hit_anything;
diff --git a/RayTracer/Triangle.cpp b/RayTracer/Triangle.cpp
index 4c0fd38..e3c4c60 100644
--- a/RayTracer/Triangle.cpp
+++ b/RayTracer/Triangle.cpp
@@ -6,7 +6,7 @@
 /////////////////////////////////////////////////////////////////////////////////////////
 bool Triangle::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
 {
-	++rec.rayTriangleTestCount;
+	++rec.rayTriangleQuery;
 
 	glm::vec3 rayDirection = r.GetRayDirection();
 	glm::vec3 rayOrigin = r.GetRayOrigin();
@@ -104,7 +104,7 @@ bool Triangle::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
 		rec.uv = barycentric.x * v2.uv + barycentric.y * v0.uv + barycentric.z * v1.uv;
 		rec.mat_ptr = mat_ptr;
 
-		++rec.rayTriangleIntersectionCount;
+		++rec.rayTriangleSuccess;
 
 		return true;
 	}
diff --git a/RayTracer/TriangleMesh.cpp b/RayTracer/TriangleMesh.cpp
index b141c62..d6429ef 100644
--- a/RayTracer/TriangleMesh.cpp
+++ b/RayTracer/TriangleMesh.cpp
@@ -104,7 +104,7 @@ bool TriangleMesh::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) con
 	bool isIntersection = false;
 	float closestSoFar = tmax;
 
-	if (m_ptrAABB->hit(r, tmin, tmax, rec))
+	//if (m_ptrAABB->hit(r, tmin, tmax, rec))
 	{
 		for (int i = 0; i < m_vecTriangles.size(); i++)
 		{
diff --git a/RayTracer/TriangleMesh.h b/RayTracer/TriangleMesh.h
index 18f250f..b4d7a97 100644
--- a/RayTracer/TriangleMesh.h
+++ b/RayTracer/TriangleMesh.h
@@ -20,7 +20,7 @@ public:
 
 	virtual bool hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const;
 
-	inline int GetTriangleCount() { return m_iTriangleCount; }
+	inline uint64_t GetTriangleCount() { return m_iTriangleCount; }
 
 private:
 
@@ -32,5 +32,5 @@ private:
 	AABB*				   m_ptrAABB;
 	Material*			   m_ptrMaterial;
 
-	int					   m_iTriangleCount;
+	uint64_t			   m_iTriangleCount;
 };
```

## `cbb7202` — 2019-04-04 _(master)_

> - Added Profiler system - Added BVH implementation

```diff
diff --git a/Application.cpp b/Application.cpp
index d314dd9..6bd2204 100644
--- a/Application.cpp
+++ b/Application.cpp
@@ -15,9 +15,9 @@
 ///////////////////////////////////////////////////////////////////////////////////////////////////
 Application::Application()
 {
-	m_iBackbufferWidth = 480;
-	m_iBackbufferHeight = 270;
-	m_iNumSamples = 1;
+	m_iBackbufferWidth = 960;
+	m_iBackbufferHeight = 540;
+	m_iNumSamples = 10;
 	m_dTotalRenderTime = 0;
 	m_bThreaded = false;
 
@@ -55,12 +55,12 @@ void Application::Execute()
 	int percentageDone = 0.0f;
 
 	const clock_t begin_time = clock();
-	double counter = 0;
+	float counter = 0;
 
 	Trace();
 
 	const clock_t end_time = clock();
-	m_dTotalRenderTime = (end_time - begin_time) / (double)CLOCKS_PER_SEC;
+	m_dTotalRenderTime = (end_time - begin_time) / (float)CLOCKS_PER_SEC;
 
 	// Write into Profiler...
 	Profiler::getInstance().WriteToProfiler("Total Render Time: ", m_dTotalRenderTime);
@@ -120,25 +120,25 @@ void Application::SaveImage()
 glm::vec3 Application::TraceColor(const Ray & r, int depth, int& rayCount)
 {
 	HitRecord rec;
-	glm::vec3 traceColor = glm::vec3(0);
+	glm::vec3 traceColor = glm::vec3(0.0f, 0.0f, 0.0f);
 
 	if (Scene::getInstance().Trace(r, rayCount, 0.001f, FLT_MAX, rec))
 	{
 		Ray scatteredRay;
-		glm::vec3 attenuation = glm::vec3(0);
+		glm::vec3 attenuation = glm::vec3(0.0f, 0.0f, 0.0f);
 
 		if (depth < 50 && rec.mat_ptr->Scatter(r, rec, rayCount, attenuation, scatteredRay))
 		{
-			if (glm::distance(scatteredRay.GetRayOrigin(), scatteredRay.GetRayDirection()) < 0.0000001f)
+			if (glm::length(scatteredRay.GetRayOrigin() - scatteredRay.GetRayDirection()) < 0.0000001f)
 				traceColor = attenuation;
 			else
-				traceColor = attenuation * TraceColor(scatteredRay, depth + 1, rayCount);
+				traceColor = attenuation * (TraceColor(scatteredRay, depth + 1, rayCount));
 		}
 	}
 	else
 	{
 		glm::vec3 unit_direction = glm::normalize(r.GetRayDirection());
-		float t = 0.5f * (unit_direction.y + 1.0f);
+		float t = 0.5f * (unit_direction[1] + 1.0f);
 		traceColor = Helper::LerpVector(glm::vec3(1.0f, 1.0f, 1.0f), glm::vec3(0.5f, 0.7f, 1.0f), t);
 	}
 
@@ -207,11 +207,11 @@ void Application::ParallelTrace(std::mutex * threadMutex, int i)
 				}
 
 				color = color / float(ns);
-				color = glm::vec3(sqrt(color.x), sqrt(color.y), sqrt(color.z));
+				color = glm::vec3(sqrt(color[0]), sqrt(color[1]), sqrt(color[2]));
 
-				float ir = (255.99f * color.x);
-				float ig = (255.99f * color.y);
-				float ib = (255.99f * color.z);
+				float ir = (255.99f * color[0]);
+				float ig = (255.99f * color[1]);
+				float ib = (255.99f * color[2]);
 
 				SetPixel(hdc, backBufferWidth - i, backBufferHeight - j, RGB(ir, ig, ib));
 				//++counter;
@@ -272,11 +272,11 @@ void Application::Trace()
 				}
 
 				color = color / float(m_iNumSamples);
-				color = glm::vec3(sqrt(color.x), sqrt(color.y), sqrt(color.z));
+				color = glm::vec3(sqrt(color[0]), sqrt(color[1]), sqrt(color[2]));
 
-				float ir = (255.99f*color.x);
-				float ig = (255.99f*color.y);
-				float ib = (255.99f*color.z);
+				float ir = (255.99f*color[0]);
+				float ig = (255.99f*color[1]);
+				float ib = (255.99f*color[2]);
 
 				//float ir = 255.99f;
 				//float ig = 128.99f;
diff --git a/Application.h b/Application.h
index 694f1c5..a063cac 100644
--- a/Application.h
+++ b/Application.h
@@ -20,7 +20,7 @@ public:
 
 	inline int		GetBufferWidth() { return m_iBackbufferWidth; }
 	inline int		GetBufferHeight() { return m_iBackbufferHeight; }
-	inline double	GetTotalRenderTime() { return m_dTotalRenderTime; }
+	inline float	GetTotalRenderTime() { return m_dTotalRenderTime; }
 
 private:
 	glm::vec3		TraceColor(const Ray& r, int depth, int& rayCount);
@@ -32,7 +32,7 @@ private:
 	int				m_iBackbufferHeight;
 	int				m_iNumSamples;
 	int				m_iMaxThreads;
-	double			m_dTotalRenderTime;
+	float			m_dTotalRenderTime;
 	bool			m_bThreaded;
 
 	std::atomic<uint64_t>	m_iRayCount;
diff --git a/Profiler.cpp b/Profiler.cpp
index 6651d04..7c511f1 100644
--- a/Profiler.cpp
+++ b/Profiler.cpp
@@ -30,16 +30,6 @@ void Profiler::WriteToProfiler(const std::string & _inputStr, float _value)
 	m_strInfo.append(buffer);
 }
 
-///////////////////////////////////////////////////////////////////////////////////////////////////
-void Profiler::WriteToProfiler(const std::string & _inputStr, double _value)
-{
-	char buffer[64];
-	sprintf(buffer, "%.2f", _value);
-
-	m_strInfo.append("\n" + _inputStr);
-	m_strInfo.append(buffer);
-}
-
 ///////////////////////////////////////////////////////////////////////////////////////////////////
 void Profiler::WriteToProfiler(const std::string & _inputStr, uint64_t _value)
 {
diff --git a/Profiler.h b/Profiler.h
index 535a708..223c54e 100644
--- a/Profiler.h
+++ b/Profiler.h
@@ -17,7 +17,6 @@ public:
 
 	void WriteToProfiler(const std::string& _inputStr);
 	void WriteToProfiler(const std::string& _inputStr, float _value);
-	void WriteToProfiler(const std::string& _inputStr, double _value);
 	void WriteToProfiler(const std::string& _inputStr, uint64_t _value);
 
 private:
diff --git a/RayTracer/AABB.cpp b/RayTracer/AABB.cpp
index 1f76e80..f5c2dbc 100644
--- a/RayTracer/AABB.cpp
+++ b/RayTracer/AABB.cpp
@@ -6,22 +6,45 @@
 /////////////////////////////////////////////////////////////////////////////////////////////////////
 AABB::AABB()
 {
-	minBound = glm::vec3(0);
-	maxBound = glm::vec3(0);
+	minBound = glm::vec3(0.0f, 0.0f, 0.0f);
+	maxBound = glm::vec3(0.0f, 0.0f, 0.0f);
 }
 
 /////////////////////////////////////////////////////////////////////////////////////////////////////
-void AABB::UpdateBB(const glm::vec3& _pos)
+int AABB::GetLongestAxis()
 {
-	if (_pos.x < minBound.x) { minBound.x = _pos.x; }
-	if (_pos.y < minBound.y) { minBound.y = _pos.y; }
-	if (_pos.z < minBound.z) { minBound.z = _pos.z; }
+	glm::vec3 axis = maxBound - minBound;
 
-	if (_pos.x > maxBound.x) { maxBound.x = _pos.x; }
-	if (_pos.y > maxBound.y) { maxBound.y = _pos.y; }
-	if (_pos.z > maxBound.z) { maxBound.z = _pos.z; }
+	if (axis[0] > axis[1] && axis[0] > axis[2]) return eLongestAxis::X_AXIS;
+	if (axis[1] > axis[0] && axis[1] > axis[2]) return eLongestAxis::Y_AXIS;
+	if (axis[2] > axis[0] && axis[2] > axis[1]) return eLongestAxis::Z_AXIS;
+
+	return 0;
+}
+
+/////////////////////////////////////////////////////////////////////////////////////////////////////
+glm::vec3 AABB::GetCentroidPoint()
+{
+	return glm::vec3(0.5f * minBound + 0.5f * maxBound);
 }
 
+/////////////////////////////////////////////////////////////////////////////////////////////////////
+void AABB::ExpandBoundingBox(const AABB& _box)
+{
+	minBound = glm::vec3(fminf(_box.minBound[0], minBound[0]), fminf(_box.minBound[1], minBound[1]), fminf(_box.minBound[2], minBound[2]));
+	maxBound = glm::vec3(fmaxf(_box.maxBound[0], maxBound[0]), fmaxf(_box.maxBound[1], maxBound[1]), fmaxf(_box.maxBound[2], maxBound[2]));
+}
+
+/////////////////////////////////////////////////////////////////////////////////////////////////////
+AABB AABB::GetSurroundingBBox(const AABB & _box0, const AABB & _box1)
+{
+	glm::vec3 minBound = glm::vec3(fminf(_box0.minBound[0], _box1.minBound[0]), fminf(_box0.minBound[1], _box1.minBound[1]), fminf(_box0.minBound[2], _box1.minBound[2]));
+	glm::vec3 maxBound = glm::vec3(fmaxf(_box0.maxBound[0], _box1.maxBound[0]), fmaxf(_box0.maxBound[1], _box1.maxBound[1]), fmaxf(_box0.maxBound[2], _box1.maxBound[2]));
+
+	return AABB(minBound, maxBound);
+}
+
+/////////////////////////////////////////////////////////////////////////////////////////////////////
 bool AABB::hit(const Ray & r, float tmin, float tmax, HitRecord& rec)
 {
 	++rec.rayBoxQuery;
@@ -35,9 +58,9 @@ bool AABB::hit(const Ray & r, float tmin, float tmax, HitRecord& rec)
 	glm::vec3 rayInvDirection = r.GetInvRayDirection();
 	
 	// Direction X
-	float t0x = (minBound.x - rayOrigin.x) * rayInvDirection.x;
-	float t1x = (maxBound.x - rayOrigin.x) * rayInvDirection.x;
-	if (rayInvDirection.x < 0.0f)
+	float t0x = (minBound[0] - rayOrigin[0]) * rayInvDirection[0];
+	float t1x = (maxBound[0] - rayOrigin[0]) * rayInvDirection[0];
+	if (rayInvDirection[0] < 0.0f)
 		std::swap(t0x, t1x);
 	
 	tmin = (t0x > tmin) ? t0x : tmin;
@@ -46,9 +69,9 @@ bool AABB::hit(const Ray & r, float tmin, float tmax, HitRecord& rec)
 		xHit = false;
 	
 	// Y Direction
-	float t0y = (minBound.y - rayOrigin.y) * rayInvDirection.y;
-	float t1y = (maxBound.y - rayOrigin.y) * rayInvDirection.y;
-	if (rayInvDirection.y < 0.0f)
+	float t0y = (minBound[1] - rayOrigin[1]) * rayInvDirection[1];
+	float t1y = (maxBound[1] - rayOrigin[1]) * rayInvDirection[1];
+	if (rayInvDirection[1] < 0.0f)
 		std::swap(t0y, t1y);
 	
 	tmin = (t0y > tmin) ? t0y : tmin;
@@ -57,9 +80,9 @@ bool AABB::hit(const Ray & r, float tmin, float tmax, HitRecord& rec)
 		yHit = false;
 	
 	// Z Direction
-	float t0z = (minBound.z - rayOrigin.z) * rayInvDirection.z;
-	float t1z = (maxBound.z - rayOrigin.z) * rayInvDirection.z;
-	if (rayInvDirection.z < 0.0f)
+	float t0z = (minBound[2] - rayOrigin[2]) * rayInvDirection[2];
+	float t1z = (maxBound[2] - rayOrigin[2]) * rayInvDirection[2];
+	if (rayInvDirection[1] < 0.0f)
 		std::swap(t0z, t1z);
 	
 	tmin = (t0z > tmin) ? t0z : tmin;
diff --git a/RayTracer/AABB.h b/RayTracer/AABB.h
index 5b6e8d4..a55fe9b 100644
--- a/RayTracer/AABB.h
+++ b/RayTracer/AABB.h
@@ -1,10 +1,17 @@
 #pragma once
 
-#include "glm\glm.hpp"
+#include "glm/glm.hpp"
 #include "Ray.h"
 
 struct HitRecord;
 
+enum eLongestAxis
+{
+	X_AXIS = 0,
+	Y_AXIS,
+	Z_AXIS
+};
+
 class AABB
 {
 public:
@@ -14,10 +21,14 @@ public:
 		minBound(_min),
 		maxBound(_max) {}
 
-	void UpdateBB(const glm::vec3& _pos);
-	bool hit(const Ray& r, float tmin, float tmax, HitRecord& rec);
+	int			GetLongestAxis();
+	glm::vec3	GetCentroidPoint();
+
+	void		ExpandBoundingBox(const AABB& _box);
+	AABB		GetSurroundingBBox(const AABB& _box0, const AABB& _box1);
+
+	bool		hit(const Ray& r, float tmin, float tmax, HitRecord& rec);
 
-private:
-	glm::vec3 minBound;
-	glm::vec3 maxBound;
+	glm::vec3	minBound;		// top back left
+	glm::vec3	maxBound;		// bottom right front
 };
\ No newline at end of file
diff --git a/RayTracer/Camera.cpp b/RayTracer/Camera.cpp
index 0132b56..98588a3 100644
--- a/RayTracer/Camera.cpp
+++ b/RayTracer/Camera.cpp
@@ -29,7 +29,7 @@ void Camera::InitCamera(float screenWidth, float screenHeight)
 	origin = lookFrom;
 	w = glm::normalize(lookFrom - lookAt);
 	u = glm::normalize(glm::cross(Up, w));
-	v = glm::cross(w, u);
+	v = glm::normalize(glm::cross(w, u));
 
 	lower_left_corner = origin - half_width * focus_dist * u - half_height * focus_dist * v - focus_dist * w;
 	horizontal = 2 * half_width * focus_dist * u;
@@ -39,7 +39,7 @@ void Camera::InitCamera(float screenWidth, float screenHeight)
 Ray Camera::get_ray(float s, float t)
 {
 	glm::vec3 rd = lens_radius * Helper::GetRandomInUnitDisk();
-	glm::vec3 offset = rd.x * u + rd.y * v;
+	glm::vec3 offset = rd[0] * u + rd[1] * v;
 	return Ray(origin + offset, lower_left_corner + s * horizontal + t * vertical - origin - offset);
 }
 
diff --git a/RayTracer/Helper.h b/RayTracer/Helper.h
index 3f47377..1af822c 100644
--- a/RayTracer/Helper.h
+++ b/RayTracer/Helper.h
@@ -14,9 +14,9 @@ namespace Helper
 		return (1.0f - t) * vec1 + t * vec2;
 	}
 
-	inline double GetRandom01()
+	inline float GetRandom01()
 	{
-		return ((double)rand() / (RAND_MAX + 1));
+		return ((float)rand() / (RAND_MAX + 1));
 	}
 
 	inline glm::vec3 GetRandomInUnitDisk()
@@ -42,6 +42,11 @@ namespace Helper
 		return P;
 	}
 
+	inline glm::vec3 Reflect(const glm::vec3& dir, const glm::vec3& normal)
+	{
+		return (dir - 2.0f * glm::dot(dir, normal) * normal);
+	}
+
 	inline bool Refract(const glm::vec3& v, const glm::vec3& n, float ni_over_nt, glm::vec3& refracted)
 	{
 		glm::vec3 unit_v = glm::normalize(v);
diff --git a/RayTracer/Hitable.h b/RayTracer/Hitable.h
index 7f03a08..93a56aa 100644
--- a/RayTracer/Hitable.h
+++ b/RayTracer/Hitable.h
@@ -3,15 +3,16 @@
 #include "Ray.h"
 
 class Material;
+class AABB;
 
 struct HitRecord
 {
 	HitRecord()
 	{
 		t = 0.0f;
-		P = glm::vec3(0);
-		N = glm::vec3(0);
-		uv = glm::vec2(0);
+		P = glm::vec3(0.0f, 0.0f, 0.0f);
+		N = glm::vec3(0.0f, 0.0f, 0.0f);
+		uv = glm::vec2(0.0f, 0.0f);
 		mat_ptr = nullptr;
 
 		rayTriangleQuery = 0;
@@ -37,4 +38,5 @@ class Hitable
 {
 public:
 	virtual bool hit(const Ray& r, float t_min, float t_max, HitRecord& rec) const = 0;
+	virtual void BoundingBox(AABB& box) const = 0;
 };
\ No newline at end of file
diff --git a/RayTracer/LameBVH.cpp b/RayTracer/LameBVH.cpp
new file mode 100644
index 0000000..16e6e7e
--- /dev/null
+++ b/RayTracer/LameBVH.cpp
@@ -0,0 +1,345 @@
+
+#include "LameBVH.h"
+#include <algorithm>
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+BVHTree::BVHTree()
+{
+	m_pRootNode = nullptr;
+	m_uiNumNodes = 0;
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+BVHTree::~BVHTree()
+{
+	if (m_pRootNode)
+	{
+		delete m_pRootNode;
+		m_pRootNode = nullptr;
+	}
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+bool BVHTree::hit(const Ray & ray, float tMin, float tMax, HitRecord & rec) const
+{
+	if (!m_pRootNode)
+		return false;
+
+	float closestSoFar = tMax;
+	if (m_pRootNode->bbox.hit(ray, tMin, tMax, rec))
+	{
+		bool hit = Hit(m_pRootNode, ray, tMin, tMax, rec);
+		return hit;
+	}
+
+	return false;
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void BVHTree::BoundingBox(AABB & box) const
+{
+	box = m_pRootNode->bbox;
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+bool BVHTree::Hit(BVHNode * node, const Ray & ray, float & tMin, float & tMax, HitRecord & rec) const
+{
+	bool isIntersection = false;
+
+	// We are not at a leaf node so check the left and right node of the current node
+	if (!node->isLeaf)
+	{
+		float tL0 = 0.0001f;
+		float tL1 = FLT_MAX;
+
+		float tR0 = 0.0001f;
+		float tR1 = FLT_MAX;
+
+		BVHNode *firstNode = 0;
+		BVHNode *secondNode = 0;
+		BVHNode *leftNode = node->leftNode;
+
+		if (leftNode)
+		{
+			bool intersectedL = leftNode->bbox.hit(ray, tL0, tL1, rec);
+			if (intersectedL && tL0 <= tMax)
+			{
+				firstNode = leftNode;
+			}
+		}
+
+		BVHNode *rightNode = node->rightNode;
+		if (rightNode)
+		{
+			bool intersectedR = rightNode->bbox.hit(ray, tR0, tR1, rec);
+			if (intersectedR && tR0 <= tMax)
+			{
+				secondNode = rightNode;
+			}
+		}
+
+		if (firstNode)
+		{
+			float thit1 = tMax;
+			bool isIntersect1 = Hit(firstNode, ray, tMin, thit1, rec);
+
+			if (isIntersect1 && thit1 < tMax)
+			{
+				tMax = thit1;
+				isIntersection = true;
+			}
+		}
+
+		if (secondNode)
+		{
+			float thit2 = tMax;
+
+			bool isIntersect2 = Hit(secondNode, ray, tMin, thit2, rec);
+
+			if (isIntersect2 && thit2 < tMax)
+			{
+				tMax = thit2;
+				isIntersection = true;
+			}
+		}
+
+	}
+	// Check intersection for all triangles contained in the leaf node
+	else
+	{
+		uint64_t startIndex = node->startIndex;
+		uint64_t noOfTriangles = node->numTriangles;
+
+		for (uint64_t i = startIndex; i < startIndex + noOfTriangles; i++)
+		{
+			if (primsVector->at(i)->hit(ray, tMin, tMax, rec))
+			{
+				isIntersection = true;
+				// Record the closest hit
+				tMax = rec.t;
+			}
+		}
+	}
+
+	return isIntersection;
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void BVHTree::BuildBVHTree(std::vector<Triangle*> *listTris, int _leafSize)
+{
+	if (!m_pRootNode)
+	{
+		// 1. Create a Root Node
+		m_pRootNode = new BVHNode();
+
+		// 2. Create AABB for every object in the scene.
+		std::vector<Triangle*>::iterator iter = listTris->begin();
+		AABB worldBB;
+		for (; iter != listTris->end() ; iter++)
+		{
+			AABB tempBB;
+			(*iter)->BoundingBox(tempBB);
+			worldBB.ExpandBoundingBox(tempBB);
+		}
+
+		// 3. Assign AABB box to Root node.
+		m_pRootNode->bbox = worldBB;
+		m_pRootNode->startIndex = 0;
+	}
+
+	int leftIndex = 0;
+	int rightIndex = listTris->size();
+
+	m_iLeafSize = _leafSize;
+
+	primsVector = listTris;
+	BuildRecursive(leftIndex, rightIndex, m_pRootNode);
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void BVHTree::BuildRecursive(int startIndex, int endIndex, BVHNode * node)
+{
+	if ((endIndex - startIndex) <= m_iLeafSize)
+	{
+		node->isLeaf = true;
+		node->startIndex = startIndex;
+		node->numTriangles = endIndex - startIndex;
+
+		m_uiNumNodes++;
+	}
+	else
+	{
+		// 4. Find AABB's longest axis & sort each object along this direction
+		int longestAxis = node->bbox.GetLongestAxis();
+		//float axisMidPoint = 0.0f;
+		glm::vec3 nodeAxis = node->bbox.minBound + node->bbox.maxBound;
+		float axisMidPoint = nodeAxis[longestAxis] * 0.5f;
+
+		switch (longestAxis)
+		{
+		case 0:
+		{
+			//axisMidPoint = (node->bbox.maxBound[0] - node->bbox.minBound[0]) * 0.5f;
+			std::sort(primsVector->begin() + startIndex, primsVector->begin() + endIndex, CompareBB_X);
+			break;
+		}
+
+		case 1:
+		{
+			//axisMidPoint = (node->bbox.maxBound[1] - node->bbox.minBound[1]) * 0.5f;
+			std::sort(primsVector->begin() + startIndex, primsVector->begin() + endIndex, CompareBB_Y);
+			break;
+		}
+
+		case 2:
+		{
+			//axisMidPoint = (node->bbox.maxBound[2] - node->bbox.minBound[2]) * 0.5f;
+			std::sort(primsVector->begin() + startIndex, primsVector->begin() + endIndex, CompareBB_Z);
+			break;
+		}
+		}
+
+		// 5. Find split index according to midPoint on largest axis
+		int splitIndex = startIndex;
+		for (int i = startIndex; i < endIndex; i++)
+		{
+			glm::vec3 centroid = primsVector->at(i)->Centroid();
+			if (centroid[longestAxis] > axisMidPoint)
+			{
+				splitIndex = i;
+				break;
+			}
+		}
+
+		// 6. Using split index, divide the scene into left & right side
+		// 7. For each side, create an AABB containing their respective objects
+		AABB leftBB;
+		primsVector->at(startIndex)->BoundingBox(leftBB);
+		for (int i = startIndex+1; i < splitIndex; i++)
+		{
+			AABB tempBB;
+			primsVector->at(i)->BoundingBox(tempBB);
+			leftBB.ExpandBoundingBox(tempBB);
+		}
+
+		AABB rightBB;
+		primsVector->at(splitIndex)->BoundingBox(rightBB);
+		for (int i = splitIndex + 1; i < endIndex; i++)
+		{
+			AABB tempBB;
+			primsVector->at(i)->BoundingBox(tempBB);
+			rightBB.ExpandBoundingBox(tempBB);
+		}
+
+		// 8. Create a left & right node in the binary tree & attach it's corresponding BB.
+		BVHNode* leftNode = new BVHNode();
+		BVHNode* rightNode = new BVHNode();
+
+		leftNode->bbox = leftBB;
+		rightNode->bbox = rightBB;
+
+		node->leftNode = leftNode;
+		node->rightNode = rightNode;
+
+		BuildRecursive(startIndex, splitIndex, leftNode);
+		BuildRecursive(splitIndex + 1, endIndex, rightNode);
+	}
+	
+
+	//if ((rightIndex - leftIndex) <= 1)
+	//{
+	//	node->isLeaf = true;
+	//	node->startIndex = leftIndex;
+	//}
+	//else
+	//{
+	//	int longestAxis = node->bbox.GetLongestAxis();
+	//	glm::vec3 nodeAxis = (node->bbox.minBound + node->bbox.maxBound);
+	//	float midPointOnAxis = nodeAxis[longestAxis] * 0.5f;
+	//
+	//	switch (longestAxis)
+	//	{
+	//	case 0:
+	//	{
+	//		std::sort(primsVector->begin() + leftIndex, primsVector->begin() + rightIndex, CompareBB_X);
+	//		break;
+	//	}
+	//
+	//	case 1:
+	//	{
+	//		std::sort(primsVector->begin() + leftIndex, primsVector->begin() + rightIndex, CompareBB_Y);
+	//		break;
+	//	}
+	//
+	//	case 2:
+	//	{
+	//		std::sort(primsVector->begin() + leftIndex, primsVector->begin() + rightIndex, CompareBB_Z);
+	//		break;
+	//	}
+	//	}
+	//
+	//	
+	//	int splitIndex = leftIndex;
+	//	for (int i = leftIndex; i < rightIndex; i++)
+	//	{
+	//		glm::vec3 centroid = primsVector->at(i)->Centroid();
+	//		
+	//		if (centroid[longestAxis] > midPointOnAxis)
+	//		{
+	//			splitIndex = i;
+	//			break;
+	//		}
+	//	}
+	//
+	//	BVHNode* leftNode = new BVHNode();
+	//	BVHNode* rightNode = new BVHNode();
+	//
+	//	AABB leftBB;
+	//	primsVector->at(leftIndex)->BoundingBox(leftBB);
+	//	for (int i = leftIndex + 1; i < splitIndex; i++)
+	//	{
+	//		AABB tempBB;
+	//		primsVector->at(i)->BoundingBox(tempBB);
+	//		leftBB.ExpandBoundingBox(tempBB);
+	//	}
+	//
+	//	AABB rightBB;
+	//	primsVector->at(splitIndex)->BoundingBox(rightBB);
+	//	for (int i = splitIndex + 1; i < rightIndex; i++)
+	//	{
+	//		AABB tempBB;
+	//		primsVector->at(i)->BoundingBox(tempBB);
+	//		rightBB.ExpandBoundingBox(tempBB);
+	//	}
+	//
+	//	leftNode->bbox = leftBB;
+	//	rightNode->bbox = rightBB;
+	//
+	//	node->leftNode = leftNode;
+	//	node->rightNode = rightNode;
+	//
+	//	BuildRecursive(leftIndex, splitIndex, leftNode);
+	//	BuildRecursive(splitIndex, rightIndex, rightNode);
+	//}
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+bool BVHTree::CompareBB_X(const Triangle * first, const Triangle * second)
+{
+	return (first->Centroid()[0] < second->Centroid()[0]);
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+bool BVHTree::CompareBB_Y(const Triangle * first, const Triangle * second)
+{
+	return (first->Centroid()[1] < second->Centroid()[1]);
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+bool BVHTree::CompareBB_Z(const Triangle * first, const Triangle * second)
+{
+	return (first->Centroid()[2] < second->Centroid()[2]);
+}
+
+
+
diff --git a/RayTracer/LameBVH.h b/RayTracer/LameBVH.h
new file mode 100644
index 0000000..c750deb
--- /dev/null
+++ b/RayTracer/LameBVH.h
@@ -0,0 +1,73 @@
+///////////////////////////////////////////////////////////////////////////////////////////////////
+// Based on Implementation by : https://github.com/DarrenSweeney/Dazzer_Ray
+///////////////////////////////////////////////////////////////////////////////////////////////////
+
+#pragma once
+
+#include "AABB.h"
+#include "Triangle.h"
+
+#include <vector>
+
+class Triangle;
+
+struct BVHNode
+{
+	BVHNode()
+	{
+		leftNode = nullptr;
+		rightNode = nullptr;
+		isLeaf = false;
+		startIndex = 0;
+		numTriangles = 0;
+	}
+
+	~BVHNode()
+	{
+		if (!isLeaf)
+		{
+			if (leftNode)
+			{
+				delete leftNode;
+				leftNode = nullptr;
+			}
+
+			if (rightNode)
+			{
+				delete rightNode;
+				rightNode = nullptr;
+			}
+		}
+	}
+
+	BVHNode* leftNode;
+	BVHNode* rightNode;
+	AABB	 bbox;
+	bool	 isLeaf;
+	uint64_t startIndex;
+	uint64_t numTriangles;
+};
+
+class BVHTree : public Hitable
+{
+public:
+	BVHTree();
+	~BVHTree();
+
+	virtual bool hit(const Ray& ray, float tMin, float tMax, HitRecord& rec) const;
+	virtual void BoundingBox(AABB& box) const;
+
+	bool Hit(BVHNode *node, const Ray &ray, float &tMin, float &tMax, HitRecord &rec) const;
+	void BuildBVHTree(std::vector<Triangle*> *listTris, int _leafSize);
+	void BuildRecursive(int startIndex, int endIndex, BVHNode* node);
+
+	static bool CompareBB_X(const Triangle * first, const Triangle * second);
+	static bool CompareBB_Y(const Triangle * first, const Triangle * second);
+	static bool CompareBB_Z(const Triangle * first, const Triangle * second);
+
+private:
+	BVHNode*	m_pRootNode;
+	uint64_t	m_uiNumNodes;
+	int			m_iLeafSize;
+	std::vector<Triangle*> *primsVector;
+};
diff --git a/RayTracer/Metal.cpp b/RayTracer/Metal.cpp
index a747478..8f28466 100644
--- a/RayTracer/Metal.cpp
+++ b/RayTracer/Metal.cpp
@@ -4,7 +4,7 @@
 
 bool Metal::Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& attenuation, Ray& scatterd) const
 {
-	glm::vec3 target = glm::reflect(glm::normalize(r_in.GetRayDirection()), rec.N);
+	glm::vec3 target = glm::normalize(Helper::Reflect(r_in.GetRayDirection(), rec.N));
 	scatterd = Ray(rec.P, target + fuzz * Helper::RandomInUnitSphere());
 	++rayCount;
 
diff --git a/RayTracer/Ray.h b/RayTracer/Ray.h
index ca7f846..96ef8d8 100644
--- a/RayTracer/Ray.h
+++ b/RayTracer/Ray.h
@@ -7,9 +7,9 @@ class Ray
 public:
 	Ray() 
 	{
-		origin = glm::vec3(0);
-		direction = glm::vec3(1);
-		invDirection = glm::vec3(1);
+		origin = glm::vec3(0.0f, 0.0f, 0.0f);
+		direction = glm::vec3(1.0f, 1.0f, 1.0f);
+		invDirection = glm::vec3(1.0f, 1.0f, 1.0f);
 	}
 
 	Ray(const glm::vec3& A, const glm::vec3& B) 
@@ -17,7 +17,7 @@ public:
 		origin = A;
 		direction = B; 
 
-		invDirection = glm::vec3(1 / direction.x, 1/direction.y, 1/direction.z);
+		invDirection = glm::vec3(1.0f / direction[0], 1.0f/direction[1], 1.0f/direction[2]);
 	}
 
 	inline glm::vec3 GetRayOrigin() const { return origin; }
diff --git a/RayTracer/Scene.cpp b/RayTracer/Scene.cpp
index 4c07e71..cdf7149 100644
--- a/RayTracer/Scene.cpp
+++ b/RayTracer/Scene.cpp
@@ -26,32 +26,32 @@ Scene::~Scene()
 void Scene::InitScene()
 {
 	glm::vec3 center0(-3.0f, 0.15f, 0);
-	glm::vec3 albedo0(1, 0, 0);
-	Material* pMatSphere0 = new Metal(new ConstantTexture(glm::vec3(1.0, 0.3, 0.0)), 0);
+	glm::vec3 albedo0(1.0f, 0.0f, 0.0f);
+	Material* pMatSphere0 = new Metal(new ConstantTexture(glm::vec3(1.0f, 0.3f, 0.0f)), 0);
 	Sphere* pSphere0 = new Sphere(center0, 0.8f, pMatSphere0);
 
 	// Sphere2
-	glm::vec3 center1(0, -100.5, 0);
-	glm::vec3 albedo1(0.2);
+	glm::vec3 center1(0.0f, -100.5f, 0.0f);
+	glm::vec3 albedo1(0.2f, 0.2f, 0.2f);
 	Material* pMatSphere1 = new Lambertian(new ConstantTexture(albedo1));
 	Sphere* pSphere1 = new Sphere(center1, 100.0f, pMatSphere1);
 
-	Sphere* pSphere2 = new Sphere(glm::vec3(-1.0, 0.0f, 1.5f), 0.5f, new Transparent(1.5f));
-	Sphere* pSphere3 = new Sphere(glm::vec3(-4.0f, 0.4f, 0.0f), 1.0f, new Metal(new ConstantTexture(glm::vec3(1.0, 0.1, 0.0)), 0));
-	Sphere* pSphere4 = new Sphere(glm::vec3(2.5f, 0.0f, 0), 0.5, new Lambertian(new ImageTexture("models/earth.jpg")));
+	Sphere* pSphere2 = new Sphere(glm::vec3(-1.0f, 0.0f, 1.5f), 0.5f, new Transparent(1.5f));
+	Sphere* pSphere3 = new Sphere(glm::vec3(-4.0f, 0.4f, 0.0f), 1.0f, new Metal(new ConstantTexture(glm::vec3(1.0f, 0.1f, 0.0f)), 0));
+	Sphere* pSphere4 = new Sphere(glm::vec3(2.5f, 0.0f, 0.0f), 0.5, new Lambertian(new ImageTexture("models/earth.jpg")));
 	//Triangle* pTriangle0  = new Triangle(glm::vec3(-2.0f, 0.0f, -1.0f), glm::vec3(2.0f, 0.0f, -1.0f), glm::vec3(0.0f, 2.0f, -1.0f), new Metal(new ConstantTexture(glm::vec3(0.0, 1.0f, 0.0f)), 0.5f));
-	Texture* baseTexture = new ImageTexture("models/car.jpg");
+	Texture* baseTexture = new ImageTexture("models/Body_Color.jpg");
 	Material* pMatMesh = new Lambertian(baseTexture);
 	//Material* pMatMesh = new FlatColor (new ConstantTexture(glm::vec3(1,1,0)));
-	//TriangleMesh* pMesh0 = new TriangleMesh("models/UVCube5.fbx", pMatMesh);
-	TriangleMesh* pMesh0 = new TriangleMesh("models/car.fbx", pMatMesh);
+	//TriangleMesh* pMesh0 = new TriangleMesh("models/UVCube5.fbx", pMatSphere0);
+	TriangleMesh* pMesh0 = new TriangleMesh("models/barb1.fbx", pMatMesh);
 
 	Profiler::getInstance().WriteToProfiler("Triangle Count:", pMesh0->GetTriangleCount());
 
-	vecHitables.push_back(pSphere0);
+	//vecHitables.push_back(pSphere0);
 	vecHitables.push_back(pSphere1);
-	vecHitables.push_back(pSphere2);
-	vecHitables.push_back(pSphere3);
+	//vecHitables.push_back(pSphere2);
+	//vecHitables.push_back(pSphere3);
 	vecHitables.push_back(pSphere4);
 	//vecHitables.push_back(pTriangle0);
 	vecHitables.push_back(pMesh0);
@@ -59,7 +59,7 @@ void Scene::InitScene()
 
 void Scene::InitRandomScene()
 {
-	Sphere* pSphere0 = new Sphere(glm::vec3(0, -1000, 0), 1000, new Lambertian(new ConstantTexture (glm::vec3(0.5, 0.5, 0.5))));
+	Sphere* pSphere0 = new Sphere(glm::vec3(0, -1000.0f, 0), 1000, new Lambertian(new ConstantTexture (glm::vec3(0.5, 0.5, 0.5))));
 	vecHitables.push_back(pSphere0);
 
 	int i = 1;
@@ -70,8 +70,8 @@ void Scene::InitRandomScene()
 		{
 			float choose_mat = Helper::GetRandom01();
 
-			glm::vec3 center(a + 0.9f * Helper::GetRandom01(), 0.2, b + 0.9 * Helper::GetRandom01());
-			if (glm::length((center - glm::vec3(4, 0.2, 0))) > 0.9f)
+			glm::vec3 center(a + 0.9f * Helper::GetRandom01(), 0.2f, b + 0.9f * Helper::GetRandom01());
+			if (glm::length(center - glm::vec3(4.0f, 0.2f, 0.0f)) > 0.9f)
 			{
 				if (choose_mat < 0.8f)
 				{
@@ -95,9 +95,9 @@ void Scene::InitRandomScene()
 		}
 	}
 
-	Sphere* pSphere1 = new Sphere(glm::vec3(0, 1, 0), 1.0f, new Transparent(1.5f));
-	Sphere* pSphere2 = new Sphere(glm::vec3(-4, 1, 0), 1.0f, new Lambertian(new ConstantTexture(glm::vec3(0.4f, 0.2f, 0.1f))));
-	Sphere* pSphere3 = new Sphere(glm::vec3(4, 1, 0), 1.0f, new Metal(new ConstantTexture(glm::vec3(0.7f, 0.6f, 0.5f)), 0.0f));
+	Sphere* pSphere1 = new Sphere(glm::vec3(0.f, 1.f, 0.f), 1.0f, new Transparent(1.5f));
+	Sphere* pSphere2 = new Sphere(glm::vec3(-4.f, 1.f, 0.f), 1.0f, new Lambertian(new ConstantTexture(glm::vec3(0.4f, 0.2f, 0.1f))));
+	Sphere* pSphere3 = new Sphere(glm::vec3(4.f, 1.f, 0.f), 1.0f, new Metal(new ConstantTexture(glm::vec3(0.7f, 0.6f, 0.5f)), 0.0f));
 
 	vecHitables.push_back(pSphere1);
 	vecHitables.push_back(pSphere2);
@@ -110,7 +110,7 @@ bool Scene::Trace(const Ray& r, int& rayCount, float tmin, float tmax, HitRecord
 
 	bool hit_anything = false;
 	HitRecord temp_rec;
-	double closest_so_far = tmax;
+	float closest_so_far = tmax;
 
 	for (int i = 0; i < vecHitables.size(); i++)
 	{
diff --git a/RayTracer/Sphere.cpp b/RayTracer/Sphere.cpp
index b0bbe83..f5b1770 100644
--- a/RayTracer/Sphere.cpp
+++ b/RayTracer/Sphere.cpp
@@ -1,8 +1,9 @@
 
 #include "Sphere.h"
 #include "Helper.h"
+#include "AABB.h"
 
-/////////////////////////////////////////////////////////////////////////////////////////
+///////////////////////////////////////////////////////////////////////////////////////////////////
 bool Sphere::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
 {
 	glm::vec3 rayDirection = r.GetRayDirection();
@@ -18,7 +19,7 @@ bool Sphere::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
 
 	if (discriminant > 0)
 	{
-		t = (-b - sqrt(discriminant)) / (2.0 * a);
+		t = (-b - sqrt(discriminant)) / (2.0f * a);
 		if (t < tmax && t > tmin)
 		{
 			rec.t = t;
@@ -30,7 +31,7 @@ bool Sphere::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
 			return true;
 		}
 
-		t = (-b + sqrt(discriminant)) / (2.0 * a);
+		t = (-b + sqrt(discriminant)) / (2.0f * a);
 		if (t < tmax && t > tmin)
 		{
 			rec.t = t;
@@ -46,11 +47,17 @@ bool Sphere::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
 	return false;
 }
 
-/////////////////////////////////////////////////////////////////////////////////////////
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void Sphere::BoundingBox(AABB & box) const
+{
+	box = AABB(center - glm::vec3(radius, radius, radius), center + glm::vec3(radius, radius, radius));
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
 glm::vec2 Sphere::GetSphereUV(const glm::vec3& p) const
 {
-	float phi = std::atan2(p.z, p.x);
-	float theta = std::asin(p.y);
+	float phi = std::atan2(p[2], p[0]);
+	float theta = std::asin(p[1]);
 
 	float x = 1 - (phi + PI) / (2 * PI);
 	float y = (theta + PI / 2) / PI;
diff --git a/RayTracer/Sphere.h b/RayTracer/Sphere.h
index b81fa54..5c7d99b 100644
--- a/RayTracer/Sphere.h
+++ b/RayTracer/Sphere.h
@@ -14,6 +14,8 @@ public:
 		mat_ptr(ptr_mat) {};
 
 	virtual bool hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const;
+	virtual void BoundingBox(AABB& box) const;
+
 	glm::vec2 GetSphereUV(const glm::vec3& p) const;
 
 private:
diff --git a/RayTracer/Texture.cpp b/RayTracer/Texture.cpp
index e63a72a..46f9c15 100644
--- a/RayTracer/Texture.cpp
+++ b/RayTracer/Texture.cpp
@@ -16,8 +16,8 @@ glm::vec3 ImageTexture::value(glm::vec2 uv) const
 	if (channels > 3)
 		return glm::vec3(1, 0, 0.8f);
 
-	int i = (uv.x) * width;
-	int j = (1 - uv.y) * height;
+	int i = (uv[0]) * width;
+	int j = (1 - uv[1]) * height;
 
 	if (i < 0) i = 0;
 	if (j < 0) j = 0;
diff --git a/RayTracer/Transparent.h b/RayTracer/Transparent.h
index e33d0ec..4e9e36e 100644
--- a/RayTracer/Transparent.h
+++ b/RayTracer/Transparent.h
@@ -15,11 +15,11 @@ public:
 		glm::vec3 outward_normal;
 		glm::vec3 ray_direction = r_in.GetRayDirection();
 		
-		glm::vec3 reflected = glm::reflect(ray_direction, rec.N);
+		glm::vec3 reflected = Helper::Reflect(ray_direction, rec.N);
 		float ni_over_nt;
-		attenuation = glm::vec3(1, 1, 1);
+		attenuation = glm::vec3(1.0f, 1.0f, 1.0f);
 
-		glm::vec3 refracted = glm::vec3(0);
+		glm::vec3 refracted = glm::vec3(0.0f, 0.0f, 0.0f);
 		float reflect_prob;
 		float cosine;
 
@@ -33,7 +33,7 @@ public:
 		{
 			outward_normal = rec.N;
 			ni_over_nt = 1 / refr_index;
-			cosine = -glm::dot(ray_direction, rec.N) / glm::length(ray_direction);
+			cosine = glm::dot(-ray_direction, rec.N) / glm::length(ray_direction);
 		}
 
 		if (Helper::Refract(ray_direction, outward_normal, ni_over_nt, refracted))
diff --git a/RayTracer/Triangle.cpp b/RayTracer/Triangle.cpp
index e3c4c60..b4cdaad 100644
--- a/RayTracer/Triangle.cpp
+++ b/RayTracer/Triangle.cpp
@@ -1,8 +1,23 @@
 
+#include "AABB.h"
 #include "Triangle.h"
 
 //#define MOLLER_TRUMBORE
 
+Triangle::Triangle(const VertexPNT & _v0, const VertexPNT & _v1, const VertexPNT & _v2, Material * ptr_mat)
+{
+	v0 = _v0; v1 = _v1; v2 = _v2;
+	mat_ptr = ptr_mat;
+
+	// calculate centroid...
+	centroid = v0.position + v1.position + v2.position;
+	centroid /= 3.0f;
+	//float x = (v0.position[0] + v1.position[0] + v2.position[0]) / 3.0f;
+	//float y = (v0.position[1] + v1.position[1] + v2.position[1]) / 3.0f;
+	//float z = (v0.position[2] + v1.position[2] + v2.position[2]) / 3.0f;
+	//centroid = glm::vec3(x, y, z);
+}
+
 /////////////////////////////////////////////////////////////////////////////////////////
 bool Triangle::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
 {
@@ -28,25 +43,25 @@ bool Triangle::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
 	float invDet = 1 / det;
 
 	glm::vec3 tvec = rayOrigin - v0.position;
-	barycentric.x = glm::dot(tvec, pvec) * invDet;
+	barycentric[0] = glm::dot(tvec, pvec) * invDet;
 
-	if (barycentric.x < 0 || barycentric.x > 1)
+	if (barycentric[0] < 0 || barycentric[0] > 1)
 		return false;
 
 	glm::vec3 qvec = glm::cross(tvec, edge0);
-	barycentric.y = glm::dot(rayDirection, qvec) * invDet;
+	barycentric[1] = glm::dot(rayDirection, qvec) * invDet;
 
-	if (barycentric.y < 0 || barycentric.x + barycentric.y > 1)
+	if (barycentric[1] < 0 || barycentric[0] + barycentric[1] > 1)
 		return false;
 
-	barycentric.z = 1 - barycentric.x - barycentric.y; //glm::dot(edge2, qvec) * invDet;
+	barycentric[2] = 1 - barycentric[0] - barycentric[1]; //glm::dot(edge2, qvec) * invDet;
 
 	// Got barycentric, now calculate P,N & UV coordinates
 	// Record hit data!!!
 	rec.t = 100.0f;
-	rec.P = v0.position * barycentric.x + v1.position * barycentric.y + v2.position * barycentric.z;
-	rec.N = v0.normal * barycentric.x +   v1.normal * barycentric.y +   v2.normal * barycentric.z;
-	rec.uv =v0.uv * barycentric.x +       v1.uv * barycentric.y +       v2.uv * barycentric.z;
+	rec.P = v0.position * barycentric[0] + v1.position * barycentric[1] + v2.position * barycentric[2];
+	rec.N = v0.normal * barycentric[0] +   v1.normal * barycentric[1] +   v2.normal * barycentric[2];
+	rec.uv =v0.uv * barycentric[0] +       v1.uv * barycentric[1] +       v2.uv * barycentric[2];
 	rec.mat_ptr = mat_ptr;
 
 	return true;
@@ -54,21 +69,21 @@ bool Triangle::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
 	// NOTE that we are not normalizing the normal vector
 	// as we need to take it's area.
 	// cross product's magnitude is area of parallelogram formed by two vectors
-	glm::vec3 area = glm::cross(edge0, edge1);
+	glm::vec3 area = glm::cross(edge0, edge1); 
 	float areaOfParellogram = glm::length(area);
 
 	// Normalize normal now!
 	// cross product's vector direction represents new vector perpendicular to 
 	// plane formed by those two vectors!
 	glm::vec3 N = glm::normalize(area);
-
 	// Check if ray & plane are parallel
-	float NDotRayDirection = glm::dot(N, rayDirection);
+	float NDotRayDirection = glm::dot(N, rayDirection); 
 	if (fabs(NDotRayDirection) < 0.001f)
 		return false;
 
 	// Compute plane distance from origin
-	float d = glm::dot(v0.position, N);
+	
+	float d = glm::dot(v0.position, N); 
 
 	// Compute t at which intersection happens!
 	float t = (d - glm::dot(N, rayOrigin)) / NDotRayDirection;
@@ -80,28 +95,27 @@ bool Triangle::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
 	glm::vec3 P = rayOrigin + (t * rayDirection);
 
 	// Perform tests if this P is inside triangle or outside
-	glm::vec3 C;
 	glm::vec3 P0 = P - v0.position;
 	glm::vec3 P1 = P - v1.position;
 	glm::vec3 P2 = P - v2.position;
 
-	glm::vec3 C0 = glm::cross(edge0, P0);
-	glm::vec3 C1 = glm::cross(edge1, P1);
-	glm::vec3 C2 = glm::cross(edge2, P2);
+	glm::vec3 C0 = glm::cross(edge0, P0);  
+	glm::vec3 C1 = glm::cross(edge1, P1);  
+	glm::vec3 C2 = glm::cross(edge2, P2);  
 
 	if (glm::dot(N, C0) >= 0 && glm::dot(N, C1) >= 0 && glm::dot(N, C2) >= 0)
 	{
 		float length0 = glm::length(C0);
 		float length1 = glm::length(C1);
-		barycentric.x = length0 / areaOfParellogram;
-		barycentric.y = length1 / areaOfParellogram;
-		barycentric.z = 1 - barycentric.x - barycentric.y;
+		barycentric[0] = length0 / areaOfParellogram;
+		barycentric[1] = length1 / areaOfParellogram;
+		barycentric[2] = 1 - barycentric[0] - barycentric[1];
 
 		// Record hit data!!!
 		rec.t = t;
 		rec.P = P;
 		rec.N = N;
-		rec.uv = barycentric.x * v2.uv + barycentric.y * v0.uv + barycentric.z * v1.uv;
+		rec.uv = barycentric[0] * v2.uv + barycentric[1] * v0.uv + barycentric[2] * v1.uv;
 		rec.mat_ptr = mat_ptr;
 
 		++rec.rayTriangleSuccess;
@@ -142,4 +156,17 @@ bool Triangle::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
 	//	}
 	//}
 	//return false;
-}
\ No newline at end of file
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void Triangle::BoundingBox(AABB &box) const
+{
+	box.minBound = glm::vec3(fminf(fminf(v0.position[0], v1.position[0]), v2.position[0]),
+							fminf(fminf(v0.position[1], v1.position[1]), v2.position[1]),
+							fminf(fminf(v0.position[2], v1.position[2]), v2.position[2]));
+
+	box.maxBound = glm::vec3(fmaxf(fmaxf(v0.position[0], v1.position[0]), v2.position[0]),
+							fmaxf(fmaxf(v0.position[1], v1.position[1]), v2.position[1]),
+							fmaxf(fmaxf(v0.position[2], v1.position[2]), v2.position[2]));
+}
+
diff --git a/RayTracer/Triangle.h b/RayTracer/Triangle.h
index 8b735bc..760e300 100644
--- a/RayTracer/Triangle.h
+++ b/RayTracer/Triangle.h
@@ -1,6 +1,6 @@
 #pragma once
 
-#include "glm\glm.hpp"
+#include "glm/glm.hpp"
 #include "Hitable.h"
 #include "VertexStructures.h"
 
@@ -10,15 +10,18 @@ class Triangle : public Hitable
 {
 public:
 	Triangle() {}
-	Triangle(const VertexPNT& _v0, const VertexPNT& _v1, const VertexPNT& _v2, Material* ptr_mat) :
-		v0(_v0), v1(_v1), v2(_v2),
-		mat_ptr(ptr_mat) {};
+	Triangle(const VertexPNT& _v0, const VertexPNT& _v1, const VertexPNT& _v2, Material* ptr_mat);
 
 	virtual bool hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const;
+	virtual void BoundingBox(AABB& box) const;
+
+	inline glm::vec3 Centroid() const { return centroid; }
 
 private:
 	VertexPNT v0;
 	VertexPNT v1;
 	VertexPNT v2;
+	//glm::vec3 centroid;
+	glm::vec3 centroid;
 	Material* mat_ptr;
 };
diff --git a/RayTracer/TriangleMesh.cpp b/RayTracer/TriangleMesh.cpp
index d6429ef..ae99476 100644
--- a/RayTracer/TriangleMesh.cpp
+++ b/RayTracer/TriangleMesh.cpp
@@ -1,14 +1,37 @@
 
-#include "glm\glm.hpp"
+#include "glm/glm.hpp"
+
+#include "LameBVH.h"
 #include "TriangleMesh.h"
 #include "AABB.h"
 #include <Windows.h>
 
+///////////////////////////////////////////////////////////////////////////////////////////////////
 TriangleMesh::TriangleMesh()
 {
 
 }
 
+///////////////////////////////////////////////////////////////////////////////////////////////////
+TriangleMesh::~TriangleMesh()
+{
+	m_vecTriangles.clear();
+	m_ptrMaterial = nullptr;
+
+	if (m_ptrAABB)
+	{
+		delete m_ptrAABB;
+		m_ptrAABB = nullptr;
+	}
+
+	if (m_ptrBVH)
+	{
+		delete m_ptrBVH;
+		m_ptrBVH = nullptr;
+	}
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
 TriangleMesh::TriangleMesh(const std::string& path, Material* ptr_mat)
 {
 	m_vecTriangles.clear();
@@ -16,11 +39,15 @@ TriangleMesh::TriangleMesh(const std::string& path, Material* ptr_mat)
 
 	m_ptrAABB = new AABB();
 
-	m_iTriangleCount = 0;
-
 	LoadModel(path);
+
+	m_iTriangleCount = m_vecTriangles.size();
+
+	m_ptrBVH = new BVHTree();
+	m_ptrBVH->BuildBVHTree(&m_vecTriangles, m_iTriangleCount/8);
 }
 
+///////////////////////////////////////////////////////////////////////////////////////////////////
 void TriangleMesh::LoadModel(const std::string& path)
 {
 	Assimp::Importer importer;
@@ -36,6 +63,7 @@ void TriangleMesh::LoadModel(const std::string& path)
 	ProcessNode(scene->mRootNode, scene);
 }
 
+///////////////////////////////////////////////////////////////////////////////////////////////////
 void TriangleMesh::ProcessNode(aiNode* node, const aiScene* scene)
 {
 	// node only contains indices to actual objects in the scene. But scene,
@@ -54,6 +82,7 @@ void TriangleMesh::ProcessNode(aiNode* node, const aiScene* scene)
 	}
 }
 
+///////////////////////////////////////////////////////////////////////////////////////////////////
 void TriangleMesh::ProcessMesh(aiMesh* mesh, const aiScene* scene)
 {
 	std::vector<VertexPNT> vecVertices;
@@ -63,17 +92,16 @@ void TriangleMesh::ProcessMesh(aiMesh* mesh, const aiScene* scene)
 	{
 		VertexPNT vertex;
 
-		vertex.position = glm::vec3(mesh->mVertices[i].x, mesh->mVertices[i].y, mesh->mVertices[i].z);
-		vertex.normal = glm::vec3(mesh->mNormals[i].x, mesh->mNormals[i].y, mesh->mNormals[i].z);
+		vertex.position = glm::vec3(mesh->mVertices[i][0], mesh->mVertices[i][1], mesh->mVertices[i][2]);
+		vertex.normal = glm::vec3(mesh->mNormals[i][0], mesh->mNormals[i][1], mesh->mNormals[i][2]);
 
 		if (mesh->mTextureCoords[0])
 		{
-			//vertex.uv = glm::clamp(glm::vec2(mesh->mTextureCoords[0][i].x, mesh->mTextureCoords[0][i].y), 0.0f, 1.0f);
-			vertex.uv = glm::vec2(mesh->mTextureCoords[0][i].x, mesh->mTextureCoords[0][i].y);
+			//vertex.uv = glm::clamp(glm::vec2(mesh->mTextureCoords[0][i][0], mesh->mTextureCoords[0][i][1]), 0.0f, 1.0f);
+			vertex.uv = glm::vec2(mesh->mTextureCoords[0][i][0], mesh->mTextureCoords[0][i][1]);
 		}
 		
 		vecVertices.push_back(vertex);
-		m_ptrAABB->UpdateBB(vertex.position);
 	}
 
 	for (unsigned int i = 0; i < mesh->mNumFaces; i++)
@@ -94,27 +122,47 @@ void TriangleMesh::ProcessMesh(aiMesh* mesh, const aiScene* scene)
 		m_vecTriangles.push_back(tri);
 	}
 
+	//AABB box;
+	//for (unsigned int i = 0; i < m_vecTriangles.size(); i++)
+	//{
+	//	m_vecTriangles[i]->BoundingBox(box);
+	//	m_ptrAABB->ExpandBoundingBox(box);
+	//}
+
 	// Hold count for triangles...
 	m_iTriangleCount = m_vecTriangles.size();
 }
 
-/////////////////////////////////////////////////////////////////////////////////////////
+///////////////////////////////////////////////////////////////////////////////////////////////////
 bool TriangleMesh::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
 {
 	bool isIntersection = false;
 	float closestSoFar = tmax;
 
-	//if (m_ptrAABB->hit(r, tmin, tmax, rec))
+	if (m_ptrBVH->hit(r, tmin, tmax, rec))
 	{
-		for (int i = 0; i < m_vecTriangles.size(); i++)
-		{
-			if (m_vecTriangles[i]->hit(r, tmin, closestSoFar, rec))
-			{
-				isIntersection = true;
-				closestSoFar = rec.t;
-			}
-		}
+		rec.mat_ptr = m_ptrMaterial;
+		//closestSoFar = rec.t;
+		isIntersection = true;
 	}
+
+	//if (m_ptrAABB->hit(r, tmin, tmax, rec))
+	//{
+	//	for (int i = 0; i < m_vecTriangles.size(); i++)
+	//	{
+	//		if (m_vecTriangles[i]->hit(r, tmin, closestSoFar, rec))
+	//		{
+	//			isIntersection = true;
+	//			closestSoFar = rec.t;
+	//		}
+	//	}
+	//}
 	
 	return isIntersection;
 }
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void TriangleMesh::BoundingBox(AABB & box) const
+{
+	box = *m_ptrAABB;
+}
diff --git a/RayTracer/TriangleMesh.h b/RayTracer/TriangleMesh.h
index b4d7a97..0a509fd 100644
--- a/RayTracer/TriangleMesh.h
+++ b/RayTracer/TriangleMesh.h
@@ -10,15 +10,17 @@
 
 class Material;
 class AABB;
+class BVHTree;
 
 class TriangleMesh : public Hitable
 {
 public:
 	TriangleMesh();
-	~TriangleMesh() {}
+	~TriangleMesh();
 	TriangleMesh(const std::string& path, Material* ptr_mat);
 
 	virtual bool hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const;
+	virtual void BoundingBox(AABB& box) const;
 
 	inline uint64_t GetTriangleCount() { return m_iTriangleCount; }
 
@@ -32,5 +34,7 @@ private:
 	AABB*				   m_ptrAABB;
 	Material*			   m_ptrMaterial;
 
+	BVHTree*			   m_ptrBVH;
+
 	uint64_t			   m_iTriangleCount;
 };
diff --git a/RayTracer/VertexStructures.h b/RayTracer/VertexStructures.h
index 0012dd2..9f24bba 100644
--- a/RayTracer/VertexStructures.h
+++ b/RayTracer/VertexStructures.h
@@ -33,9 +33,9 @@ struct VertexPNT
 {
 	VertexPNT() 
 	{
-		position = glm::vec3(0);
-		normal = glm::vec3(0);
-		uv = glm::vec2(0);
+		position = glm::vec3(0.0f, 0.0f, 0.0f);
+		normal =   glm::vec3(0.0f, 0.0f, 0.0f);
+		uv = glm::vec2(0.0f, 0.0f);
 	}
 
 	VertexPNT(const glm::vec3& _pos, const glm::vec3& _normal, const glm::vec2 _uv) :
diff --git a/WindowsRayTracer.cpp b/WindowsRayTracer.cpp
index 79f8afe..3f803d4 100644
--- a/WindowsRayTracer.cpp
+++ b/WindowsRayTracer.cpp
@@ -131,8 +131,14 @@ BOOL InitInstance(HINSTANCE hInstance, int nCmdShow)
    }
 
    // Initialize Application!
+
+#ifdef NDEBUG
    pApp->Initialize(hWnd, true);
+#else
+   pApp->Initialize(hWnd, false);
+#endif // NDEBUG
 
+   
    ShowWindow(hWnd, nCmdShow);
    UpdateWindow(hWnd);
 
```

