# Post 14 — An application layer and ray counting

## `849e03f` — 2019-02-24 _(master)_

> - Added Application Layer - Added Ray Counter - Added FlatColor material type

```diff
diff --git a/.gitignore b/.gitignore
index 8cedccf..525247b 100644
--- a/.gitignore
+++ b/.gitignore
@@ -37,3 +37,7 @@
 *.app
 *.ppm
 *.bmp
+/models
+/RenderImage1.jpg
+/carRender.jpg
+/carReflection.jpg
diff --git a/Application.cpp b/Application.cpp
new file mode 100644
index 0000000..3ab6184
--- /dev/null
+++ b/Application.cpp
@@ -0,0 +1,272 @@
+
+#include <thread>
+#include <time.h>
+#include <vector>
+#include <fstream>
+#include "glm/glm.hpp"
+#include "RayTracer/Hitable.h"
+#include "RayTracer/Material.h"
+#include "RayTracer/Scene.h"
+#include "RayTracer/Helper.h"
+#include "RayTracer/Camera.h"
+#include "Application.h"
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+Application::Application()
+{
+	m_iBackbufferWidth = 480;
+	m_iBackbufferHeight = 270;
+	m_iNumSamples = 1;
+	m_dTotalRenderTime = 0;
+	m_bThreaded = false;
+
+	m_iRayCount = 0;
+
+	m_hWnd = NULL;
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+Application::~Application()
+{
+	delete m_pCamera;
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void Application::Initialize(HWND hwnd, bool _threaded)
+{
+	m_bThreaded = _threaded;
+	m_hWnd = hwnd;
+
+	_threaded ? m_iMaxThreads = std::thread::hardware_concurrency() : 0;
+
+	m_pCamera = &(Camera::getInstance());
+	m_pCamera->InitCamera(m_iBackbufferWidth, m_iBackbufferHeight);
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void Application::Execute(HDC _hdc)
+{
+	int percentageDone = 0.0f;
+
+	const clock_t begin_time = clock();
+	double counter = 0;
+
+	Trace();
+
+	const clock_t end_time = clock();
+	m_dTotalRenderTime = (end_time - begin_time) / (double)CLOCKS_PER_SEC;
+
+	int rayCount = m_iRayCount;
+
+	const size_t len = 256;
+	wchar_t buffer[len] = {};
+	swprintf(buffer, L"[Time : %0.2f seconds!] [Ray Count : %d rays]", m_dTotalRenderTime, rayCount);
+	SetWindowText(m_hWnd, buffer);
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void Application::SaveImage()
+{
+	static int count = 0;
+
+	BITMAPINFO info;
+	BITMAPFILEHEADER header;
+	memset(&info, 0, sizeof(info));
+	memset(&header, 0, sizeof(header));
+
+	info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
+	info.bmiHeader.biWidth = m_iBackbufferWidth;
+	info.bmiHeader.biHeight = m_iBackbufferHeight;
+	info.bmiHeader.biPlanes = 1;
+	info.bmiHeader.biBitCount = 24;
+	info.bmiHeader.biCompression = BI_RGB;
+	//info.bmiHeader.biSizeImage = width * height * 3;
+
+	header.bfType = 0x4D42;
+	header.bfOffBits = sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER);
+
+	char* pixels = NULL;
+	HDC hdc = GetDC(m_hWnd);
+	HDC memDC = CreateCompatibleDC(hdc);
+	HBITMAP section = CreateDIBSection(hdc, &info, DIB_RGB_COLORS, (void**)&pixels, 0, 0);
+	DeleteObject(SelectObject(memDC, section));
+	BitBlt(memDC, 0, 0, m_iBackbufferWidth, m_iBackbufferHeight, hdc, 0, 0, SRCCOPY);
+	DeleteDC(memDC);
+
+	count++;
+	char buf[32] = { 0 };
+	sprintf(buf, "RenderImage%d.bmp", count);
+	std::fstream hFile(buf, std::ios::out | std::ios::binary);
+	if (hFile.is_open())
+	{
+		hFile.write((char*)&header, sizeof(header));
+		hFile.write((char*)&info.bmiHeader, sizeof(info.bmiHeader));
+		int bytes = (((24 * m_iBackbufferWidth + 31) & (~31)) / 8) * m_iBackbufferHeight;
+		hFile.write(pixels, bytes);
+		hFile.close();
+	}
+
+	DeleteObject(section);
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+glm::vec3 Application::TraceColor(const Ray & r, int depth, int& rayCount)
+{
+	HitRecord rec;
+
+	if (Scene::getInstance().Trace(r, rayCount, 0.001f, FLT_MAX, rec))
+	{
+		Ray scatteredRay;
+		glm::vec3 attenuation = glm::vec3(0);
+
+		if (depth < 50 && rec.mat_ptr->Scatter(r, rec, rayCount, attenuation, scatteredRay))
+		{
+			if (glm::distance(scatteredRay.GetRayOrigin(), scatteredRay.GetRayDirection()) < 0.0000001f)
+				return attenuation;
+			else
+				return attenuation * TraceColor(scatteredRay, depth + 1, rayCount);
+		}
+		else
+		{
+			return glm::vec3(0, 0, 0);
+		}
+	}
+	else
+	{
+		glm::vec3 unit_direction = glm::normalize(r.GetRayDirection());
+		float t = 0.5f * (unit_direction.y + 1.0f);
+		return Helper::LerpVector(glm::vec3(1.0f, 1.0f, 1.0f), glm::vec3(0.5f, 0.7f, 1.0f), t);
+	}
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void Application::ShowProgress(int percentage)
+{
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void Application::ParallelTrace(std::mutex * threadMutex, int i)
+{
+	threadMutex->lock();
+
+	int backBufferHeight = m_iBackbufferHeight;
+	int backBufferWidth = m_iBackbufferWidth;
+	int quarterHeight = m_iBackbufferHeight / m_iMaxThreads;
+	int startWidth = 0;
+	int startHeight = i * quarterHeight;
+	int endWidth = m_iBackbufferWidth;
+	int endHeight = (i + 1) * quarterHeight;
+	int ns = m_iNumSamples;
+	HDC hdc = GetDC(m_hWnd);
+
+	int rayCount = 0;
+
+	threadMutex->unlock();
+
+	// Error check for bounds!
+	if (startWidth < endWidth && startHeight < endHeight)
+	{
+		for (int j = startHeight; j <= endHeight; j++)
+		{
+			for (int i = startWidth; i <= endWidth; i++)
+			{
+				glm::vec3 color(0, 0, 0);
+
+				for (int s = 0; s < ns; s++)
+				{
+					float u = float(i + Helper::GetRandom01()) / float(backBufferWidth);
+					float v = float(j + Helper::GetRandom01()) / float(backBufferHeight);
+
+					Ray r = m_pCamera->get_ray(u, v);
+
+					color = color + TraceColor(r, 0, rayCount);
+				}
+
+				color = color / float(ns);
+				color = glm::vec3(sqrt(color.x), sqrt(color.y), sqrt(color.z));
+
+				float ir = (255.99f * color.x);
+				float ig = (255.99f * color.y);
+				float ib = (255.99f * color.z);
+
+				SetPixel(hdc, backBufferWidth - i, backBufferHeight - j, RGB(ir, ig, ib));
+				//++counter;
+			}
+
+			//percentageDone = (counter / (gBackbufferWidth*gBackbufferHeight)) * 100.0f;
+			//ShowProgress(percentageDone);
+		}
+	}
+
+	m_iRayCount += rayCount;
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void Application::Trace()
+{
+	if (m_pCamera == nullptr)
+		return;
+
+	if (m_bThreaded)
+	{
+		std::vector<std::thread*> ThreadGroup;
+		std::mutex threadMutex;
+
+		for (int i = 0; i < m_iMaxThreads; i++)
+		{
+			std::thread* t = new std::thread(&Application::ParallelTrace, this, &threadMutex, i);
+			ThreadGroup.push_back(t);
+		}
+
+		std::vector<std::thread*>::iterator iter = ThreadGroup.begin();
+		for (; iter != ThreadGroup.end(); iter++)
+		{
+			//if((*iter)->joinable())
+			(*iter)->join();
+		}
+	}
+	else
+	{
+		HDC hdc = GetDC(m_hWnd);
+
+		int rayCount = 0;
+
+		for (int j = m_iBackbufferHeight; j >= 0; j--)
+		{
+			for (int i = 0; i <= m_iBackbufferWidth; i++)
+			{
+				glm::vec3 color(0, 0, 0);
+
+				for (int s = 0; s < m_iNumSamples; s++)
+				{
+					float u = float(i + Helper::GetRandom01()) / float(m_iBackbufferWidth);
+					float v = float(j + Helper::GetRandom01()) / float(m_iBackbufferHeight);
+
+					Ray r = m_pCamera->get_ray(u, v);
+
+					color = color + TraceColor(r, 0, rayCount);
+				}
+
+				color = color / float(m_iNumSamples);
+				color = glm::vec3(sqrt(color.x), sqrt(color.y), sqrt(color.z));
+
+				float ir = (255.99f*color.x);
+				float ig = (255.99f*color.y);
+				float ib = (255.99f*color.z);
+
+				//float ir = 255.99f;
+				//float ig = 128.99f;
+				//float ib = 255.99f;
+
+				//fprintf(filePtr, "\n%d %d %d", ir, ig, ib);
+				SetPixel(hdc, m_iBackbufferWidth - i, m_iBackbufferHeight - j, RGB(ir, ig, ib));
+				//++counter;
+			}
+
+			//percentageDone = (counter / (gBackbufferWidth*gBackbufferHeight)) * 100.0f;
+			//ShowProgress(percentageDone);
+		}
+
+		m_iRayCount += rayCount;
+	}
+}
\ No newline at end of file
diff --git a/Application.h b/Application.h
new file mode 100644
index 0000000..9583051
--- /dev/null
+++ b/Application.h
@@ -0,0 +1,42 @@
+#pragma once
+
+#include "glm/glm.hpp"
+#include <Windows.h>
+#include <mutex>
+#include <atomic>
+
+class Ray;
+class Camera;
+
+class Application
+{
+public:
+	Application();
+	~Application();
+
+	void			Initialize(HWND hwnd, bool _threaded);
+	void			Execute(HDC _hdc);
+	void			SaveImage();
+
+	inline int		GetBufferWidth() { return m_iBackbufferWidth; }
+	inline int		GetBufferHeight() { return m_iBackbufferHeight; }
+	inline double	GetTotalRenderTime() { return m_dTotalRenderTime; }
+
+private:
+	glm::vec3		TraceColor(const Ray& r, int depth, int& rayCount);
+	void			ShowProgress(int percentage);
+	void			ParallelTrace(std::mutex* threadMutex, int i);
+	void			Trace();
+
+	int				m_iBackbufferWidth;
+	int				m_iBackbufferHeight;
+	int				m_iNumSamples;
+	int				m_iMaxThreads;
+	double			m_dTotalRenderTime;
+	bool			m_bThreaded;
+
+	std::atomic<int>	m_iRayCount;
+
+	HWND			m_hWnd;
+	Camera*			m_pCamera;
+};
diff --git a/RayTracer/FlatColor.cpp b/RayTracer/FlatColor.cpp
new file mode 100644
index 0000000..f16fd9c
--- /dev/null
+++ b/RayTracer/FlatColor.cpp
@@ -0,0 +1,12 @@
+
+#include "FlatColor.h"
+
+bool FlatColor::Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& attenuation, Ray& scatterd) const
+{
+	// Ray origin & Direction both are same, which means no further bounces
+	// and processing of rays, useful for flat colors...!
+	scatterd = Ray(rec.P, rec.P);
+
+	attenuation = Albedo->value(rec.uv);
+	return true;
+}
\ No newline at end of file
diff --git a/RayTracer/FlatColor.h b/RayTracer/FlatColor.h
new file mode 100644
index 0000000..b29c1cf
--- /dev/null
+++ b/RayTracer/FlatColor.h
@@ -0,0 +1,17 @@
+#pragma once
+
+#include "Ray.h"
+#include "Hitable.h"
+#include "Material.h"
+#include "Texture.h"
+
+class FlatColor : public Material
+{
+public:
+	FlatColor(Texture* _albedo) : Albedo(_albedo) {}
+
+	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& attenuation, Ray& scatterd) const;
+
+private:
+	Texture* Albedo;
+};
diff --git a/RayTracer/Helper.h b/RayTracer/Helper.h
index 5518fbd..3f47377 100644
--- a/RayTracer/Helper.h
+++ b/RayTracer/Helper.h
@@ -46,7 +46,7 @@ namespace Helper
 	{
 		glm::vec3 unit_v = glm::normalize(v);
 		float NDotV = glm::dot(unit_v, n);
-		float discriminant = 1.0 - ni_over_nt * ni_over_nt * (1 - NDotV * NDotV);
+		float discriminant = 1.0f - ni_over_nt * ni_over_nt * (1 - NDotV * NDotV);
 
 		if (discriminant > 0)
 		{
diff --git a/RayTracer/Lambertian.cpp b/RayTracer/Lambertian.cpp
index d6736be..65eb004 100644
--- a/RayTracer/Lambertian.cpp
+++ b/RayTracer/Lambertian.cpp
@@ -2,10 +2,12 @@
 #include "Lambertian.h"
 #include "Helper.h"
 
-bool Lambertian::Scatter(const Ray& r_in, const HitRecord& rec, glm::vec3& attenuation, Ray& scatterd) const
+bool Lambertian::Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& attenuation, Ray& scatterd) const
 {
 	glm::vec3 target = rec.P + rec.N + Helper::RandomInUnitSphere();
 	scatterd = Ray(rec.P, target - rec.P);
+	++rayCount;
+
 	attenuation = Albedo->value(rec.uv);
 	return true;
 }
\ No newline at end of file
diff --git a/RayTracer/Lambertian.h b/RayTracer/Lambertian.h
index 89d60ad..aceba69 100644
--- a/RayTracer/Lambertian.h
+++ b/RayTracer/Lambertian.h
@@ -10,7 +10,7 @@ class Lambertian : public Material
 public:
 	Lambertian(Texture* _albedo) : Albedo(_albedo) {}
 
-	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, glm::vec3& attenuation, Ray& scatterd) const;
+	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& attenuation, Ray& scatterd) const;
 
 private:
 	Texture* Albedo;
diff --git a/RayTracer/Material.h b/RayTracer/Material.h
index 6f4ecf4..ba18659 100644
--- a/RayTracer/Material.h
+++ b/RayTracer/Material.h
@@ -6,5 +6,5 @@
 class Material
 {
 public:
-	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, glm::vec3& attenuation, Ray& scattered) const = 0;
+	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& attenuation, Ray& scattered) const = 0;
 };
diff --git a/RayTracer/Metal.cpp b/RayTracer/Metal.cpp
index e22f2b6..a747478 100644
--- a/RayTracer/Metal.cpp
+++ b/RayTracer/Metal.cpp
@@ -2,10 +2,12 @@
 #include "Metal.h"
 #include "Helper.h"
 
-bool Metal::Scatter(const Ray& r_in, const HitRecord& rec, glm::vec3& attenuation, Ray& scatterd) const
+bool Metal::Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& attenuation, Ray& scatterd) const
 {
 	glm::vec3 target = glm::reflect(glm::normalize(r_in.GetRayDirection()), rec.N);
 	scatterd = Ray(rec.P, target + fuzz * Helper::RandomInUnitSphere());
+	++rayCount;
+
 	attenuation = Albedo->value(rec.uv);
 	return (glm::dot(scatterd.GetRayDirection(), rec.N) > 0);
 }
\ No newline at end of file
diff --git a/RayTracer/Metal.h b/RayTracer/Metal.h
index cf228cd..5a295c4 100644
--- a/RayTracer/Metal.h
+++ b/RayTracer/Metal.h
@@ -16,7 +16,7 @@ public:
 			fuzz = 1;
 	}
 
-	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, glm::vec3& attenuation, Ray& scatterd) const;
+	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& attenuation, Ray& scatterd) const;
 
 private:
 	Texture* Albedo;
diff --git a/RayTracer/Ray.h b/RayTracer/Ray.h
index bfa6fe5..ca7f846 100644
--- a/RayTracer/Ray.h
+++ b/RayTracer/Ray.h
@@ -5,7 +5,13 @@
 class Ray
 {
 public:
-	Ray() {}
+	Ray() 
+	{
+		origin = glm::vec3(0);
+		direction = glm::vec3(1);
+		invDirection = glm::vec3(1);
+	}
+
 	Ray(const glm::vec3& A, const glm::vec3& B) 
 	{ 
 		origin = A;
diff --git a/RayTracer/Scene.cpp b/RayTracer/Scene.cpp
index 0d346b7..fdfa74a 100644
--- a/RayTracer/Scene.cpp
+++ b/RayTracer/Scene.cpp
@@ -2,6 +2,7 @@
 #include "Scene.h"
 #include "Camera.h"
 #include "Sphere.h"
+#include "FlatColor.h"
 #include "Lambertian.h"
 #include "Metal.h"
 #include "Transparent.h"
@@ -40,12 +41,13 @@ void Scene::InitScene()
 	//Triangle* pTriangle0  = new Triangle(glm::vec3(-2.0f, 0.0f, -1.0f), glm::vec3(2.0f, 0.0f, -1.0f), glm::vec3(0.0f, 2.0f, -1.0f), new Metal(new ConstantTexture(glm::vec3(0.0, 1.0f, 0.0f)), 0.5f));
 	Texture* baseTexture = new ImageTexture("models/car.jpg");
 	Material* pMatMesh = new Lambertian(baseTexture);
+	//Material* pMatMesh = new FlatColor (new ConstantTexture(glm::vec3(1,1,0)));
 	//TriangleMesh* pMesh0 = new TriangleMesh("models/UVCube5.fbx", pMatMesh);
 	TriangleMesh* pMesh0 = new TriangleMesh("models/car.fbx", pMatMesh);
 
-	//vecHitables.push_back(pSphere0);
+	vecHitables.push_back(pSphere0);
 	vecHitables.push_back(pSphere1);
-	//vecHitables.push_back(pSphere2);
+	vecHitables.push_back(pSphere2);
 	vecHitables.push_back(pSphere3);
 	vecHitables.push_back(pSphere4);
 	//vecHitables.push_back(pTriangle0);
@@ -99,8 +101,10 @@ void Scene::InitRandomScene()
 	vecHitables.push_back(pSphere3);
 }
 
-bool Scene::Trace(const Ray& r, float tmin, float tmax, HitRecord& rec)
+bool Scene::Trace(const Ray& r, int& rayCount, float tmin, float tmax, HitRecord& rec)
 {
+	++rayCount;
+
 	bool hit_anything = false;
 	HitRecord temp_rec;
 	double closest_so_far = tmax;
diff --git a/RayTracer/Scene.h b/RayTracer/Scene.h
index 4fbdb5c..dadb9a9 100644
--- a/RayTracer/Scene.h
+++ b/RayTracer/Scene.h
@@ -16,12 +16,12 @@ public:
 		return instance;
 	}
 
-	bool Trace(const Ray& r, float tmin, float tmax, HitRecord& rec);
+	bool Trace(const Ray& r, int& rayCount, float tmin, float tmax, HitRecord& rec);
 
 private:
 	Scene();
 	void InitScene();
 	void InitRandomScene();
-
+	
 	std::vector<Hitable*> vecHitables;
 };
\ No newline at end of file
diff --git a/RayTracer/Transparent.h b/RayTracer/Transparent.h
index e1e106e..e33d0ec 100644
--- a/RayTracer/Transparent.h
+++ b/RayTracer/Transparent.h
@@ -10,7 +10,7 @@ class Transparent : public Material
 public:
 	Transparent(float ri) : refr_index(ri) {}
 
-	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, glm::vec3& attenuation, Ray& scattered) const
+	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& attenuation, Ray& scattered) const
 	{
 		glm::vec3 outward_normal;
 		glm::vec3 ray_direction = r_in.GetRayDirection();
@@ -55,6 +55,8 @@ public:
 			scattered = Ray(rec.P, refracted);
 		}
 
+		++rayCount;
+
 		return true;
 	}
 
diff --git a/WindowsRayTracer.cpp b/WindowsRayTracer.cpp
index c271851..495a771 100644
--- a/WindowsRayTracer.cpp
+++ b/WindowsRayTracer.cpp
@@ -4,45 +4,8 @@
 
 #include "header.h"
 #include "WindowsRayTracer.h"
-#include <time.h>
+#include "Application.h"
 #include <stdint.h>
-#include <fstream>
-#include <vector>
-
-/////------- Ray Tracer based Includes -------/////
-#include "glm/glm.hpp"
-#include "./RayTracer/Ray.h"
-#include "./RayTracer/Sphere.h"
-#include "./RayTracer/Triangle.h"
-#include "./RayTracer/Scene.h"
-#include "./RayTracer/Camera.h"
-#include "./RayTracer/Helper.h"
-#include "./RayTracer/Material.h"
-#include "./RayTracer/Lambertian.h"
-#include "./RayTracer/Metal.h"
-#include "./RayTracer/Transparent.h"
-
-#define C11_THREADS
-
-const int COLOR_CHANNELS = 3; // RGB
-const int gBackbufferWidth = 480;
-const int gBackbufferHeight = 270;
-const int nSamples = 1;
-
-unsigned long long int numRays = 0;
-
-int maxNumThreads = 0;
-double TotalRenderTime = 0;
-
-#if defined C11_THREADS
-#include <thread>
-#include <mutex>
-#elif defined ENKITS
-#include "enkiTS\TaskScheduler.h"
-#endif
-
-//Camera* gCam = new Camera(glm::vec3(2,2,20), glm::vec3(0,0,0), glm::vec3(0, 1, 0), 60, float(gBackbufferWidth) / float(gBackbufferHeight), 0.0f, 1.0f);
-Camera* gCam = nullptr; // (pos, lookAt, Up, 45, float(gBackbufferWidth) / float(gBackbufferHeight), 0.0f, 1.0f);
 
 #define MAX_LOADSTRING 100
 
@@ -52,6 +15,8 @@ HINSTANCE hInst;                                // current instance
 WCHAR szTitle[MAX_LOADSTRING];                  // The title bar text
 WCHAR szWindowClass[MAX_LOADSTRING];            // the main window class name
 
+Application* pApp = nullptr;
+
 // Forward declarations of functions included in this code module:
 ATOM                MyRegisterClass(HINSTANCE hInstance);
 BOOL                InitInstance(HINSTANCE, int);
@@ -59,247 +24,6 @@ LRESULT CALLBACK    WndProc(HWND, UINT, WPARAM, LPARAM);
 INT_PTR CALLBACK    About(HWND, UINT, WPARAM, LPARAM);
 
 /////////////////////////////////////////////////////////////////////////////////////////////////////////////
-#pragma region RayTracer
-
-//Hitable* BasicTestScene()
-//{
-//	Hitable** list = new Hitable*[6];
-//	list[0] = new Sphere(glm::vec3(1.05f, 0, 0), 0.5, new Metal(glm::vec3(0.5, 0.2, 0.1), 0.5));
-//	list[1] = new Sphere(glm::vec3(0, -100.5, 0), 100, new Lambertian(glm::vec3(0.2, 0.2, 0.2)));
-//	list[2] = new Sphere(glm::vec3(0, 0, 2), 0.5, new Lambertian(glm::vec3(1.0f, 0.0f, 0.0f)));
-//	list[3] = new Sphere(glm::vec3(-1.05f, 0, 0), 0.5, new Metal(glm::vec3(1.0, 0.2, 0.0), 0));
-//	list[4] = new Sphere(glm::vec3(0.0f, 0, -3), 0.5, new Lambertian(glm::vec3(1.0, 1.0, 0.0)));
-//	list[5] = new Triangle(glm::vec3(-2.0f, 0.0f, -1.0f), glm::vec3(2.0f, 0.0f, -1.0f), glm::vec3(0.0f, 2.0f, -1.0f), new Lambertian(glm::vec3(0.0f, 1.0f, 0.0f)));
-//
-//	return new HitableList(list, 6);
-//}
-//
-//Hitable* random_scene()
-//{
-//	int n = 500;
-//	Hitable** list = new Hitable*[n + 1];
-//	list[0] = new Sphere(glm::vec3(0, -1000, 0), 1000, new Lambertian(glm::vec3(0.5, 0.5, 0.5)));
-//	int i = 1;
-//	for (int a = -11; a < 11; a++)
-//	{
-//		for (int b = -11; b < 11; b++)
-//		{
-//			float choose_mat = Helper::GetRandom01();
-//			glm::vec3 center(a + 0.9f*Helper::GetRandom01(), 0.2, b + 0.9*Helper::GetRandom01());
-//			if ((center - glm::vec3(4, 0.2, 0)).Length() > 0.9f)
-//			{
-//				if (choose_mat < 0.8f)
-//				{
-//					// diffuse
-//					list[i++] = new Sphere(center, 0.2f, new Lambertian(glm::vec3(Helper::GetRandom01()*Helper::GetRandom01(), Helper::GetRandom01()*Helper::GetRandom01(), Helper::GetRandom01()*Helper::GetRandom01())));
-//				}
-//				else if (choose_mat < 0.95)
-//				{
-//					// Metal
-//					list[i++] = new Sphere(center, 0.2f, new Metal(glm::vec3(0.5f*(1 + Helper::GetRandom01()), 0.5f*(1 + Helper::GetRandom01()), 0.5f*(1 + Helper::GetRandom01())), Helper::GetRandom01()));
-//				}
-//				else
-//				{
-//					// glass
-//					list[i++] = new Sphere(center, 0.2f, new Transparent(1.5f));
-//				}
-//			}
-//		}
-//	}
-//
-//	list[i++] = new Sphere(glm::vec3(0, 1, 0), 1.0f, new Transparent(1.5f));
-//	list[i++] = new Sphere(glm::vec3(-4, 1, 0), 1.0f, new Lambertian(glm::vec3(0.4f, 0.2f, 0.1f)));
-//	list[i++] = new Sphere(glm::vec3(4, 1, 0), 1.0f, new Metal(glm::vec3(0.7f, 0.6f, 0.5f), 0.0f));
-//
-//	return new HitableList(list, i);
-//}
-//
-//Hitable* world = BasicTestScene();
-glm::vec3 TraceColor(const Ray& r, int depth)
-{
-	HitRecord rec;
-
-	++numRays;
-	if (Scene::getInstance().Trace(r, 0.001f, FLT_MAX, rec))
-	{
-		Ray scatteredRay;
-		glm::vec3 attenuation = glm::vec3(0);
-
-		if (depth < 50 && rec.mat_ptr->Scatter(r, rec, attenuation, scatteredRay))
-		{
-			return attenuation * TraceColor(scatteredRay, depth + 1);
-		}
-		else
-		{
-			return glm::vec3(0, 0, 0);
-		}
-	}
-	else
-	{
-		glm::vec3 unit_direction = glm::normalize(r.GetRayDirection());
-		float t = 0.5 * (unit_direction.y + 1.0f);
-		return Helper::LerpVector(glm::vec3(1.0f, 1.0f, 1.0f), glm::vec3(0.5f, 0.7f, 1.0f), t);
-	}
-}
-
-void ShowProgress(int percentage)
-{
-	system("cls");
-	printf("\nRendering Progress : %d%%\n", percentage);
-}
-
-void ParallelTrace(std::mutex* threadMutex, int i)
-{
-	threadMutex->lock();
-
-	int backBufferHeight = gBackbufferHeight;
-	int backBufferWidth = gBackbufferWidth;
-	int quarterHeight = gBackbufferHeight / maxNumThreads;
-	int startWidth = 0;
-	int startHeight = i * quarterHeight; 
-	int endWidth = gBackbufferWidth;
-	int endHeight = (i + 1) * quarterHeight;
-	int ns = nSamples;
-	HDC hdc = GetDC(hWnd);
-
-	threadMutex->unlock();
-
-	// Error check for bounds!
-	if (startWidth < endWidth && startHeight < endHeight)
-	{
-		for (int j = startHeight; j <= endHeight; j++)
-		{
-			for (int i = startWidth; i <= endWidth; i++)
-			{
-				glm::vec3 color(0, 0, 0);
-
-				for (int s = 0; s < ns; s++)
-				{
-					float u = float(i + Helper::GetRandom01()) / float(backBufferWidth);
-					float v = float(j + Helper::GetRandom01()) / float(backBufferHeight);
-				
-					Ray r = gCam->get_ray(u, v);
-				
-					color = color + TraceColor(r, 0);
-				}
-				
-				color = color / float(ns);
-				color = glm::vec3(sqrt(color.x), sqrt(color.y), sqrt(color.z));
-
-				float ir = (255.99 * color.x);
-				float ig = (255.99 * color.y);
-				float ib = (255.99 * color.z);
-
-				//float ir = 255.99f;
-				//float ig = 128.99f;
-				//float ib = 255.99f;
-
-				//fprintf(filePtr, "\n%d %d %d", ir, ig, ib);
-				SetPixel(hdc, backBufferWidth - i, backBufferHeight- j, RGB(ir, ig, ib));
-				//++counter;
-			}
-
-			//percentageDone = (counter / (gBackbufferWidth*gBackbufferHeight)) * 100.0f;
-			//ShowProgress(percentageDone);
-		}
-	}
-}
-
-void Trace()
-{
-	if (gCam == nullptr)
-		return;
-
-#pragma region OLD_CODE
-	//HDC hdc = GetDC(hWnd);
-	//
-	//for (int j = gBackbufferHeight; j >= 0; j--)
-	//{
-	//	for (int i = 0; i <= gBackbufferWidth; i++)
-	//	{
-	//		glm::vec3 color(0, 0, 0);
-	//
-	//		for (int s = 0; s < nSamples; s++)
-	//		{
-	//			float u = float(i + Helper::GetRandom01()) / float(gBackbufferWidth);
-	//			float v = float(j + Helper::GetRandom01()) / float(gBackbufferHeight);
-	//
-	//			Ray r = gCam->get_ray(u, v);
-	//
-	//			color = color + TraceColor(r, 0);
-	//		}
-	//
-	//		color = color / float(nSamples);
-	//		color = glm::vec3(sqrt(color.x), sqrt(color.y), sqrt(color.z));
-	//
-	//		float ir = (255.99*color.x);
-	//		float ig = (255.99*color.y);
-	//		float ib = (255.99*color.z);
-	//
-	//		//float ir = 255.99f;
-	//		//float ig = 128.99f;
-	//		//float ib = 255.99f;
-	//
-	//		//fprintf(filePtr, "\n%d %d %d", ir, ig, ib);
-	//		SetPixel(hdc, gBackbufferWidth - i, gBackbufferHeight - j, RGB(ir, ig, ib));
-	//		//++counter;
-	//	}
-	//
-	//	//percentageDone = (counter / (gBackbufferWidth*gBackbufferHeight)) * 100.0f;
-	//	//ShowProgress(percentageDone);
-	//}
-#pragma endregion
-
-	
-#if defined C11_THREADS
-	std::vector<std::thread*> ThreadGroup;
-	std::mutex threadMutex;
-	
-	for (int i = 0; i < maxNumThreads; i++)
-	{
-		std::thread* t = new std::thread(&ParallelTrace, &threadMutex, i);
-		ThreadGroup.push_back(t);
-	}
-	
-	std::vector<std::thread*>::iterator iter = ThreadGroup.begin();
-	for (; iter != ThreadGroup.end(); iter++)
-	{
-		//if((*iter)->joinable())
-		(*iter)->join();
-	}
-#elif defined ENKITS
-
-#endif
-	
-}
-
-void Execute(HDC hdc)
-{
-	
-	int percentageDone = 0.0f;
-
-	const clock_t begin_time = clock();
-	double counter = 0;
-	
-	Trace();
-
-	const clock_t end_time = clock();
-	TotalRenderTime = (end_time - begin_time) / (double)CLOCKS_PER_SEC;
-
-	const size_t len = 256;
-	wchar_t buffer[len] = {};
-	swprintf(buffer, L"Windows Ray Tracer [Render Time : %0.2f seconds!]", TotalRenderTime);
-	SetWindowText(hWnd, buffer);
-	//MessageBox(hWnd, buffer, L"Render Time!", MB_OKCANCEL);
-
-	//printf("Render Time : %.2f seconds\n", time);
-
-}
-
-#pragma endregion
-////////////////////////////////////////// END OF RAY TRACER CODE ///////////////////////////////////////////
-
-
 int APIENTRY wWinMain(_In_ HINSTANCE hInstance,
                      _In_opt_ HINSTANCE hPrevInstance,
                      _In_ LPWSTR    lpCmdLine,
@@ -313,11 +37,8 @@ int APIENTRY wWinMain(_In_ HINSTANCE hInstance,
     LoadStringW(hInstance, IDC_WINDOWSRAYTRACER, szWindowClass, MAX_LOADSTRING);
     MyRegisterClass(hInstance);
 
-#if defined C11_THREADS
-	maxNumThreads = std::thread::hardware_concurrency();
-#elif defined ENKITS
-	maxNumThreads = 4;
-#endif 
+	// Application Initialization
+	pApp = new Application();
 
     // Perform application initialization:
     if (!InitInstance (hInstance, nCmdShow))
@@ -342,51 +63,6 @@ int APIENTRY wWinMain(_In_ HINSTANCE hInstance,
     return (int) msg.wParam;
 }
 
-
-void SaveImage()
-{
-	static int count = 0;
-
-	BITMAPINFO info;
-	BITMAPFILEHEADER header;
-	memset(&info, 0, sizeof(info));
-	memset(&header, 0, sizeof(header));
-
-	info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
-	info.bmiHeader.biWidth = gBackbufferWidth;
-	info.bmiHeader.biHeight = gBackbufferHeight;
-	info.bmiHeader.biPlanes = 1;
-	info.bmiHeader.biBitCount = 24;
-	info.bmiHeader.biCompression = BI_RGB;
-	//info.bmiHeader.biSizeImage = width * height * 3;
-
-	header.bfType = 0x4D42;
-	header.bfOffBits = sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER);
-
-	char* pixels = NULL;
-	HDC hdc = GetDC(hWnd);
-	HDC memDC = CreateCompatibleDC(hdc);
-	HBITMAP section = CreateDIBSection(hdc, &info, DIB_RGB_COLORS, (void**)&pixels, 0, 0);
-	DeleteObject(SelectObject(memDC, section));
-	BitBlt(memDC, 0, 0, gBackbufferWidth, gBackbufferHeight, hdc, 0, 0, SRCCOPY);
-	DeleteDC(memDC);
-
-	count++;
-	char buf[32] = { 0 };
-	sprintf(buf, "RenderImage%d.bmp", count);
-	std::fstream hFile(buf, std::ios::out | std::ios::binary);
-	if (hFile.is_open())
-	{
-		hFile.write((char*)&header, sizeof(header));
-		hFile.write((char*)&info.bmiHeader, sizeof(info.bmiHeader));
-		int bytes = (((24 * gBackbufferWidth + 31) & (~31)) / 8) * gBackbufferHeight;
-		hFile.write(pixels, bytes);
-		hFile.close();
-	}
-
-	DeleteObject(section);
-}
-
 //
 //  FUNCTION: MyRegisterClass()
 //
@@ -414,7 +90,7 @@ ATOM MyRegisterClass(HINSTANCE hInstance)
 }
 
 //
-//   FUNCTION: InitInstance(HINSTANCE, int)
+//   FUNCTION: InitInstance(HINSTANCE, int, Application)
 //
 //   PURPOSE: Saves instance handle and creates main window
 //
@@ -427,7 +103,9 @@ BOOL InitInstance(HINSTANCE hInstance, int nCmdShow)
 {
    hInst = hInstance; // Store instance handle in our global variable
 
-   RECT rect = { 0,0,gBackbufferWidth,gBackbufferHeight };
+   pApp = new Application();
+
+   RECT rect = { 0, 0, pApp->GetBufferWidth(), pApp->GetBufferHeight() };
    AdjustWindowRect(&rect, WS_OVERLAPPEDWINDOW, true);
 
    hWnd = CreateWindow (szWindowClass, szTitle, WS_OVERLAPPEDWINDOW,
@@ -438,8 +116,8 @@ BOOL InitInstance(HINSTANCE hInstance, int nCmdShow)
       return FALSE;
    }
 
-   Camera::getInstance().InitCamera(gBackbufferWidth, gBackbufferHeight);
-   gCam = &Camera::getInstance();
+   // Initialize Application!
+   pApp->Initialize(hWnd, true);
 
    ShowWindow(hWnd, nCmdShow);
    UpdateWindow(hWnd);
@@ -472,14 +150,14 @@ LRESULT CALLBACK WndProc(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam)
                 break;
 			case ID_FILE_SAVEIMAGE:
 			{
-				SaveImage();
+				pApp->SaveImage();
 				break;
 			}
 			case ID_FILE_RENDERTIME:
 			{
 				const size_t len = 256;
 				wchar_t buffer[len] = {};
-				swprintf(buffer, L"Total Render Time : %0.2f seconds!", TotalRenderTime);
+				swprintf(buffer, L"Total Render Time : %0.2f seconds!", pApp->GetTotalRenderTime());
 				MessageBox(hWnd, buffer, L"Render Time", 0);
 				break;
 			}
@@ -496,7 +174,7 @@ LRESULT CALLBACK WndProc(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam)
             PAINTSTRUCT ps;
             HDC hdc = BeginPaint(hWnd, &ps);
 
-			Execute(hdc);
+			pApp->Execute(hdc);
 
 			OutputDebugString(L"This is paint!");
 
@@ -504,7 +182,10 @@ LRESULT CALLBACK WndProc(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam)
         }
         break;
     case WM_DESTROY:
-        PostQuitMessage(0);
+	{
+		PostQuitMessage(0);
+	}
+        
         break;
     default:
         return DefWindowProc(hWnd, message, wParam, lParam);
```

