# Post 1 — A Win32 window and the dumbest possible canvas

## `24e60c1` — 2018-05-13 _(master)_

> GDI based ray tracer, First commit.

_This commit introduces the whole project at once (852 lines, 26 files). The diff below is scoped to just the files relevant to this post._

```diff
diff --git a/WindowsRayTracer.cpp b/WindowsRayTracer.cpp
new file mode 100644
index 0000000..5da556a
--- /dev/null
+++ b/WindowsRayTracer.cpp
@@ -0,0 +1,420 @@
+﻿// WindowsRayTracer.cpp : Defines the entry point for the application.
+//
+
+#include "header.h"
+#include "WindowsRayTracer.h"
+#include <time.h>
+#include <stdint.h>
+#include <fstream>
+#include <dwmapi.h>
+#pragma comment(lib, "Dwmapi.lib");
+
+/////------- Ray Tracer based Includes -------/////
+#include "./RayTracer/Vector3.h"
+#include "./RayTracer/Ray.h"
+#include "./RayTracer/Sphere.h"
+#include "./RayTracer/HitableList.h"
+#include "./RayTracer/Camera.h"
+#include "./RayTracer/Helper.h"
+#include "./RayTracer/Material.h"
+#include "./RayTracer/Lambertian.h"
+#include "./RayTracer/Metal.h"
+#include "./RayTracer/Transparent.h"
+
+const int COLOR_CHANNELS = 3; // RGB
+const int gBackbufferWidth = 480;
+const int gBackbufferHeight = 270;
+const int nSamples = 1;
+
+double TotalRenderTime = 0;
+
+#define MAX_LOADSTRING 100
+
+// Global Variables:
+HWND	hWnd;									// current window handle
+HINSTANCE hInst;                                // current instance
+WCHAR szTitle[MAX_LOADSTRING];                  // The title bar text
+WCHAR szWindowClass[MAX_LOADSTRING];            // the main window class name
+
+// Forward declarations of functions included in this code module:
+ATOM                MyRegisterClass(HINSTANCE hInstance);
+BOOL                InitInstance(HINSTANCE, int);
+LRESULT CALLBACK    WndProc(HWND, UINT, WPARAM, LPARAM);
+INT_PTR CALLBACK    About(HWND, UINT, WPARAM, LPARAM);
+
+
+
+float* gBackBuffer; 
+uint32_t* gBackbufferBytes;
+HBITMAP gBackbufferBitmap;
+
+/////////////////////////////////////////////////////////////////////////////////////////////////////////////
+#pragma region RayTracer
+
+Vector3 TraceColor(const Ray& r, Hitable* world, int depth)
+{
+	HitRecord rec;
+
+	if (world->hit(r, 0.001f, FLT_MAX, rec))
+	{
+		Ray scatteredRay;
+		Vector3 attenuation;
+
+		if (depth < 50 && rec.mat_ptr->Scatter(r, rec, attenuation, scatteredRay))
+		{
+			return attenuation * TraceColor(scatteredRay, world, depth + 1);
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
+}
+
+void ShowProgress(int percentage)
+{
+	system("cls");
+	printf("\nRendering Progress : %d%%\n", percentage);
+}
+
+Hitable* random_scene()
+{
+	int n = 500;
+	Hitable** list = new Hitable*[n + 1];
+	list[0] = new Sphere(Vector3(0, -1000, 0), 1000, new Lambertian(Vector3(0.5, 0.5, 0.5)));
+	int i = 1;
+	for (int a = -11; a < 11; a++)
+	{
+		for (int b = -11; b < 11; b++)
+		{
+			float choose_mat = Helper::GetRandom01();
+			Vector3 center(a + 0.9f*Helper::GetRandom01(), 0.2, b + 0.9*Helper::GetRandom01());
+			if ((center - Vector3(4, 0.2, 0)).length() > 0.9f)
+			{
+				if (choose_mat < 0.8f)
+				{
+					// diffuse
+					list[i++] = new Sphere(center, 0.2f, new Lambertian(Vector3(Helper::GetRandom01()*Helper::GetRandom01(), Helper::GetRandom01()*Helper::GetRandom01(), Helper::GetRandom01()*Helper::GetRandom01())));
+				}
+				else if (choose_mat < 0.95)
+				{
+					// Metal
+					list[i++] = new Sphere(center, 0.2f, new Metal(Vector3(0.5f*(1 + Helper::GetRandom01()), 0.5f*(1 + Helper::GetRandom01()), 0.5f*(1 + Helper::GetRandom01())), Helper::GetRandom01()));
+				}
+				else
+				{
+					// glass
+					list[i++] = new Sphere(center, 0.2f, new Transparent(1.5f));
+				}
+			}
+		}
+	}
+
+	list[i++] = new Sphere(Vector3(0, 1, 0), 1.0f, new Transparent(1.5f));
+	list[i++] = new Sphere(Vector3(-4, 1, 0), 1.0f, new Lambertian(Vector3(0.4f, 0.2f, 0.1f)));
+	list[i++] = new Sphere(Vector3(4, 1, 0), 1.0f, new Metal(Vector3(0.7f, 0.6f, 0.5f), 0.0f));
+
+	return new HitableList(list, i);
+}
+
+Hitable* BasicTestScene()
+{
+	Hitable** list = new Hitable*[5];
+	list[0] = new Sphere(Vector3(1.05f, 0, 0), 0.5, new Metal(Vector3(0.5, 0.2, 0.1), 0.5));
+	list[1] = new Sphere(Vector3(0, -100.5, 0), 100, new Lambertian(Vector3(0.2, 0.2, 0.2)));
+	list[2] = new Sphere(Vector3(0, 0, 0.1), 0.5, new Transparent(1.5f));
+	list[3] = new Sphere(Vector3(-1.05f, 0, 0), 0.5, new Metal(Vector3(1.0, 0.2, 0.0), 0));
+	list[4] = new Sphere(Vector3(0.0f, 0, -3), 0.5, new Lambertian(Vector3(1.0, 1.0, 0.0)));
+
+	return new HitableList(list, 5);
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
+	for (int j = 0; j <= gBackbufferHeight; j++)
+	{
+		for (int i = 0; i <= gBackbufferWidth; i++)
+		{
+			Vector3 color(0, 0, 0);
+			
+			for (int s = 0; s < nSamples; s++)
+			{
+				float u = float(i + Helper::GetRandom01()) / float(gBackbufferWidth);
+				float v = float(j + Helper::GetRandom01()) / float(gBackbufferHeight);
+			
+				Ray r = cam.get_ray(u, v);
+			
+				color = color + TraceColor(r, world, 0);
+			}
+			
+			color = color / float(nSamples);
+			color = Vector3(sqrt(color.x), sqrt(color.y), sqrt(color.z));
+			
+			float ir = (255.99*color.x);
+			float ig = (255.99*color.y);
+			float ib = (255.99*color.z);
+
+			//float ir = 255.99f;
+			//float ig = 128.99f;
+			//float ib = 255.99f;
+
+			//fprintf(filePtr, "\n%d %d %d", ir, ig, ib);
+			SetPixel(hdc, gBackbufferWidth-i, gBackbufferHeight-j, RGB(ir, ig, ib));
+			//Sleep(0.5);
+			++counter;
+		}
+
+		percentageDone = (counter / (gBackbufferWidth*gBackbufferHeight)) * 100.0f;
+		//ShowProgress(percentageDone);
+	}
+
+	const clock_t end_time = clock();
+	TotalRenderTime = (end_time - begin_time) / (double)CLOCKS_PER_SEC;
+
+	//printf("Render Time : %.2f seconds\n", time);
+
+}
+
+#pragma endregion
+////////////////////////////////////////// END OF RAY TRACER CODE ///////////////////////////////////////////
+
+
+int APIENTRY wWinMain(_In_ HINSTANCE hInstance,
+                     _In_opt_ HINSTANCE hPrevInstance,
+                     _In_ LPWSTR    lpCmdLine,
+                     _In_ int       nCmdShow)
+{
+    UNREFERENCED_PARAMETER(hPrevInstance);
+    UNREFERENCED_PARAMETER(lpCmdLine);
+
+    // Initialize global strings
+    LoadStringW(hInstance, IDS_APP_TITLE, szTitle, MAX_LOADSTRING);
+    LoadStringW(hInstance, IDC_WINDOWSRAYTRACER, szWindowClass, MAX_LOADSTRING);
+    MyRegisterClass(hInstance);
+
+    // Perform application initialization:
+    if (!InitInstance (hInstance, nCmdShow))
+    {
+        return FALSE;
+    }
+
+    HACCEL hAccelTable = LoadAccelerators(hInstance, MAKEINTRESOURCE(IDC_WINDOWSRAYTRACER));
+
+    MSG msg;
+
+    // Main message loop:
+    while (GetMessage(&msg, nullptr, 0, 0))
+    {
+        if (!TranslateAccelerator(msg.hwnd, hAccelTable, &msg))
+        {
+            TranslateMessage(&msg);
+            DispatchMessage(&msg);
+        }
+    }
+
+    return (int) msg.wParam;
+}
+
+
+void SaveImage()
+{
+	BITMAPINFO info;
+	BITMAPFILEHEADER header;
+	memset(&info, 0, sizeof(info));
+	memset(&header, 0, sizeof(header));
+
+	RECT rc;
+	DwmGetWindowAttribute(hWnd, DWMWA_EXTENDED_FRAME_BOUNDS, &rc, sizeof(RECT));
+	int width = rc.right - rc.left;
+	int height = rc.bottom - rc.top;
+
+	info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
+	info.bmiHeader.biWidth = width;
+	info.bmiHeader.biHeight = height;
+	info.bmiHeader.biPlanes = 1;
+	info.bmiHeader.biBitCount = 24;
+	info.bmiHeader.biCompression = BI_RGB;
+	//info.bmiHeader.biSizeImage = width * height * 3;
+
+	header.bfType = 0x4D42;
+	header.bfOffBits = sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER);
+
+	char* pixels = NULL;
+	HDC hdc = GetDC(hWnd);
+	HDC memDC = CreateCompatibleDC(hdc);
+	HBITMAP section = CreateDIBSection(hdc, &info, DIB_RGB_COLORS, (void**)&pixels, 0, 0);
+	DeleteObject(SelectObject(memDC, section));
+	BitBlt(memDC, 0, 0, width, height, hdc, 0, 0, SRCCOPY);
+	DeleteDC(memDC);
+
+	std::fstream hFile("RenderImage.bmp", std::ios::out | std::ios::binary);
+	if (hFile.is_open())
+	{
+		hFile.write((char*)&header, sizeof(header));
+		hFile.write((char*)&info.bmiHeader, sizeof(info.bmiHeader));
+		int bytes = (((24 * width + 31) & (~31)) / 8) * height;
+		hFile.write(pixels, bytes);
+		hFile.close();
+		DeleteObject(section);
+	}
+
+	DeleteObject(section);
+}
+
+//
+//  FUNCTION: MyRegisterClass()
+//
+//  PURPOSE: Registers the window class.
+//
+ATOM MyRegisterClass(HINSTANCE hInstance)
+{
+    WNDCLASSEXW wcex;
+
+    wcex.cbSize = sizeof(WNDCLASSEX);
+
+    wcex.style          = CS_HREDRAW | CS_VREDRAW;
+    wcex.lpfnWndProc    = WndProc;
+    wcex.cbClsExtra     = 0;
+    wcex.cbWndExtra     = 0;
+    wcex.hInstance      = hInstance;
+    wcex.hIcon          = LoadIcon(hInstance, MAKEINTRESOURCE(IDI_WINDOWSRAYTRACER));
+    wcex.hCursor        = LoadCursor(nullptr, IDC_ARROW);
+    wcex.hbrBackground  = (HBRUSH)(COLOR_WINDOW+1);
+    wcex.lpszMenuName   = MAKEINTRESOURCEW(IDC_WINDOWSRAYTRACER);
+    wcex.lpszClassName  = szWindowClass;
+    wcex.hIconSm        = LoadIcon(wcex.hInstance, MAKEINTRESOURCE(IDI_SMALL));
+
+    return RegisterClassExW(&wcex);
+}
+
+//
+//   FUNCTION: InitInstance(HINSTANCE, int)
+//
+//   PURPOSE: Saves instance handle and creates main window
+//
+//   COMMENTS:
+//
+//        In this function, we save the instance handle in a global variable and
+//        create and display the main program window.
+//
+BOOL InitInstance(HINSTANCE hInstance, int nCmdShow)
+{
+   hInst = hInstance; // Store instance handle in our global variable
+
+   hWnd = CreateWindow (szWindowClass, szTitle, WS_OVERLAPPEDWINDOW,
+      0, 0, gBackbufferWidth, gBackbufferHeight, nullptr, nullptr, hInstance, nullptr);
+
+   if (!hWnd)
+   {
+      return FALSE;
+   }
+
+   ShowWindow(hWnd, nCmdShow);
+   UpdateWindow(hWnd);
+
+   return TRUE;
+}
+
+//
+//  FUNCTION: WndProc(HWND, UINT, WPARAM, LPARAM)
+//
+//  PURPOSE:  Processes messages for the main window.
+//
+//  WM_COMMAND  - process the application menu
+//  WM_PAINT    - Paint the main window
+//  WM_DESTROY  - post a quit message and return
+//
+//
+LRESULT CALLBACK WndProc(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam)
+{
+    switch (message)
+    {
+    //case WM_COMMAND:
+    //    {
+    //        int wmId = LOWORD(wParam);
+    //        // Parse the menu selections:
+    //        switch (wmId)
+    //        {
+    //        case IDM_ABOUT:
+    //            DialogBox(hInst, MAKEINTRESOURCE(IDD_ABOUTBOX), hWnd, About);
+    //            break;
+	//		case ID_FILE_SAVEIMAGE:
+	//		{
+	//			SaveImage();
+	//			break;
+	//		}
+	//		case ID_FILE_RENDERTIME:
+	//		{
+	//			const size_t len = 256;
+	//			wchar_t buffer[len] = {};
+	//			swprintf(buffer, L"Total Render Time : %0.2f seconds!", TotalRenderTime);
+	//			MessageBox(hWnd, buffer, L"Render Time", 0);
+	//			break;
+	//		}
+    //        case IDM_EXIT:
+    //            DestroyWindow(hWnd);
+    //            break;
+    //        default:
+    //            return DefWindowProc(hWnd, message, wParam, lParam);
+    //        }
+    //    }
+    //    break;
+    case WM_PAINT:
+        {
+            PAINTSTRUCT ps;
+            HDC hdc = BeginPaint(hWnd, &ps);
+
+			Execute(hdc);
+
+			OutputDebugString(L"This is paint!");
+
+            EndPaint(hWnd, &ps);
+        }
+        break;
+    case WM_DESTROY:
+        PostQuitMessage(0);
+        break;
+    default:
+        return DefWindowProc(hWnd, message, wParam, lParam);
+    }
+    return 0;
+}
+
+// Message handler for about box.
+INT_PTR CALLBACK About(HWND hDlg, UINT message, WPARAM wParam, LPARAM lParam)
+{
+    UNREFERENCED_PARAMETER(lParam);
+    switch (message)
+    {
+    case WM_INITDIALOG:
+        return (INT_PTR)TRUE;
+
+    case WM_COMMAND:
+        if (LOWORD(wParam) == IDOK || LOWORD(wParam) == IDCANCEL)
+        {
+            EndDialog(hDlg, LOWORD(wParam));
+            return (INT_PTR)TRUE;
+        }
+        break;
+    }
+    return (INT_PTR)FALSE;
+}
diff --git a/WindowsRayTracer.h b/WindowsRayTracer.h
new file mode 100644
index 0000000..c4aafa3
--- /dev/null
+++ b/WindowsRayTracer.h
@@ -0,0 +1,3 @@
+﻿#pragma once
+
+#include "resource.h"
diff --git a/header.h b/header.h
new file mode 100644
index 0000000..e3fd0b3
--- /dev/null
+++ b/header.h
@@ -0,0 +1,20 @@
+﻿// header.h : include file for standard system include files,
+// or project specific include files
+//
+
+#pragma once
+
+#include "targetver.h"
+
+#define WIN32_LEAN_AND_MEAN             // Exclude rarely-used stuff from Windows headers
+// Windows Header Files:
+#include <windows.h>
+
+// C RunTime Header Files
+#include <stdlib.h>
+#include <malloc.h>
+#include <memory.h>
+#include <tchar.h>
+
+
+// TODO: reference additional headers your program requires here
```

