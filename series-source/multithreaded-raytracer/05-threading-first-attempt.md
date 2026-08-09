# Post 5 — First attempt at threading: std::thread and horizontal bands

## `0114729` — 2018-05-13 _(master)_

> Prep for multi-threading.

```diff
diff --git a/WindowsRayTracer.cpp b/WindowsRayTracer.cpp
index aee21af..53317e6 100644
--- a/WindowsRayTracer.cpp
+++ b/WindowsRayTracer.cpp
@@ -6,8 +6,6 @@
 #include <time.h>
 #include <stdint.h>
 #include <fstream>
-#include <dwmapi.h>
-#pragma comment(lib, "Dwmapi.lib");
 
 /////------- Ray Tracer based Includes -------/////
 #include "./RayTracer/Vector3.h"
@@ -22,8 +20,8 @@
 #include "./RayTracer/Transparent.h"
 
 const int COLOR_CHANNELS = 3; // RGB
-const int gBackbufferWidth = 480;
-const int gBackbufferHeight = 270;
+const int gBackbufferWidth = 960;
+const int gBackbufferHeight = 540;
 const int nSamples = 1;
 
 double TotalRenderTime = 0;
@@ -135,40 +133,27 @@ Hitable* BasicTestScene()
 	return new HitableList(list, 5);
 }
 
-void Execute(HDC hdc)
+void Trace(HDC hdc, Camera cam, Hitable* world)
 {
-	Hitable* world = BasicTestScene();
-
-	Vector3 lookFrom(0, 1.5, 6);
-	Vector3 lookAt(0, 0, 0);
-	float dist_to_focus = 1.0f;	// set this to 1.0 & apertue to 0.0f to stop DOF effect!
-	float aperture = 0.0f;
-
-	Camera cam(lookFrom, lookAt, Vector3(0, 1, 0), 20, float(gBackbufferWidth) / float(gBackbufferHeight), aperture, dist_to_focus);
-	int percentageDone = 0.0f;
-
-	const clock_t begin_time = clock();
-	double counter = 0;
-	
 	for (int j = 0; j <= gBackbufferHeight; j++)
 	{
 		for (int i = 0; i <= gBackbufferWidth; i++)
 		{
 			Vector3 color(0, 0, 0);
-			
+
 			for (int s = 0; s < nSamples; s++)
 			{
 				float u = float(i + Helper::GetRandom01()) / float(gBackbufferWidth);
 				float v = float(j + Helper::GetRandom01()) / float(gBackbufferHeight);
-			
+
 				Ray r = cam.get_ray(u, v);
-			
+
 				color = color + TraceColor(r, world, 0);
 			}
-			
+
 			color = color / float(nSamples);
 			color = Vector3(sqrt(color.x), sqrt(color.y), sqrt(color.z));
-			
+
 			float ir = (255.99*color.x);
 			float ig = (255.99*color.y);
 			float ib = (255.99*color.z);
@@ -178,14 +163,32 @@ void Execute(HDC hdc)
 			//float ib = 255.99f;
 
 			//fprintf(filePtr, "\n%d %d %d", ir, ig, ib);
-			SetPixel(hdc, gBackbufferWidth-i, gBackbufferHeight-j, RGB(ir, ig, ib));
+			SetPixel(hdc, gBackbufferWidth - i, gBackbufferHeight - j, RGB(ir, ig, ib));
 			//Sleep(0.5);
-			++counter;
+			//++counter;
 		}
 
-		percentageDone = (counter / (gBackbufferWidth*gBackbufferHeight)) * 100.0f;
+		//percentageDone = (counter / (gBackbufferWidth*gBackbufferHeight)) * 100.0f;
 		//ShowProgress(percentageDone);
 	}
+}
+
+void Execute(HDC hdc)
+{
+	Hitable* world = BasicTestScene();
+
+	Vector3 lookFrom(0, 1.5, 6);
+	Vector3 lookAt(0, 0, 0);
+	float dist_to_focus = 1.0f;	// set this to 1.0 & apertue to 0.0f to stop DOF effect!
+	float aperture = 0.0f;
+
+	Camera cam(lookFrom, lookAt, Vector3(0, 1, 0), 20, float(gBackbufferWidth) / float(gBackbufferHeight), aperture, dist_to_focus);
+	int percentageDone = 0.0f;
+
+	const clock_t begin_time = clock();
+	double counter = 0;
+	
+	Trace(hdc, cam, world);
 
 	const clock_t end_time = clock();
 	TotalRenderTime = (end_time - begin_time) / (double)CLOCKS_PER_SEC;
@@ -237,6 +240,8 @@ int APIENTRY wWinMain(_In_ HINSTANCE hInstance,
 
 void SaveImage()
 {
+	static int count = 0;
+
 	BITMAPINFO info;
 	BITMAPFILEHEADER header;
 	memset(&info, 0, sizeof(info));
@@ -261,7 +266,10 @@ void SaveImage()
 	BitBlt(memDC, 0, 0, gBackbufferWidth, gBackbufferHeight, hdc, 0, 0, SRCCOPY);
 	DeleteDC(memDC);
 
-	std::fstream hFile("RenderImage.bmp", std::ios::out | std::ios::binary);
+	count++;
+	char buf[32] = { 0 };
+	sprintf(buf, "RenderImage%d.bmp", count);
+	std::fstream hFile(buf, std::ios::out | std::ios::binary);
 	if (hFile.is_open())
 	{
 		hFile.write((char*)&header, sizeof(header));
@@ -269,7 +277,6 @@ void SaveImage()
 		int bytes = (((24 * gBackbufferWidth + 31) & (~31)) / 8) * gBackbufferHeight;
 		hFile.write(pixels, bytes);
 		hFile.close();
-		DeleteObject(section);
 	}
 
 	DeleteObject(section);
```

## `7d1cdb1` — 2018-06-01 _(master)_

> Basic Multithreading support using C++11 Threads.

```diff
diff --git a/WindowsRayTracer.cpp b/WindowsRayTracer.cpp
index 53317e6..abfbdbc 100644
--- a/WindowsRayTracer.cpp
+++ b/WindowsRayTracer.cpp
@@ -1,11 +1,13 @@
 ﻿// WindowsRayTracer.cpp : Defines the entry point for the application.
 //
 
+
 #include "header.h"
 #include "WindowsRayTracer.h"
 #include <time.h>
 #include <stdint.h>
 #include <fstream>
+#include <vector>
 
 /////------- Ray Tracer based Includes -------/////
 #include "./RayTracer/Vector3.h"
@@ -19,13 +21,33 @@
 #include "./RayTracer/Metal.h"
 #include "./RayTracer/Transparent.h"
 
+#define C11_THREADS
+
 const int COLOR_CHANNELS = 3; // RGB
 const int gBackbufferWidth = 960;
 const int gBackbufferHeight = 540;
-const int nSamples = 1;
+const int nSamples = 50;
 
+unsigned long long int numRays = 0;
+
+int maxNumThreads = 0;
 double TotalRenderTime = 0;
 
+#if defined C11_THREADS
+#include <thread>
+#include <mutex>
+#elif defined ENKITS
+#include "enkiTS\TaskScheduler.h"
+#endif
+
+Vector3 lookFrom(0, 1.5, 6);
+Vector3 lookAt(0, 0, 0);
+float dist_to_focus = 1.0f;	// set this to 1.0 & apertue to 0.0f to stop DOF effect!
+float aperture = 0.0f;
+
+
+Camera cam(lookFrom, lookAt, Vector3(0, 1, 0), 20, float(gBackbufferWidth) / float(gBackbufferHeight), aperture, dist_to_focus);
+
 #define MAX_LOADSTRING 100
 
 // Global Variables:
@@ -40,46 +62,22 @@ BOOL                InitInstance(HINSTANCE, int);
 LRESULT CALLBACK    WndProc(HWND, UINT, WPARAM, LPARAM);
 INT_PTR CALLBACK    About(HWND, UINT, WPARAM, LPARAM);
 
-
-
-float* gBackBuffer; 
-uint32_t* gBackbufferBytes;
-HBITMAP gBackbufferBitmap;
-
 /////////////////////////////////////////////////////////////////////////////////////////////////////////////
 #pragma region RayTracer
 
-Vector3 TraceColor(const Ray& r, Hitable* world, int depth)
+Hitable* BasicTestScene()
 {
-	HitRecord rec;
-
-	if (world->hit(r, 0.001f, FLT_MAX, rec))
-	{
-		Ray scatteredRay;
-		Vector3 attenuation;
+	Hitable** list = new Hitable*[5];
+	list[0] = new Sphere(Vector3(1.05f, 0, 0), 0.5, new Metal(Vector3(0.5, 0.2, 0.1), 0.5));
+	list[1] = new Sphere(Vector3(0, -100.5, 0), 100, new Lambertian(Vector3(0.2, 0.2, 0.2)));
+	list[2] = new Sphere(Vector3(0, 0, 0.1), 0.5, new Transparent(1.5f));
+	list[3] = new Sphere(Vector3(-1.05f, 0, 0), 0.5, new Metal(Vector3(1.0, 0.2, 0.0), 0));
+	list[4] = new Sphere(Vector3(0.0f, 0, -3), 0.5, new Lambertian(Vector3(1.0, 1.0, 0.0)));
 
-		if (depth < 50 && rec.mat_ptr->Scatter(r, rec, attenuation, scatteredRay))
-		{
-			return attenuation * TraceColor(scatteredRay, world, depth + 1);
-		}
-		else
-		{
-			return Vector3(0, 0, 0);
-		}
-	}
-	else
-	{
-		Vector3 unit_direction = unit_vector(r.GetRayDirection());
-		float t = 0.5 * (unit_direction.y + 1.0f);
-		return Helper::LerpVector(Vector3(1.0f, 1.0f, 1.0f), Vector3(0.5f, 0.7f, 1.0f), t);
-	}
+	return new HitableList(list, 5);
 }
 
-void ShowProgress(int percentage)
-{
-	system("cls");
-	printf("\nRendering Progress : %d%%\n", percentage);
-}
+Hitable* world = BasicTestScene();
 
 Hitable* random_scene()
 {
@@ -121,78 +119,178 @@ Hitable* random_scene()
 	return new HitableList(list, i);
 }
 
-Hitable* BasicTestScene()
+Vector3 TraceColor(const Ray& r, int depth)
 {
-	Hitable** list = new Hitable*[5];
-	list[0] = new Sphere(Vector3(1.05f, 0, 0), 0.5, new Metal(Vector3(0.5, 0.2, 0.1), 0.5));
-	list[1] = new Sphere(Vector3(0, -100.5, 0), 100, new Lambertian(Vector3(0.2, 0.2, 0.2)));
-	list[2] = new Sphere(Vector3(0, 0, 0.1), 0.5, new Transparent(1.5f));
-	list[3] = new Sphere(Vector3(-1.05f, 0, 0), 0.5, new Metal(Vector3(1.0, 0.2, 0.0), 0));
-	list[4] = new Sphere(Vector3(0.0f, 0, -3), 0.5, new Lambertian(Vector3(1.0, 1.0, 0.0)));
+	HitRecord rec;
 
-	return new HitableList(list, 5);
+	++numRays;
+	if (world->hit(r, 0.001f, FLT_MAX, rec))
+	{
+		Ray scatteredRay;
+		Vector3 attenuation;
+
+		if (depth < 50 && rec.mat_ptr->Scatter(r, rec, attenuation, scatteredRay))
+		{
+			return attenuation * TraceColor(scatteredRay, depth + 1);
+		}
+		else
+		{
+			return Vector3(0, 0, 0);
+		}
+	}
+	else
+	{
+		Vector3 unit_direction = unit_vector(r.GetRayDirection());
+		float t = 0.5 * (unit_direction.y + 1.0f);
+		return Helper::LerpVector(Vector3(1.0f, 1.0f, 1.0f), Vector3(0.5f, 0.7f, 1.0f), t);
+	}
 }
 
-void Trace(HDC hdc, Camera cam, Hitable* world)
+void ShowProgress(int percentage)
 {
-	for (int j = 0; j <= gBackbufferHeight; j++)
+	system("cls");
+	printf("\nRendering Progress : %d%%\n", percentage);
+}
+
+void ParallelTrace(std::mutex* threadMutex, int i)
+{
+	threadMutex->lock();
+
+	int backBufferHeight = gBackbufferHeight;
+	int backBufferWidth = gBackbufferWidth;
+	int quarterHeight = gBackbufferHeight / maxNumThreads;
+	int startWidth = 0;
+	int startHeight = i * quarterHeight; 
+	int endWidth = gBackbufferWidth;
+	int endHeight = (i + 1) * quarterHeight;
+	int ns = nSamples;
+	HDC hdc = GetDC(hWnd);
+
+	threadMutex->unlock();
+
+	// Error check for bounds!
+	if (startWidth < endWidth && startHeight < endHeight)
 	{
-		for (int i = 0; i <= gBackbufferWidth; i++)
+		for (int j = startHeight; j <= endHeight; j++)
 		{
-			Vector3 color(0, 0, 0);
-
-			for (int s = 0; s < nSamples; s++)
+			for (int i = startWidth; i <= endWidth; i++)
 			{
-				float u = float(i + Helper::GetRandom01()) / float(gBackbufferWidth);
-				float v = float(j + Helper::GetRandom01()) / float(gBackbufferHeight);
-
-				Ray r = cam.get_ray(u, v);
+				Vector3 color(0, 0, 0);
 
-				color = color + TraceColor(r, world, 0);
-			}
+				for (int s = 0; s < ns; s++)
+				{
+					float u = float(i + Helper::GetRandom01()) / float(backBufferWidth);
+					float v = float(j + Helper::GetRandom01()) / float(backBufferHeight);
+				
+					Ray r = cam.get_ray(u, v);
+				
+					color = color + TraceColor(r, 0);
+				}
+				
+				color = color / float(ns);
+				color = Vector3(sqrt(color.x), sqrt(color.y), sqrt(color.z));
 
-			color = color / float(nSamples);
-			color = Vector3(sqrt(color.x), sqrt(color.y), sqrt(color.z));
+				float ir = (255.99 * color.x);
+				float ig = (255.99 * color.y);
+				float ib = (255.99 * color.z);
 
-			float ir = (255.99*color.x);
-			float ig = (255.99*color.y);
-			float ib = (255.99*color.z);
+				//float ir = 255.99f;
+				//float ig = 128.99f;
+				//float ib = 255.99f;
 
-			//float ir = 255.99f;
-			//float ig = 128.99f;
-			//float ib = 255.99f;
+				//fprintf(filePtr, "\n%d %d %d", ir, ig, ib);
+				SetPixel(hdc, backBufferWidth - i, backBufferHeight- j, RGB(ir, ig, ib));
+				//++counter;
+			}
 
-			//fprintf(filePtr, "\n%d %d %d", ir, ig, ib);
-			SetPixel(hdc, gBackbufferWidth - i, gBackbufferHeight - j, RGB(ir, ig, ib));
-			//Sleep(0.5);
-			//++counter;
+			//percentageDone = (counter / (gBackbufferWidth*gBackbufferHeight)) * 100.0f;
+			//ShowProgress(percentageDone);
 		}
-
-		//percentageDone = (counter / (gBackbufferWidth*gBackbufferHeight)) * 100.0f;
-		//ShowProgress(percentageDone);
 	}
 }
 
-void Execute(HDC hdc)
+void Trace()
 {
-	Hitable* world = BasicTestScene();
+#pragma region OLD_CODE
+	//for (int j = 0; j <= gBackbufferHeight; j++)
+	//{
+	//	for (int i = 0; i <= gBackbufferWidth; i++)
+	//	{
+	//		Vector3 color(0, 0, 0);
+	//
+	//		for (int s = 0; s < nSamples; s++)
+	//		{
+	//			float u = float(i + Helper::GetRandom01()) / float(gBackbufferWidth);
+	//			float v = float(j + Helper::GetRandom01()) / float(gBackbufferHeight);
+	//
+	//			Ray r = cam.get_ray(u, v);
+	//
+	//			color = color + TraceColor(r, world, 0);
+	//		}
+	//
+	//		color = color / float(nSamples);
+	//		color = Vector3(sqrt(color.x), sqrt(color.y), sqrt(color.z));
+	//
+	//		float ir = (255.99*color.x);
+	//		float ig = (255.99*color.y);
+	//		float ib = (255.99*color.z);
+	//
+	//		//float ir = 255.99f;
+	//		//float ig = 128.99f;
+	//		//float ib = 255.99f;
+	//
+	//		//fprintf(filePtr, "\n%d %d %d", ir, ig, ib);
+	//		SetPixel(hdc, gBackbufferWidth - i, gBackbufferHeight - j, RGB(ir, ig, ib));
+	//		Sleep(0.5);
+	//		//++counter;
+	//	}
+	//
+	//	//percentageDone = (counter / (gBackbufferWidth*gBackbufferHeight)) * 100.0f;
+	//	//ShowProgress(percentageDone);
+	//}
+#pragma endregion
+
+	
+#if defined C11_THREADS
+	std::vector<std::thread*> ThreadGroup;
+	std::mutex threadMutex;
+	
+	for (int i = 0; i < maxNumThreads; i++)
+	{
+		std::thread* t = new std::thread(&ParallelTrace, &threadMutex, i);
+		ThreadGroup.push_back(t);
+	}
+	
+	std::vector<std::thread*>::iterator iter = ThreadGroup.begin();
+	for (; iter != ThreadGroup.end(); iter++)
+	{
+		//if((*iter)->joinable())
+		(*iter)->join();
+	}
+#elif defined ENKITS
 
-	Vector3 lookFrom(0, 1.5, 6);
-	Vector3 lookAt(0, 0, 0);
-	float dist_to_focus = 1.0f;	// set this to 1.0 & apertue to 0.0f to stop DOF effect!
-	float aperture = 0.0f;
+#endif
+	
+}
 
-	Camera cam(lookFrom, lookAt, Vector3(0, 1, 0), 20, float(gBackbufferWidth) / float(gBackbufferHeight), aperture, dist_to_focus);
+void Execute(HDC hdc)
+{
+	
 	int percentageDone = 0.0f;
 
 	const clock_t begin_time = clock();
 	double counter = 0;
 	
-	Trace(hdc, cam, world);
+	Trace();
 
 	const clock_t end_time = clock();
 	TotalRenderTime = (end_time - begin_time) / (double)CLOCKS_PER_SEC;
 
+	const size_t len = 256;
+	wchar_t buffer[len] = {};
+	swprintf(buffer, L"Total Render Time : %0.2f seconds!", TotalRenderTime);
+	MessageBox(hWnd, buffer, L"Render Time!", MB_OKCANCEL);
+
 	//printf("Render Time : %.2f seconds\n", time);
 
 }
@@ -214,6 +312,12 @@ int APIENTRY wWinMain(_In_ HINSTANCE hInstance,
     LoadStringW(hInstance, IDC_WINDOWSRAYTRACER, szWindowClass, MAX_LOADSTRING);
     MyRegisterClass(hInstance);
 
+#if defined C11_THREADS
+	maxNumThreads = std::thread::hardware_concurrency();
+#elif defined ENKITS
+	maxNumThreads = 4;
+#endif 
+
     // Perform application initialization:
     if (!InitInstance (hInstance, nCmdShow))
     {
```

