# Post 6 — Fixing it: detached threads, no shared HDC, and a real scheduler

## `55d3021` — 2019-02-25 _(master)_

> Removing dependency on passing HDC

```diff
diff --git a/Application.cpp b/Application.cpp
index 3ab6184..b17d3b9 100644
--- a/Application.cpp
+++ b/Application.cpp
@@ -44,7 +44,7 @@ void Application::Initialize(HWND hwnd, bool _threaded)
 }
 
 ///////////////////////////////////////////////////////////////////////////////////////////////////
-void Application::Execute(HDC _hdc)
+void Application::Execute()
 {
 	int percentageDone = 0.0f;
 
diff --git a/Application.h b/Application.h
index 9583051..d2ecc1e 100644
--- a/Application.h
+++ b/Application.h
@@ -15,7 +15,7 @@ public:
 	~Application();
 
 	void			Initialize(HWND hwnd, bool _threaded);
-	void			Execute(HDC _hdc);
+	void			Execute();
 	void			SaveImage();
 
 	inline int		GetBufferWidth() { return m_iBackbufferWidth; }
diff --git a/WindowsRayTracer.cpp b/WindowsRayTracer.cpp
index 495a771..d60e1f2 100644
--- a/WindowsRayTracer.cpp
+++ b/WindowsRayTracer.cpp
@@ -48,7 +48,7 @@ int APIENTRY wWinMain(_In_ HINSTANCE hInstance,
 
     HACCEL hAccelTable = LoadAccelerators(hInstance, MAKEINTRESOURCE(IDC_WINDOWSRAYTRACER));
 
-    MSG msg;	
+	MSG msg = { 0 };
 
     // Main message loop:
     while (GetMessage(&msg, nullptr, 0, 0))
@@ -60,6 +60,19 @@ int APIENTRY wWinMain(_In_ HINSTANCE hInstance,
         }
     }
 
+	//while (msg.message != WM_QUIT)
+	//{
+	//	if (PeekMessage(&msg, NULL, 0U, 0U, PM_REMOVE))
+	//	{
+	//		TranslateMessage(&msg);
+	//		DispatchMessage(&msg);
+	//	}
+	//	else
+	//	{
+	//		pApp->Execute();
+	//	}
+	//}
+
     return (int) msg.wParam;
 }
 
@@ -174,7 +187,7 @@ LRESULT CALLBACK WndProc(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam)
             PAINTSTRUCT ps;
             HDC hdc = BeginPaint(hWnd, &ps);
 
-			pApp->Execute(hdc);
+			pApp->Execute();
 
 			OutputDebugString(L"This is paint!");
 
```

## `c36fae0` — 2019-04-14 _(OpenGL branch)_

> Fixed multithreaded rendering by deteaching thread execution.

```diff
diff --git a/Main/Application.cpp b/Main/Application.cpp
index 58a3da3..6b464f4 100644
--- a/Main/Application.cpp
+++ b/Main/Application.cpp
@@ -55,12 +55,11 @@ void Application::Initialize(bool _threaded)
 	m_pQuad = new ScreenAlignedQuad();
 	m_pQuad->Init(m_iBackbufferWidth, m_iBackbufferHeight);
 
-	glm::vec3 col = glm::vec3(1, 0, 0);
+	glm::vec3 col = glm::vec3(0, 0, 0);
 	for (int i = 0; i < m_iBackbufferWidth * m_iBackbufferHeight; i++)
 	{
 		vecBuffer.push_back(col);
 	}
-	std::copy(vecBuffer.begin(), vecBuffer.end(), std::back_inserter(copyBuffer));
 }
 
 ///////////////////////////////////////////////////////////////////////////////////////////////////
@@ -177,7 +176,7 @@ void Application::ShowProgress(int percentage)
 ///////////////////////////////////////////////////////////////////////////////////////////////////
 void Application::ParallelTrace(std::mutex * threadMutex, int i, GLFWwindow* window)
 {
-	threadMutex->lock();
+	//threadMutex->lock();
 
 	int backBufferHeight = m_iBackbufferHeight;
 	int backBufferWidth = m_iBackbufferWidth;
@@ -204,7 +203,7 @@ void Application::ParallelTrace(std::mutex * threadMutex, int i, GLFWwindow* win
 
 	int rayCount = 0;
 
-	threadMutex->unlock();
+	//threadMutex->unlock();
 
 	// Error check for bounds!
 	if (startWidth < endWidth && startHeight < endHeight)
@@ -228,9 +227,9 @@ void Application::ParallelTrace(std::mutex * threadMutex, int i, GLFWwindow* win
 				color = color / float(ns);
 				color = glm::vec3(sqrt(color.x), sqrt(color.y), sqrt(color.z));
 
-				threadMutex->lock();
+				//threadMutex->lock();
 				vecBuffer[j * endWidth + i] = color;
-				threadMutex->unlock();
+				//threadMutex->unlock();
 			}
 		}
 	}
@@ -241,12 +240,9 @@ void Application::ParallelTrace(std::mutex * threadMutex, int i, GLFWwindow* win
 ///////////////////////////////////////////////////////////////////////////////////////////////////
 void Application::UpdateGL(GLFWwindow* window)
 {
-	copyBuffer.clear();
-	std::copy(vecBuffer.begin(), vecBuffer.end(), std::back_inserter(copyBuffer));
-
 	m_pQuad->UpdateTexture(0, 0, m_iBackbufferWidth, m_iBackbufferHeight, glm::value_ptr(vecBuffer[0]));
 	m_pQuad->Render();
-
+	
 	glfwSwapBuffers(window);
 }
 
@@ -270,8 +266,7 @@ void Application::Trace(GLFWwindow* window)
 		std::vector<std::thread*>::iterator iter = ThreadGroup.begin();
 		for (; iter != ThreadGroup.end(); iter++)
 		{
-			//if((*iter)->joinable())
-			(*iter)->join();
+			(*iter)->detach();
 		}
 	}
 	else
diff --git a/Main/Application.h b/Main/Application.h
index d8dd75e..9259ce6 100644
--- a/Main/Application.h
+++ b/Main/Application.h
@@ -40,17 +40,16 @@ private:
 	double				m_dTotalRenderTime;
 	bool				m_bThreaded;
 
-	std::atomic<uint64_t>	m_iRayCount;
+	std::atomic<uint64_t>	 m_iRayCount;
 	std::atomic<uint64_t>    m_iRayTriangleQuery;
 	std::atomic<uint64_t>    m_iRayTriangleSuccess;
 	std::atomic<uint64_t>    m_iRayBoxQuery;
-	std::atomic<uint64_t>	m_iRayBoxSuccess;
+	std::atomic<uint64_t>	 m_iRayBoxSuccess;
 	std::atomic<uint64_t>    m_iTriangleCount;
 
 	Camera*				m_pCamera;
 
 	ScreenAlignedQuad*	m_pQuad;
 
-	std::vector<glm::vec3>	copyBuffer;
 	std::vector<glm::vec3>  vecBuffer;
 };
diff --git a/Main/Main.cpp b/Main/Main.cpp
index 0c71caa..a08012b 100644
--- a/Main/Main.cpp
+++ b/Main/Main.cpp
@@ -76,7 +76,12 @@ int main()
 
 	glfwSetKeyCallback(window, KeyHandler);
 
+#ifdef NDEBUG
 	pApp->Initialize(true);
+#else
+	pApp->Initialize(false);
+#endif
+
 	pApp->Execute(window);
 
 	while (!glfwWindowShouldClose(window))
```

## `a911dbe` — 2019-12-29 _(OpenGL branch)_

> - Added Marl Scheduler (Optional) - Added Various projection methods (Orthographic, Perspective, FishEye & Spherical) - Added WIP HDRI texture support

```diff
diff --git a/Main/Application.cpp b/Main/Application.cpp
index 897c422..dbbaee4 100644
--- a/Main/Application.cpp
+++ b/Main/Application.cpp
@@ -17,15 +17,23 @@
 #include "ScreenAlignedQuad.h"
 #include "Application.h"
 
+#include "marl/defer.h"
+#include "marl/scheduler.h"
+#include "marl/thread.h"
+#include "marl/waitgroup.h"
+
 #define STB_IMAGE_WRITE_IMPLEMENTATION
 #include "stb_image_write.h"
 
+#define CPLUSPLUS_THREADING 1
+//#define MARL_SCHEDULING 1
+
 ///////////////////////////////////////////////////////////////////////////////////////////////////
 Application::Application()
 {
-	m_iBackbufferWidth = 1500;
+	m_iBackbufferWidth = 500;
 	m_iBackbufferHeight = 500;
-	m_iNumSamples = 200;
+	m_iNumSamples = 10;
 	m_dTotalRenderTime = 0;
 	m_dDenoiserTime = 0;
 	m_bThreaded = false;
@@ -58,8 +66,10 @@ void Application::Initialize(bool _threaded)
 	_threaded ? m_iMaxThreads = std::thread::hardware_concurrency() : 0;
 
 	m_pScene = new Scene();
-	m_pScene->InitScene(m_iBackbufferWidth, m_iBackbufferHeight);
+	//m_pScene->InitRefractionScene(m_iBackbufferWidth, m_iBackbufferHeight);
+	//m_pScene->InitSphereScene(m_iBackbufferWidth, m_iBackbufferHeight);
 	//m_pScene->InitCornellScene(m_iBackbufferWidth, m_iBackbufferHeight);
+	m_pScene->InitTigerScene(m_iBackbufferWidth, m_iBackbufferHeight);
 	//m_pScene->InitTowerScene(m_iBackbufferWidth, m_iBackbufferHeight);
 
 	m_pQuad = new ScreenAlignedQuad();
@@ -68,11 +78,11 @@ void Application::Initialize(bool _threaded)
 	glm::vec3 col = glm::vec3(0, 0, 0);
 	for (int i = 0; i < m_iBackbufferWidth * m_iBackbufferHeight; i++)
 	{
-		vecBuffer.push_back(col);
-		m_vecDstBuffer.push_back(col);
+		m_vecSrcPixels.push_back(col);
+		m_vecDstPixels.push_back(col);
 	}
 
-  // Create Open Image Denoise Device
+	// Create Open Image Denoise Device
 	m_oidnDevice = oidn::newDevice();
 	m_oidnDevice.set("numThreads", m_iMaxThreads);
 	m_oidnDevice.commit();
@@ -226,22 +236,20 @@ glm::vec3 Application::TraceColor(const Ray & r, int depth, int& rayCount)
 
 		if (depth < 50 && rec.mat_ptr->Scatter(r, rec, rayCount, attenuation, scatteredRay))
 		{
-			if (glm::distance(scatteredRay.GetRayOrigin(), scatteredRay.GetRayDirection()) < 0.0000001f)
-				traceColor = emitted + attenuation;
-			else
-				traceColor = emitted + (attenuation * (TraceColor(scatteredRay, depth + 1, rayCount)));
+			traceColor = emitted + (attenuation * (TraceColor(scatteredRay, depth + 1, rayCount)));
 		}
 		else
 		{
+			// This is light source, simply return emitted color!
 			return emitted;
 		}
 	}
 	else
 	{
-		//glm::vec3 unit_direction = glm::normalize(r.GetRayDirection());
+		glm::vec3 unit_direction = glm::normalize(r.direction);
 		//float t = 0.5f * (unit_direction[1] + 1.0f);
 		//traceColor = Helper::LerpVector(glm::vec3(1.0f, 1.0f, 1.0f), glm::vec3(0.5f, 0.7f, 1.0f), t);
-		return m_pScene->getMissColor();
+		return m_pScene->CalculateMissColor(unit_direction);
 	}
 
 	// debug info...
@@ -303,8 +311,8 @@ void Application::ParallelTrace(std::mutex * threadMutex, int i, GLFWwindow* win
 
 				for (int s = 0; s < ns; s++)
 				{
-					float u = float(i + Helper::GetRandom01()) / float(backBufferWidth);
-					float v = float(j + Helper::GetRandom01()) / float(backBufferHeight);
+					float u = float(i + Helper::GetRandom01());// / float(backBufferWidth);
+					float v = float(j + Helper::GetRandom01());// / float(backBufferHeight);
 
 					Ray r = m_pScene->getCamera()->get_ray(u, v);
 
@@ -315,7 +323,7 @@ void Application::ParallelTrace(std::mutex * threadMutex, int i, GLFWwindow* win
 				color = glm::vec3(sqrt(color.x), sqrt(color.y), sqrt(color.z));
 
 				//threadMutex->lock();
-				vecBuffer[j * endWidth + i] = color;
+				m_vecSrcPixels[j * endWidth + i] = color;
 				//threadMutex->unlock();
 			}
 		}
@@ -324,19 +332,45 @@ void Application::ParallelTrace(std::mutex * threadMutex, int i, GLFWwindow* win
 	m_iRayCount += rayCount;
 }
 
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void Application::RenderPixel(int rowIndex, int columnIndex)
+{
+	glm::vec3 color(0, 0, 0);
+	int rayCount = 0;
+
+	for (int s = 0; s < m_iNumSamples; s++)
+	{
+		float u = float(columnIndex + Helper::GetRandom01()) / float(m_iBackbufferWidth);
+		float v = float(rowIndex + Helper::GetRandom01()) / float(m_iBackbufferHeight);
+
+		Ray r = m_pScene->getCamera()->get_ray(u, v);
+
+		color = color + TraceColor(r, 0, rayCount);
+	}
+
+	color = color / float(m_iNumSamples);
+	color = glm::vec3(sqrt(color.x), sqrt(color.y), sqrt(color.z));
+
+	int index = columnIndex + m_iBackbufferWidth * rowIndex;
+	if (index < m_iBackbufferWidth * m_iBackbufferHeight)
+	{
+		m_vecSrcPixels[index] = color;
+	}
+}
+
 ///////////////////////////////////////////////////////////////////////////////////////////////////
 void Application::UpdateGL(GLFWwindow* window)
 {
 	// Message Loop!
 	while (!glfwWindowShouldClose(window))
 	{
-		m_vecDstBuffer = vecBuffer;
+		m_vecDstPixels = m_vecSrcPixels;
 
 		glfwPollEvents();
 		glClearColor(1.0f, 1.0f, 1.0f, 1.0f);
 		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
 
-		m_pQuad->UpdateTexture(0, 0, m_iBackbufferWidth, m_iBackbufferHeight, glm::value_ptr(m_vecDstBuffer[0]));
+		m_pQuad->UpdateTexture(0, 0, m_iBackbufferWidth, m_iBackbufferHeight, glm::value_ptr(m_vecDstPixels[0]));
 		m_pQuad->Render();
 
 		glfwSwapBuffers(window);
@@ -349,58 +383,86 @@ void Application::Trace(GLFWwindow* window)
 	if (m_pScene == nullptr)
 		return;
 
-	if (m_bThreaded)
-	{
-		std::vector<std::thread*> ThreadGroup;
-		std::mutex threadMutex;
+#if defined _DEBUG
 
-		for (int i = 0; i < m_iMaxThreads; i++)
-		{
-			std::thread* t = new std::thread(&Application::ParallelTrace, this, &threadMutex, i, window);
-			ThreadGroup.push_back(t);
-		}
+	int rayCount = 0;
 
-		std::vector<std::thread*>::iterator iter = ThreadGroup.begin();
-		for (; iter != ThreadGroup.end(); iter++)
+	for (int j = 0; j < m_iBackbufferHeight; j++)
+	{
+		std::vector<glm::vec3> rowColor;
+		for (int i = 0; i < m_iBackbufferWidth; i++)
 		{
-			(*iter)->detach();
+			glm::vec3 color(0, 0, 0);
+
+			for (int s = 0; s < m_iNumSamples; s++)
+			{
+				float u = float(i + Helper::GetRandom01());// / float(m_iBackbufferWidth);
+				float v = float(j + Helper::GetRandom01());// / float(m_iBackbufferHeight);
+
+				Ray r = m_pScene->getCamera()->get_ray(u, v);
+
+				color = color + TraceColor(r, 0, rayCount);
+			}
+
+			color = color / float(m_iNumSamples);
+			color = glm::vec3(sqrt(color.x), sqrt(color.y), sqrt(color.z));
+
+			//m_vecSrcPixels[j * gBackbufferWidth + i] = color;
+
+			rowColor.push_back(color);
 		}
+
+		m_pQuad->UpdateTexture(0, j, m_iBackbufferWidth, 1, glm::value_ptr(rowColor[0]));
+		m_pQuad->Render();
+		glfwSwapBuffers(window);
+		rowColor.clear();
 	}
-	else
-	{
-		int rayCount = 0;
 
-		for (int j = 0; j < m_iBackbufferHeight; j++)
-		{
-			std::vector<glm::vec3> rowColor;
-			for (int i = 0; i < m_iBackbufferWidth; i++)
-			{
-				glm::vec3 color(0, 0, 0);
+	m_iRayCount += rayCount;
 
-				for (int s = 0; s < m_iNumSamples; s++)
-				{
-					float u = float(i + Helper::GetRandom01()) / float(m_iBackbufferWidth);
-					float v = float(j + Helper::GetRandom01()) / float(m_iBackbufferHeight);
+#else
 
-					Ray r = m_pScene->getCamera()->get_ray(u, v);
+#if defined CPLUSPLUS_THREADING 
+	std::vector<std::thread*> ThreadGroup;
+	std::mutex threadMutex;
 
-					color = color + TraceColor(r, 0, rayCount);
-				}
+	for (int i = 0; i < m_iMaxThreads; i++)
+	{
+		std::thread* t = new std::thread(&Application::ParallelTrace, this, &threadMutex, i, window);
+		ThreadGroup.push_back(t);
+	}
 
-				color = color / float(m_iNumSamples);
-				color = glm::vec3(sqrt(color.x), sqrt(color.y), sqrt(color.z));
+	std::vector<std::thread*>::iterator iter = ThreadGroup.begin();
+	for (; iter != ThreadGroup.end(); iter++)
+	{
+		(*iter)->detach();
+	}
+#elif defined MARL_SCHEDULING
+	// Marl Scheduler related...
+	marl::Scheduler scheduler;
+	scheduler.setWorkerThreadCount(marl::Thread::numLogicalCPUs());
+	scheduler.bind();
+	defer(scheduler.unbind());
 
-				//vecBuffer[j * gBackbufferWidth + i] = color;
+	marl::WaitGroup wg(m_iBackbufferHeight);
 
-				rowColor.push_back(color);
-			}
+	for (uint32_t y = 0; y < m_iBackbufferHeight; y++)
+	{
+		marl::schedule([=] {
 
-			m_pQuad->UpdateTexture(0, j, m_iBackbufferWidth, 1, glm::value_ptr(rowColor[0]));
-			m_pQuad->Render();
-			glfwSwapBuffers(window);
-			rowColor.clear();
-		}
+			defer(wg.done());
 
-		m_iRayCount += rayCount;
+			for (uint32_t x = 0; x < m_iBackbufferWidth; x++)
+			{
+				RenderPixel(y, x);
+			}
+			});
 	}
+
+	wg.wait();
+#endif
+
+#endif
+
+	
 }
\ No newline at end of file
diff --git a/Main/Application.h b/Main/Application.h
index 0fa6813..c9ef4cc 100644
--- a/Main/Application.h
+++ b/Main/Application.h
@@ -32,6 +32,7 @@ private:
 	glm::vec3			TraceColor(const Ray& r, int depth, int& rayCount);
 	void				ShowProgress(int percentage);
 	void				ParallelTrace(std::mutex* threadMutex, int i, GLFWwindow* window);
+	void				RenderPixel(int rowIndex, int columnIndex);
 	void				Trace(GLFWwindow* window);
 
 
@@ -53,8 +54,8 @@ private:
 	ScreenAlignedQuad*	m_pQuad;
 	Scene*				m_pScene;
 
-	std::vector<glm::vec3>  vecBuffer;
-	std::vector<glm::vec3>	m_vecDstBuffer;
+	std::vector<glm::vec3>  m_vecSrcPixels;
+	std::vector<glm::vec3>	m_vecDstPixels;
 
 	oidn::DeviceRef	m_oidnDevice;
 	oidn::FilterRef m_oidnFilter;
diff --git a/RayTracer/AABB.cpp b/RayTracer/AABB.cpp
index 158f494..8031896 100644
--- a/RayTracer/AABB.cpp
+++ b/RayTracer/AABB.cpp
@@ -51,11 +51,11 @@ bool AABB::hit(const Ray & r, float tmin, float tmax, HitRecord& rec)
 
 	for (int a = 0; a < 3; a++)
 	{
-		float t0 = fminf((minBound[a] - r.GetRayOrigin()[a]) / r.GetRayDirection()[a],
-						 (maxBound[a] - r.GetRayOrigin()[a]) / r.GetRayDirection()[a]);
+		float t0 = fminf((minBound[a] - r.origin[a]) / r.direction[a],
+						 (maxBound[a] - r.origin[a]) / r.direction[a]);
 
-		float t1 = fmaxf((minBound[a] - r.GetRayOrigin()[a]) / r.GetRayDirection()[a],
-						 (maxBound[a] - r.GetRayOrigin()[a]) / r.GetRayDirection()[a]);
+		float t1 = fmaxf((minBound[a] - r.origin[a]) / r.direction[a],
+						 (maxBound[a] - r.origin[a]) / r.direction[a]);
 
 		tmin = fmaxf(t0, tmin);
 		tmax = fminf(t1, tmax);
diff --git a/RayTracer/Camera.cpp b/RayTracer/Camera.cpp
index 0d6baf2..f4dfdf1 100644
--- a/RayTracer/Camera.cpp
+++ b/RayTracer/Camera.cpp
@@ -9,9 +9,15 @@ Camera::Camera()
 	lookAt = glm::vec3(0.0f, 0.0f, 0.0f);
 	Up = glm::vec3(0.0f, 1.0f, 0.0f);
 
-	aperture = 0.0f;
-	focus_dist = 1.0f;
-	vfov = 45.0f;
+	viewPlaneDistance = 0.0f;
+
+	screenWidht = 0.0f;
+	screenHeight = 0.0f;
+
+	psi_max = 180.0f;
+	lambda_max = 180.0f;
+
+	projectionType = eProjectionType::FISHEYE;
 }
 
 ///////////////////////////////////////////////////////////////////////////////////////////////////
@@ -21,32 +27,152 @@ Camera::~Camera()
 }
 
 ///////////////////////////////////////////////////////////////////////////////////////////////////
-void Camera::InitCamera(const glm::vec3& _position, const glm::vec3& _lookAt, float screenWidth, float screenHeight)
+void Camera::InitCamera(const glm::vec3& _position, const glm::vec3& _lookAt, float _screenWidth, float _screenHeight)
 {
+	// Camera params
 	position = _position;
 	lookAt = _lookAt;
 
-	lens_radius = aperture / 2.0f;
-	 
-	float theta = vfov * PI / 180.0f;
-	float half_height = tan(theta / 2);
-	float half_width = (screenWidth / screenHeight) * half_height;
+	// Common screen params
+	screenWidht = _screenWidth;
+	screenHeight = _screenHeight;
+	halfHeight = _screenHeight * 0.5f;
+	halfWidth = _screenWidth * 0.5f;
 
+	// Basic vectors
 	// For OpenGL, order of Cross product changes!
 	w = glm::normalize(position - lookAt);
 	u = glm::normalize(glm::cross(w, Up));
 	v = glm::normalize(glm::cross(u, w));
 
-	lower_left_corner = position - half_width * focus_dist * u - half_height * focus_dist * v - focus_dist * w;
-	horizontal = 2 * half_width * focus_dist * u;
-	vertical = 2 * half_height * focus_dist * v;
+	switch (projectionType)
+	{
+		case eProjectionType::PERSPECTIVE:
+		{
+			// FOV & Distance "d" from Eye position to View Plane are inter-dependent! 
+			// We can use any one as per user convenience. 
+			// tan(fov/2) = ( 0.5 * screenHeight ) / d;
+			// or
+			// d = screenHeight / 2 * tan(fov/2)
+			// We will be using "d" for the sake of it. 
+			viewPlaneDistance = 400.0f;
+			break;
+		}
+
+		case eProjectionType::FISHEYE:
+		{
+			break;
+		}
+
+		case eProjectionType::SPHERICAL:
+		{
+			break;
+		}
+
+		case eProjectionType::OTHOGRAPHIC:
+		{
+			u = glm::vec3(1, 0, 0);
+			v = glm::vec3(0, 1, 0);
+			// For OpenGL, order of Cross product changes!		
+
+			break;
+		}
+
+		default:
+		{
+			break;
+		}
+	}
 }
 
 ///////////////////////////////////////////////////////////////////////////////////////////////////
 Ray Camera::get_ray(float s, float t)
 {
-	glm::vec3 rd = lens_radius * Helper::GetRandomInUnitDisk();
-	glm::vec3 offset = rd[0] * u + rd[1] * v;
-	return Ray(position + offset, lower_left_corner + s * horizontal + t * vertical - position - offset);
+	Ray ray;
+	ray.origin = glm::vec3(0);
+	ray.direction = glm::vec3(0);
+
+	switch (projectionType)
+	{
+		case eProjectionType::PERSPECTIVE:
+		{
+			ray.origin = position;
+			
+			glm::vec3 pos = glm::vec3(s - halfWidth, t - halfHeight, 0.0f);
+			ray.direction = pos.x * u + pos.y * v - viewPlaneDistance * w;
+
+			break;
+		}
+
+		case eProjectionType::FISHEYE:
+		{
+			ray.origin = position;
+
+			// Compute Normalized Device coordinates
+			glm::vec2 ndc(0, 0);
+			ndc.x = (2.0f / screenWidht) * (s - halfWidth);
+			ndc.y = (2.0f / screenHeight) * (t - halfHeight);
+
+			float r_squared = ndc.x * ndc.x + ndc.y * ndc.y;
+
+			if (r_squared <= 1.0f)
+			{
+				float r = sqrt(r_squared);
+				float psi = glm::radians(r * psi_max);
+				float sin_psi = sin(psi);
+				float cos_psi = cos(psi);
+				float sin_alpha = ndc.y / r;
+				float cos_alpha = ndc.x / r;
+
+				ray.direction = sin_psi * cos_alpha * u + sin_psi * sin_alpha * v - cos_psi * w;
+			}
+
+			break;
+		}
+
+		case eProjectionType::SPHERICAL:
+		{
+			ray.origin = position;
+
+			// Compute Normalized Device coordinates
+			glm::vec2 ndc(0, 0);
+			ndc.x = (2.0f / screenWidht) * (s - halfWidth);
+			ndc.y = (2.0f / screenHeight) * (t - halfHeight);
+
+			// compute angles lambda & phi in radians
+			float lambda = glm::radians(ndc.x * lambda_max);
+			float psi = glm::radians(ndc.y * psi_max);
+
+			// Compute the spherical azimuth & polar angles
+			float phi = PI - lambda;
+			float theta = 0.5f * PI - psi;
+
+			float sin_phi = sin(phi);
+			float cos_phi = cos(phi);
+			float sin_theta = sin(theta);
+			float cos_theta = cos(theta);
+
+			ray.direction = sin_theta * sin_phi * u + cos_theta * v + sin_theta * cos_phi * w;
+
+			break;
+		}
+
+		case eProjectionType::OTHOGRAPHIC:
+		{
+			float pixelScale = 1.0f; // controls zoom level
+
+			ray.origin = glm::vec3(pixelScale * (s - halfWidth), pixelScale * (t - halfHeight), 0.0f);
+			ray.direction = glm::vec3(0, 0, -1);
+
+			break;
+		}
+
+		default:
+		{
+			break;
+		}
+	}
+
+	return ray;
 }
 
diff --git a/RayTracer/Camera.h b/RayTracer/Camera.h
index 8b093bc..b7bc438 100644
--- a/RayTracer/Camera.h
+++ b/RayTracer/Camera.h
@@ -3,6 +3,14 @@
 #include "Ray.h"
 #include "Helper.h"
 
+enum eProjectionType
+{
+	OTHOGRAPHIC,
+	PERSPECTIVE,
+	FISHEYE,
+	SPHERICAL,
+};
+
 class Camera
 {
 public:
@@ -13,11 +21,26 @@ public:
 	Ray get_ray(float s, float t);
 
 private:
-	glm::vec3 position, lookAt, Up;
-	glm::vec3 origin;
-	glm::vec3 lower_left_corner;
-	glm::vec3 horizontal;
-	glm::vec3 vertical;
-	glm::vec3 u, v, w;
-	float lens_radius, aperture, vfov, focus_dist;
+	// Camera vectors
+	glm::vec3		position, lookAt, Up;
+
+	// basis vectors
+	glm::vec3		u, v, w;
+
+	// screen params
+	float			halfWidth;
+	float			halfHeight;
+	float			screenWidht;
+	float			screenHeight;
+
+	// For Perspective
+	float			viewPlaneDistance;
+
+	// For Fisheye
+	float			psi_max;
+
+	// For Spherical
+	float			lambda_max;
+
+	eProjectionType projectionType;
 };
diff --git a/RayTracer/Helper.h b/RayTracer/Helper.h
index 1af822c..aaf935f 100644
--- a/RayTracer/Helper.h
+++ b/RayTracer/Helper.h
@@ -42,6 +42,17 @@ namespace Helper
 		return P;
 	}
 
+	inline glm::vec3 RandomUnitVector()
+	{
+		float z = GetRandom01() * 2.0f - 1.0f;
+		float a = GetRandom01() * 2.0f * PI;
+		float r = sqrtf(1.0f - z * z);
+		float x = r * cosf(a);
+		float y = r * sinf(a);
+
+		return glm::vec3(x, y, z);
+	}
+
 	inline glm::vec3 Reflect(const glm::vec3& dir, const glm::vec3& normal)
 	{
 		return (dir - 2.0f * glm::dot(dir, normal) * normal);
diff --git a/RayTracer/Lambertian.cpp b/RayTracer/Lambertian.cpp
index 65eb004..a977d04 100644
--- a/RayTracer/Lambertian.cpp
+++ b/RayTracer/Lambertian.cpp
@@ -4,7 +4,7 @@
 
 bool Lambertian::Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& attenuation, Ray& scatterd) const
 {
-	glm::vec3 target = rec.P + rec.N + Helper::RandomInUnitSphere();
+	glm::vec3 target = rec.P + rec.N + Helper::RandomUnitVector();
 	scatterd = Ray(rec.P, target - rec.P);
 	++rayCount;
 
diff --git a/RayTracer/Metal.cpp b/RayTracer/Metal.cpp
index 8f28466..950519b 100644
--- a/RayTracer/Metal.cpp
+++ b/RayTracer/Metal.cpp
@@ -4,10 +4,10 @@
 
 bool Metal::Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& attenuation, Ray& scatterd) const
 {
-	glm::vec3 target = glm::normalize(Helper::Reflect(r_in.GetRayDirection(), rec.N));
+	glm::vec3 target = glm::normalize(Helper::Reflect(r_in.direction, rec.N));
 	scatterd = Ray(rec.P, target + fuzz * Helper::RandomInUnitSphere());
 	++rayCount;
 
 	attenuation = Albedo->value(rec.uv);
-	return (glm::dot(scatterd.GetRayDirection(), rec.N) > 0);
+	return (glm::dot(scatterd.direction, rec.N) > 0);
 }
\ No newline at end of file
diff --git a/RayTracer/Ray.h b/RayTracer/Ray.h
index 96ef8d8..1cdc863 100644
--- a/RayTracer/Ray.h
+++ b/RayTracer/Ray.h
@@ -20,12 +20,8 @@ public:
 		invDirection = glm::vec3(1.0f / direction[0], 1.0f/direction[1], 1.0f/direction[2]);
 	}
 
-	inline glm::vec3 GetRayOrigin() const { return origin; }
-	inline glm::vec3 GetRayDirection() const { return direction; }
-	inline glm::vec3 GetInvRayDirection() const { return invDirection; }
 	inline glm::vec3 GetPointAt(float t) const { return origin + t * direction; }
 
-private:
 	glm::vec3 origin;
 	glm::vec3 direction;
 	glm::vec3 invDirection;
diff --git a/RayTracer/Scene.cpp b/RayTracer/Scene.cpp
index 902d28b..0022bf9 100644
--- a/RayTracer/Scene.cpp
+++ b/RayTracer/Scene.cpp
@@ -33,10 +33,76 @@ Scene::~Scene()
 }
 
 ///////////////////////////////////////////////////////////////////////////////////////////////////
-void Scene::InitScene(float screenWidth, float screenHeight)
+void Scene::InitSphereScene(float screenWidth, float screenHeight)
 {
 	// Initialize Camera first...!!!
-	glm::vec3 cameraPosition = glm::vec3(-3.0f, 1.5f, 5.0f);
+	glm::vec3 cameraPosition = glm::vec3(0.0f, 3.5f, 7.0f);
+	glm::vec3 cameraLookAt = glm::vec3(0.0f, 0.0f, 0.0f);
+	m_pCamera = new Camera();
+	m_pCamera->InitCamera(cameraPosition, cameraLookAt, screenWidth, screenHeight);
+
+	// Override miss color to black
+	m_colMiss = glm::vec4(0.78f, 0.88f, 1.0f, 1.0f);
+
+	// Sphere Ground
+	glm::vec3 center1(0.0f, -200.5f, 0.0f);
+	glm::vec3 albedo1(0.2f, 0.2f, 0.2f);
+	Material* pMatSphereGround = new Lambertian(new ConstantTexture(glm::vec3(0.25f, 0.25f, 0.25f)));
+	Sphere* pSphereGround = new Sphere(center1, 200.0f, pMatSphereGround);
+
+	CheckeredTexture* checksTexture = new CheckeredTexture(glm::vec3(0.2f, 0.9f, 0.5f), glm::vec3(0.03f), 10.0f, 10.0f);
+	glm::vec4 glassColor = glm::vec4(1, 1, 0, 1);
+
+	Sphere* pSphereGlass1 = new Sphere(glm::vec3(-4.0f, 0.4f, 0.0f), 1.0f, new Transparent(new ConstantTexture(glassColor), 1.5f));
+	Sphere* pSphereMetal = new Sphere(glm::vec3(3.5f, 0.5f, 0.0f), 1.0f, new Metal(checksTexture, 0.1f));
+	Sphere* pSphereLight = new Sphere(glm::vec3(-1.5f, 0.5f, 0.0f), 0.75f, new DiffuseLight(new ConstantTexture(glm::vec3(1.0f, 1.0f, 1.0f))));
+	Sphere* pSphereEarth = new Sphere(glm::vec3(0.5f, 0.0f, 0.0f), 0.5, new Lambertian(new ImageTexture("models/earth.jpg")));
+
+	//Profiler::getInstance().WriteToProfiler("Triangle Count:", pMesh0->GetTriangleCount());
+
+	vecHitables.push_back(pSphereGround);
+	vecHitables.push_back(pSphereGlass1);
+	vecHitables.push_back(pSphereMetal);
+	vecHitables.push_back(pSphereEarth);
+	vecHitables.push_back(pSphereLight);
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void Scene::InitRefractionScene(float screenWidth, float screenHeight)
+{
+	// Initialize Camera first...!!!
+	glm::vec3 cameraPosition = glm::vec3(0.0f, 3.5f, 7.0f);
+	glm::vec3 cameraLookAt = glm::vec3(0.0f, 0.0f, 0.0f);
+	m_pCamera = new Camera();
+	m_pCamera->InitCamera(cameraPosition, cameraLookAt, screenWidth, screenHeight);
+
+	// Override miss color to black
+	m_colMiss = glm::vec4(0.78f, 0.88f, 1.0f, 1.0f);
+
+	// Sphere Ground
+	glm::vec3 center1(0.0f, -200.5f, 0.0f);
+	glm::vec3 albedo1(0.2f, 0.2f, 0.2f);
+	Material* pMatSphereGround = new Lambertian(new ConstantTexture(glm::vec3(0.25f, 0.25f, 0.25f)));
+	Sphere* pSphereGround = new Sphere(center1, 200.0f, pMatSphereGround);
+
+	CheckeredTexture* checksTexture = new CheckeredTexture(glm::vec3(0.2f, 0.9f, 0.5f), glm::vec3(0.03f), 10.0f, 10.0f);
+	glm::vec4 glassColor = glm::vec4(0.5, 1, 0.25, 1);
+
+	Sphere* pSphereGlass1 = new Sphere(glm::vec3(0.0f, 0.75f, 0.0f), 1.5f, new Transparent(new ConstantTexture(glassColor), 1.5f));
+	Sphere* pSphereMetal = new Sphere(glm::vec3(0.75f, 0.5f, -5.0f), 1.0f, new Metal(checksTexture, 0.1f));
+	
+	//Profiler::getInstance().WriteToProfiler("Triangle Count:", pMesh0->GetTriangleCount());
+
+	vecHitables.push_back(pSphereGround);
+	vecHitables.push_back(pSphereGlass1);
+	vecHitables.push_back(pSphereMetal);
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void Scene::InitTigerScene(float screenWidth, float screenHeight)
+{
+	// Initialize Camera first...!!!
+	glm::vec3 cameraPosition = glm::vec3(0.0f, 1.5f, 5.0f);
 	glm::vec3 cameraLookAt = glm::vec3(0.0f, 0.0f, 0.0f);
 	m_pCamera = new Camera();
 	m_pCamera->InitCamera(cameraPosition, cameraLookAt, screenWidth, screenHeight);
@@ -89,10 +155,10 @@ void Scene::InitScene(float screenWidth, float screenHeight)
 	baseInfo.filePath = "models/QuadBase.fbx";
 	baseInfo.isLightSource = false;
 	baseInfo.leafSize = 2;
-	baseInfo.position = glm::vec3(5.0f, -0.5f, 0.0f);
+	baseInfo.position = glm::vec3(0.0f, -0.5f, 0.0f);
 	baseInfo.rotationAxis = glm::vec3(0, 1, 0);
 	baseInfo.rotationAngle = 0.0f;
-	baseInfo.scale = glm::vec3(20.0f);
+	baseInfo.scale = glm::vec3(10.0f);
 	//lightInfo.matInfo.albedoColor = glm::vec4(glm::vec3(1.5f), 1);
 	TriangleMesh* pBase = new TriangleMesh(baseInfo);
 
@@ -105,7 +171,7 @@ void Scene::InitScene(float screenWidth, float screenHeight)
 	//vecHitables.push_back(pSphereLight);
 	vecHitables.push_back(pBase);
 	vecHitables.push_back(pLight);
-	vecHitables.push_back(pGlassTiger);
+	//vecHitables.push_back(pGlassTiger);
 }
 
 ///////////////////////////////////////////////////////////////////////////////////////////////////
@@ -265,6 +331,12 @@ void Scene::InitRandomScene(float screenWidth, float screenHeight)
 	vecHitables.push_back(pSphere3);
 }
 
+////////////////////////////////////////////////////////////////////////////////////////////////////
+glm::vec4 Scene::CalculateMissColor(glm::vec3 rayDirection)
+{
+	return glm::vec4(0.3f, 0.3f, 0.3f, 1.0f);
+}
+
 ///////////////////////////////////////////////////////////////////////////////////////////////////
 bool Scene::Trace(const Ray& r, int& rayCount, float tmin, float tmax, HitRecord& rec)
 {
diff --git a/RayTracer/Scene.h b/RayTracer/Scene.h
index 70233a1..a2dfdbc 100644
--- a/RayTracer/Scene.h
+++ b/RayTracer/Scene.h
@@ -13,13 +13,16 @@ public:
 
 	bool Trace(const Ray& r, int& rayCount, float tmin, float tmax, HitRecord& rec);
 
-	void InitScene(float screenWidth, float screenHeight);
+	void InitSphereScene(float screenWidth, float screenHeight);
+	void InitRefractionScene(float screenWidth, float screenHeight);
+	void InitTigerScene(float screenWidth, float screenHeight);
 	void InitCornellScene(float screenWidth, float screenHeight);
 	void InitTowerScene(float screenWidth, float screenHeight);
 	void InitRandomScene(float screenWidth, float screenHeight);
 
 	inline Camera* getCamera() { if(m_pCamera) return m_pCamera; }
-	inline glm::vec4 getMissColor() { return m_colMiss; }
+	
+	glm::vec4	CalculateMissColor(glm::vec3 rayDirection);
 
 private:	
 	glm::vec4			  m_colMiss;
diff --git a/RayTracer/Sphere.cpp b/RayTracer/Sphere.cpp
index f5b1770..4dd6f1d 100644
--- a/RayTracer/Sphere.cpp
+++ b/RayTracer/Sphere.cpp
@@ -6,8 +6,8 @@
 ///////////////////////////////////////////////////////////////////////////////////////////////////
 bool Sphere::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
 {
-	glm::vec3 rayDirection = r.GetRayDirection();
-	glm::vec3 rayOrigin = r.GetRayOrigin();
+	glm::vec3 rayDirection = r.direction;
+	glm::vec3 rayOrigin = r.origin;
 
 	glm::vec3 oc = rayOrigin - center;
 	float a = glm::dot(rayDirection, rayDirection);
diff --git a/RayTracer/Texture.cpp b/RayTracer/Texture.cpp
index 46f9c15..b5a5d87 100644
--- a/RayTracer/Texture.cpp
+++ b/RayTracer/Texture.cpp
@@ -1,15 +1,18 @@
 
 #define STB_IMAGE_IMPLEMENTATION
 #include "stb_image.h"
-
 #include "Texture.h"
 
+#include <iostream>
+
+////////////////////////////////////////////////////////////////////////////////////////////////////
 ImageTexture::ImageTexture(const std::string & _path)
 {
 	path = _path;
 	LoadImage();
 }
 
+////////////////////////////////////////////////////////////////////////////////////////////////////
 glm::vec3 ImageTexture::value(glm::vec2 uv) const
 {
 	// Images with alpha channels not supported yet!
@@ -31,7 +34,46 @@ glm::vec3 ImageTexture::value(glm::vec2 uv) const
 	return glm::vec3(r, g, b);
 }
 
+////////////////////////////////////////////////////////////////////////////////////////////////////
 void ImageTexture::LoadImage()
 {
 	data = stbi_load(path.c_str(), &width, &height, &channels, 0);
 }
+
+////////////////////////////////////////////////////////////////////////////////////////////////////
+HDRITexture::HDRITexture()
+{
+	data = nullptr;
+}
+
+////////////////////////////////////////////////////////////////////////////////////////////////////
+HDRITexture::HDRITexture(const std::string& _path)
+{
+	path = _path;
+	data = nullptr;
+}
+
+////////////////////////////////////////////////////////////////////////////////////////////////////
+void HDRITexture::LoadImage()
+{
+	if (stbi_is_hdr(path.c_str()))
+	{
+		stbi_set_flip_vertically_on_load(1);
+		data = stbi_loadf(path.c_str(), &width, &height, &channels, 0);
+
+		if (!data)
+		{
+			std::cout << "Error loading HDRI image data!" << std::endl;
+		}
+	}
+	else
+	{
+		std::cout << "Image not HDRI!" << std::endl;
+	}
+}
+
+////////////////////////////////////////////////////////////////////////////////////////////////////
+glm::vec3 HDRITexture::value(glm::vec2 uv) const
+{
+	return glm::vec3(1, 1, 1);
+}
diff --git a/RayTracer/Texture.h b/RayTracer/Texture.h
index 6039f64..f3c0b19 100644
--- a/RayTracer/Texture.h
+++ b/RayTracer/Texture.h
@@ -53,11 +53,30 @@ private:
 	float valY;
 };
 
+////////////////////////////////////////////////////////////////////////////////////////////////////
+class HDRITexture : public Texture
+{
+public:
+	HDRITexture();
+	HDRITexture(const std::string& _path);
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
+	float* data;
+};
+
 ///////////////////////////////////////////////////////////////////////////////////////////////////
 class ImageTexture : public Texture
 {
 public:
-	ImageTexture() {}
+	ImageTexture() { data = nullptr; }
 	ImageTexture(const std::string& _path);
 
 	virtual glm::vec3 value(glm::vec2 uv) const;
diff --git a/RayTracer/Transparent.h b/RayTracer/Transparent.h
index c5df03d..f2f3a24 100644
--- a/RayTracer/Transparent.h
+++ b/RayTracer/Transparent.h
@@ -13,7 +13,7 @@ public:
 	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, int& rayCount, glm::vec3& attenuation, Ray& scattered) const
 	{
 		glm::vec3 outward_normal;
-		glm::vec3 ray_direction = r_in.GetRayDirection();
+		glm::vec3 ray_direction = r_in.direction;
 		
 		glm::vec3 reflected = Helper::Reflect(ray_direction, rec.N);
 		float ni_over_nt;
@@ -23,12 +23,16 @@ public:
 		float reflect_prob;
 		float cosine;
 
+		// When ray shoots through object back into vacuum,
+		// ni_over_nt = refr_idx, surface normal has to be inverted!
 		if (glm::dot(ray_direction, rec.N) > 0)
 		{
-			outward_normal = -rec.N;  // because we want inverted image for refraction? 
+			outward_normal = -rec.N;  
 			ni_over_nt = refr_index;
 			cosine = refr_index * glm::dot(ray_direction, rec.N) / glm::length(ray_direction);
 		}
+		// When ray shoots into the object, 
+		// ni_over_nt = 1 / refr_idx
 		else
 		{
 			outward_normal = rec.N;
@@ -46,6 +50,14 @@ public:
 		}
 
 		// this logic is not clear? 
+		// Both reflection and refraction of the light occur for dielectric material, but we can only 
+		// pick 1 scattered ray for next iteration of ray tracing. Since we are shooting multiple rays 
+		// per pixel (multi-sampling) and average the traced color as final pixel color, we can use the 
+		// same idea to get the averaged result through both reflectiona and refraction.
+
+		// Now we generate a random number between 0.0 and 1.0. If it�s smaller than reflective coefficient, 
+		// the scattered ray is recorded as reflected; If it�s bigger than reflective coefficient, 
+		// the scattered ray is recorded as refracted.
 		if (Helper::GetRandom01() < reflect_prob)
 		{
 			scattered = Ray(rec.P, reflected);
diff --git a/RayTracer/Triangle.cpp b/RayTracer/Triangle.cpp
index 32d75dc..05e32e0 100644
--- a/RayTracer/Triangle.cpp
+++ b/RayTracer/Triangle.cpp
@@ -42,8 +42,8 @@ bool Triangle::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
 {
 	++rec.rayTriangleQuery;
 
-	glm::vec3 rayDirection = r.GetRayDirection();
-	glm::vec3 rayOrigin = r.GetRayOrigin();
+	glm::vec3 rayDirection = r.direction;
+	glm::vec3 rayOrigin = r.origin;
 
 	// Compute Plane Normal
 	glm::vec3 edge0 = v1.position - v0.position;
```

