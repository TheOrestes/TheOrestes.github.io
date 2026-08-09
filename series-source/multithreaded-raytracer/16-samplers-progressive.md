# Post 16 — Samplers and progressive rendering

## `ffc606d` — 2020-01-16 _(master)_

> Added Samplers

```diff
diff --git a/Application.cpp b/Application.cpp
index 8deddc8..e0c5779 100644
--- a/Application.cpp
+++ b/Application.cpp
@@ -9,6 +9,7 @@
 #include "RayTracer/Material.h"
 #include "RayTracer/Scene.h"
 #include "RayTracer/Camera.h"
+#include "RayTracer/Sampler.h"
 #include "RayTracer/Helper.h"
 #include "Profiler.h"
 #include "Application.h"
@@ -34,6 +35,7 @@ Application::Application()
 	m_iTriangleCount = 0;
 
 	m_hWnd = NULL;
+	m_pSampler = nullptr;
 }
 
 ///////////////////////////////////////////////////////////////////////////////////////////////////
@@ -44,6 +46,12 @@ Application::~Application()
 		delete m_pScene;
 		m_pScene = nullptr;
 	}
+
+	if (m_pSampler)
+	{
+		delete m_pSampler;
+		m_pSampler = nullptr;
+	}
 }
 
 ///////////////////////////////////////////////////////////////////////////////////////////////////
@@ -60,6 +68,10 @@ void Application::Initialize(HWND hwnd, bool _threaded)
 	//m_pScene->InitCornellScene(m_iBackbufferWidth, m_iBackbufferHeight);
 	//m_pScene->InitTowerScene(m_iBackbufferWidth, m_iBackbufferHeight);
 
+	// Initialize Sampler
+	m_pSampler = new JitteredSampler();
+	m_pSampler->GenerateSamples(m_iNumSamples);
+
 	// Create Open Image Denoise Device
 	m_oidnDevice = oidn::newDevice();
 	m_oidnDevice.set("numThreads", m_iMaxThreads);
@@ -272,6 +284,8 @@ void Application::ParallelTrace(std::mutex * threadMutex, int i)
 
 	threadMutex->unlock();
 
+	std::vector<glm::vec2> samples = m_pSampler->GetSamples();
+
 	// Error check for bounds!
 	if (startWidth < endWidth && startHeight < endHeight)
 	{
@@ -283,8 +297,8 @@ void Application::ParallelTrace(std::mutex * threadMutex, int i)
 
 				for (int s = 0; s < ns; s++)
 				{
-					float u = float(i + Helper::GetRandom01());// / float(backBufferWidth);
-					float v = float(j + Helper::GetRandom01());// / float(backBufferHeight);
+					float u = float(i + samples[s].x);
+					float v = float(j + samples[s].y);
 
 					Ray r = m_pScene->getCamera()->get_ray(u, v);
 
@@ -339,6 +353,7 @@ void Application::Trace()
 		HDC hdc = GetDC(m_hWnd);
 
 		int rayCount = 0;
+		std::vector<glm::vec2> samples = m_pSampler->GetSamples();
 
 		for (int j = m_iBackbufferHeight; j >= 0; j--)
 		{
@@ -348,8 +363,8 @@ void Application::Trace()
 
 				for (int s = 0; s < m_iNumSamples; s++)
 				{
-					float u = float(i + Helper::GetRandom01());// / float(m_iBackbufferWidth);
-					float v = float(j + Helper::GetRandom01());// / float(m_iBackbufferHeight);
+					float u = float(i + samples[s].x);// / float(m_iBackbufferWidth);
+					float v = float(j + samples[s].y);// / float(m_iBackbufferHeight);
 
 					Ray r = m_pScene->getCamera()->get_ray(u, v);
 
diff --git a/Application.h b/Application.h
index c31a5c3..8d98f49 100644
--- a/Application.h
+++ b/Application.h
@@ -9,6 +9,7 @@
 
 class Ray;
 class Scene;
+class Sampler;
 
 class Application
 {
@@ -31,9 +32,9 @@ private:
 	void			ParallelTrace(std::mutex* threadMutex, int i);
 	void			Trace();
 
-	int				m_iBackbufferWidth;
-	int				m_iBackbufferHeight;
-	int				m_iNumSamples;
+	uint32_t		m_iBackbufferWidth;
+	uint32_t		m_iBackbufferHeight;
+	uint32_t		m_iNumSamples;
 	int				m_iMaxThreads;
 	float			m_dTotalRenderTime;
 	float			m_dDenoiserTime;
@@ -48,6 +49,7 @@ private:
 
 	HWND			m_hWnd;
 	Scene*			m_pScene;
+	Sampler*		m_pSampler;
 
 	oidn::DeviceRef	m_oidnDevice;
 	oidn::FilterRef m_oidnFilter;
diff --git a/RayTracer/Sampler.cpp b/RayTracer/Sampler.cpp
new file mode 100644
index 0000000..4509dbc
--- /dev/null
+++ b/RayTracer/Sampler.cpp
@@ -0,0 +1,184 @@
+
+#include "Sampler.h"
+#include "Helper.h"
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+Sampler::Sampler()
+{
+	m_vecSamples.clear();
+	m_vecDiskSamples.clear();
+	m_vecHemisphereSamples.clear();
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void Sampler::MapSamplesToDisk()
+{
+	float r, phi;						// polar coordinates
+	glm::vec2 sample = glm::vec2(0,0);	// sample point on unit disk
+
+	uint32_t size = m_vecSamples.size();
+
+	m_vecDiskSamples.reserve(size);
+
+	for (int i = 0; i < size; ++i)
+	{
+		// map sample point to [-1,1]
+
+		sample.x = 2.0f * m_vecSamples[i].x - 1.0f;
+		sample.y = 2.0f * m_vecSamples[i].y - 1.0f;
+
+		if (sample.x > -sample.y)
+		{
+			// sector 1 & 2
+			if (sample.x > sample.y)
+			{
+				// sector 1
+				r = sample.x;
+				phi = sample.y / sample.x;
+			}
+			else
+			{
+				// sector 2
+				r = sample.y;
+				phi = 2.0f - (sample.x / sample.y);
+			}
+		}
+		else
+		{
+			// sector 3 & 4
+			if (sample.x < sample.y)
+			{
+				// sector 3
+				r = -sample.x;
+				phi = 4 + (sample.y / sample.x);
+			}
+			else
+			{
+				// sector 4
+				r = -sample.y;
+				if (sample.y != 0.0f)
+				{
+					phi = 6 - (sample.x / sample.y);
+				}
+				else
+				{
+					phi = 0.0f;
+				}
+			}
+		}
+
+		phi *= PI / 4.0f;
+
+		m_vecDiskSamples[i].x = r * cos(phi);
+		m_vecDiskSamples[i].y = r * sin(phi);
+	}
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void Sampler::MapSamplesToHemisphere(const float e)
+{
+	uint32_t size = m_vecSamples.size();
+	m_vecHemisphereSamples.reserve(size);
+
+	for (int i = 0; i < size; ++i)
+	{
+		float cos_phi = cos(2.0f * PI * m_vecSamples[i].x);
+		float sin_phi = sin(2.0f * PI * m_vecSamples[i].x);
+
+		float cos_theta = pow((1.0f - m_vecSamples[i].y), 1.0f / (e + 1.0f));
+		float sin_theta = sqrt(1.0f - cos_theta * cos_theta);
+
+		float pu = sin_theta * cos_phi;
+		float pv = sin_theta * sin_phi;
+		float pw = cos_theta;
+
+		m_vecHemisphereSamples.push_back(glm::vec3(pu, pv, pw));
+	}
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void RandomSampler::GenerateSamples(uint32_t _numSamples)
+{
+	m_strName = "RandomSampler";
+	m_uiNumSamples = _numSamples;
+	m_vecSamples.reserve(m_uiNumSamples);
+
+	for (uint32_t i = 0; i < m_uiNumSamples; ++i)
+	{
+		glm::vec2 sample = glm::vec2(Helper::GetRandom01(), Helper::GetRandom01());
+		m_vecSamples.push_back(sample);
+	}
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void RegularSampler::GenerateSamples(uint32_t _numSamples)
+{
+	m_strName = "RegularSampler";
+	m_uiNumSamples = _numSamples;
+	m_vecSamples.reserve(m_uiNumSamples);
+
+	uint32_t numSets;				// horizontal or vertical sections
+	uint32_t numGrids;				// total number of grids in a pixel
+	uint32_t numSamplesPerGrid;		// per grid samples!
+
+	// derive number of sets based on sample count to avoid zero samples per grid!
+	numSets = (m_uiNumSamples < 4) ? 1 : sqrt(m_uiNumSamples);
+	
+	numGrids = numSets * numSets;
+	numSamplesPerGrid = m_uiNumSamples / numGrids;
+	
+	for (uint32_t i = 0; i < numSets; ++i)
+	{
+		for (uint32_t j = 0; j < numSets; ++j)
+		{
+			for (uint32_t k = 0; k < numSamplesPerGrid; ++k)
+			{
+				// This loop doesn't really matter since in Regular
+				// sampling, all the points will lie on same location!
+				// However, I have addded it to keep in sync with logic 
+				// in Jittered sampler!
+				float x = (i + 0.5f) / numSets;
+				float y = (j + 0.5f) / numSets;
+				glm::vec2 sample = glm::vec2(x, y);
+				m_vecSamples.push_back(sample);
+			}
+		}
+	}
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void JitteredSampler::GenerateSamples(uint32_t _numSamples)
+{
+	m_strName = "JitteredSampler";
+	m_uiNumSamples = _numSamples;
+	m_vecSamples.reserve(m_uiNumSamples);
+
+	uint32_t numSets;				// horizontal or vertical sections
+	uint32_t numGrids;				// total number of grids in a pixel
+	uint32_t numSamplesPerGrid;		// per grid samples!
+
+	// derive number of sets based on sample count to avoid zero samples per grid!
+	numSets = (m_uiNumSamples < 4) ? 1 : sqrt(m_uiNumSamples);
+
+	numGrids = numSets * numSets;
+	numSamplesPerGrid = m_uiNumSamples / numGrids;
+
+	for (uint32_t i = 0; i < numSets; ++i)
+	{
+		for (uint32_t j = 0; j < numSets; ++j)
+		{
+			for (uint32_t k = 0; k < numSamplesPerGrid; ++k)
+			{
+				// This loop doesn't really matter since in Regular
+				// sampling, all the points will lie on same location!
+				// However, I have addded it to keep in sync with logic 
+				// in Jittered sampler!
+				float x = (i + Helper::GetRandom01()) / numSets;
+				float y = (j + Helper::GetRandom01()) / numSets;
+				glm::vec2 sample = glm::vec2(x, y);
+				m_vecSamples.push_back(sample);
+			}
+		}
+	}
+}
+
diff --git a/RayTracer/Sampler.h b/RayTracer/Sampler.h
new file mode 100644
index 0000000..206955d
--- /dev/null
+++ b/RayTracer/Sampler.h
@@ -0,0 +1,63 @@
+#pragma once
+
+#include <vector>
+#include <string>
+#include "glm/glm.hpp"
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+class Sampler
+{
+public:
+	Sampler(); 
+	virtual ~Sampler() {};
+
+	// pure virtual function to be implemented by derived class!
+	virtual void					GenerateSamples(uint32_t _numSamples) = 0;
+
+	virtual void					MapSamplesToDisk();
+	virtual void					MapSamplesToHemisphere(const float e);
+
+	virtual std::vector<glm::vec2>  GetSamples()			{ return m_vecSamples; };
+	virtual std::vector<glm::vec2>	GetDiskSamples()		{ return m_vecDiskSamples; }
+	virtual std::vector<glm::vec3>	GetHemisphereSamples()	{ return m_vecHemisphereSamples; }
+	virtual std::string				GetName()				{ return m_strName; }
+
+protected:
+	uint32_t						m_uiNumSamples;
+	std::vector<glm::vec2>			m_vecSamples;
+	std::vector<glm::vec2>			m_vecDiskSamples;
+	std::vector<glm::vec3>			m_vecHemisphereSamples;
+	std::string						m_strName;
+};
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+class RandomSampler : public Sampler
+{
+public:
+	RandomSampler() {};
+	~RandomSampler() {};
+
+	virtual void					GenerateSamples(uint32_t _numSamples);
+};
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+class RegularSampler : public Sampler
+{
+public:
+	RegularSampler() {};
+	~RegularSampler() {};
+
+	virtual void					GenerateSamples(uint32_t _numSamples);
+};
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+class JitteredSampler : public Sampler
+{
+public:
+	JitteredSampler() {};
+	~JitteredSampler() {};
+
+	virtual void					GenerateSamples(uint32_t _numSamples);
+};
+
+
```

## `f8aea40` — 2020-01-15 _(OpenGL branch)_

> Added Samplers & Disk Samples, Hemisphere samples.

```diff
diff --git a/.gitignore b/.gitignore
index 01cfceb..2fd79ba 100644
--- a/.gitignore
+++ b/.gitignore
@@ -37,4 +37,6 @@
 *.app
 *.ppm
 *.bmp
+*.hdr
+*.dat
 /models
diff --git a/Main/Application.cpp b/Main/Application.cpp
index 0b3726b..cf80db9 100644
--- a/Main/Application.cpp
+++ b/Main/Application.cpp
@@ -13,6 +13,7 @@
 #include "../RayTracer/Helper.h"
 #include "../RayTracer/Camera.h"
 #include "..//RayTracer/Scene.h"
+#include "../RayTracer/Sampler.h"
 #include "Profiler.h"
 #include "ScreenAlignedQuad.h"
 #include "Application.h"
@@ -31,9 +32,9 @@
 ///////////////////////////////////////////////////////////////////////////////////////////////////
 Application::Application()
 {
-	m_iBackbufferWidth = 1000;
+	m_iBackbufferWidth = 500;
 	m_iBackbufferHeight = 500;
-	m_iNumSamples = 50;
+	m_iNumSamples = 100;
 	m_dTotalRenderTime = 0;
 	m_dDenoiserTime = 0;
 	m_bThreaded = false;
@@ -46,6 +47,7 @@ Application::Application()
 	m_iTriangleCount = 0;
 
 	m_pQuad = nullptr;
+	m_pSampler = nullptr;
 }
 
 ///////////////////////////////////////////////////////////////////////////////////////////////////
@@ -56,6 +58,12 @@ Application::~Application()
 		delete m_pScene;
 		m_pScene = nullptr;
 	}
+
+	if (m_pSampler)
+	{
+		delete m_pSampler;
+		m_pSampler = nullptr;
+	}
 }
 
 ///////////////////////////////////////////////////////////////////////////////////////////////////
@@ -67,14 +75,18 @@ void Application::Initialize(bool _threaded)
 
 	m_pScene = new Scene();
 	//m_pScene->InitRefractionScene(m_iBackbufferWidth, m_iBackbufferHeight);
-	//m_pScene->InitSphereScene(m_iBackbufferWidth, m_iBackbufferHeight);
+	m_pScene->InitSphereScene(m_iBackbufferWidth, m_iBackbufferHeight);
 	//m_pScene->InitCornellScene(m_iBackbufferWidth, m_iBackbufferHeight);
-	m_pScene->InitTigerScene(m_iBackbufferWidth, m_iBackbufferHeight);
+	//m_pScene->InitTigerScene(m_iBackbufferWidth, m_iBackbufferHeight);
 	//m_pScene->InitTowerScene(m_iBackbufferWidth, m_iBackbufferHeight);
 
 	m_pQuad = new ScreenAlignedQuad();
 	m_pQuad->Init(m_iBackbufferWidth, m_iBackbufferHeight);
 
+	// Initialize Sampler
+	m_pSampler = new JitteredSampler();
+	m_pSampler->GenerateSamples(m_iNumSamples);
+
 	glm::vec3 col = glm::vec3(0, 0, 0);
 	for (int i = 0; i < m_iBackbufferWidth * m_iBackbufferHeight; i++)
 	{
@@ -115,7 +127,15 @@ void Application::Execute(GLFWwindow* window)
 ///////////////////////////////////////////////////////////////////////////////////////////////////
 void Application::SaveImage()
 {
-	static int count = 0;
+	std::string fileName = m_pSampler->GetName() + std::to_string(m_iBackbufferWidth)
+												 + "x" 
+												 + std::to_string(m_iBackbufferHeight) 
+												 + "_samples_"
+												 + std::to_string(m_iNumSamples) 
+												 + ".hdr";
+
+	stbi_flip_vertically_on_write(1);
+	stbi_write_hdr(fileName.c_str(), m_iBackbufferWidth, m_iBackbufferHeight, 3, glm::value_ptr(m_vecDstPixels[0]));
 
 	//BITMAPINFO info;
 	//BITMAPFILEHEADER header;
@@ -300,6 +320,8 @@ void Application::ParallelTrace(std::mutex * threadMutex, int i, GLFWwindow* win
 
 	//threadMutex->unlock();
 
+	std::vector<glm::vec2> samples = m_pSampler->GetSamples();
+
 	// Error check for bounds!
 	if (startWidth < endWidth && startHeight < endHeight)
 	{
@@ -311,8 +333,8 @@ void Application::ParallelTrace(std::mutex * threadMutex, int i, GLFWwindow* win
 
 				for (int s = 0; s < ns; s++)
 				{
-					float u = float(i + Helper::GetRandom01());// / float(backBufferWidth);
-					float v = float(j + Helper::GetRandom01());// / float(backBufferHeight);
+					float u = float(i + samples[s].x); 
+					float v = float(j + samples[s].y); 
 
 					Ray r = m_pScene->getCamera()->get_ray(u, v);
 
@@ -365,14 +387,14 @@ void Application::UpdateGL(GLFWwindow* window)
 	while (!glfwWindowShouldClose(window))
 	{
 		m_vecDstPixels = m_vecSrcPixels;
-
+	
 		glfwPollEvents();
 		glClearColor(1.0f, 1.0f, 1.0f, 1.0f);
 		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
-
+	
 		m_pQuad->UpdateTexture(0, 0, m_iBackbufferWidth, m_iBackbufferHeight, glm::value_ptr(m_vecDstPixels[0]));
 		m_pQuad->Render();
-
+	
 		glfwSwapBuffers(window);
 	}
 }
@@ -386,6 +408,7 @@ void Application::Trace(GLFWwindow* window)
 #if defined _DEBUG
 
 	int rayCount = 0;
+	std::vector<glm::vec2> samples = m_pSampler->GetSamples();
 
 	for (int j = 0; j < m_iBackbufferHeight; j++)
 	{
@@ -396,8 +419,8 @@ void Application::Trace(GLFWwindow* window)
 
 			for (int s = 0; s < m_iNumSamples; s++)
 			{
-				float u = float(i + Helper::GetRandom01());// / float(m_iBackbufferWidth);
-				float v = float(j + Helper::GetRandom01());// / float(m_iBackbufferHeight);
+				float u = float(i + samples[s].x);
+				float v = float(j + samples[s].y);
 
 				Ray r = m_pScene->getCamera()->get_ray(u, v);
 
@@ -407,8 +430,7 @@ void Application::Trace(GLFWwindow* window)
 			color = color / float(m_iNumSamples);
 			color = glm::vec3(sqrt(color.x), sqrt(color.y), sqrt(color.z));
 
-			//m_vecSrcPixels[j * gBackbufferWidth + i] = color;
-
+			m_vecSrcPixels[j * m_iBackbufferWidth + i] = color;
 			rowColor.push_back(color);
 		}
 
diff --git a/Main/Application.h b/Main/Application.h
index c9ef4cc..77f2e0d 100644
--- a/Main/Application.h
+++ b/Main/Application.h
@@ -11,6 +11,7 @@
 class Ray;
 class ScreenAlignedQuad;
 class Scene;
+class Sampler;
 
 class Application
 {
@@ -53,6 +54,7 @@ private:
 
 	ScreenAlignedQuad*	m_pQuad;
 	Scene*				m_pScene;
+	Sampler*			m_pSampler;
 
 	std::vector<glm::vec3>  m_vecSrcPixels;
 	std::vector<glm::vec3>	m_vecDstPixels;
diff --git a/Main/Main.cpp b/Main/Main.cpp
index 4e8265a..e4f09d4 100644
--- a/Main/Main.cpp
+++ b/Main/Main.cpp
@@ -88,6 +88,8 @@ int main()
 	pApp->Execute(window);
 	pApp->UpdateGL(window);
 
+	pApp->SaveImage();
+
 	glfwTerminate();
 
 	delete pApp;
diff --git a/RayTracer/Sampler.cpp b/RayTracer/Sampler.cpp
new file mode 100644
index 0000000..4509dbc
--- /dev/null
+++ b/RayTracer/Sampler.cpp
@@ -0,0 +1,184 @@
+
+#include "Sampler.h"
+#include "Helper.h"
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+Sampler::Sampler()
+{
+	m_vecSamples.clear();
+	m_vecDiskSamples.clear();
+	m_vecHemisphereSamples.clear();
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void Sampler::MapSamplesToDisk()
+{
+	float r, phi;						// polar coordinates
+	glm::vec2 sample = glm::vec2(0,0);	// sample point on unit disk
+
+	uint32_t size = m_vecSamples.size();
+
+	m_vecDiskSamples.reserve(size);
+
+	for (int i = 0; i < size; ++i)
+	{
+		// map sample point to [-1,1]
+
+		sample.x = 2.0f * m_vecSamples[i].x - 1.0f;
+		sample.y = 2.0f * m_vecSamples[i].y - 1.0f;
+
+		if (sample.x > -sample.y)
+		{
+			// sector 1 & 2
+			if (sample.x > sample.y)
+			{
+				// sector 1
+				r = sample.x;
+				phi = sample.y / sample.x;
+			}
+			else
+			{
+				// sector 2
+				r = sample.y;
+				phi = 2.0f - (sample.x / sample.y);
+			}
+		}
+		else
+		{
+			// sector 3 & 4
+			if (sample.x < sample.y)
+			{
+				// sector 3
+				r = -sample.x;
+				phi = 4 + (sample.y / sample.x);
+			}
+			else
+			{
+				// sector 4
+				r = -sample.y;
+				if (sample.y != 0.0f)
+				{
+					phi = 6 - (sample.x / sample.y);
+				}
+				else
+				{
+					phi = 0.0f;
+				}
+			}
+		}
+
+		phi *= PI / 4.0f;
+
+		m_vecDiskSamples[i].x = r * cos(phi);
+		m_vecDiskSamples[i].y = r * sin(phi);
+	}
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void Sampler::MapSamplesToHemisphere(const float e)
+{
+	uint32_t size = m_vecSamples.size();
+	m_vecHemisphereSamples.reserve(size);
+
+	for (int i = 0; i < size; ++i)
+	{
+		float cos_phi = cos(2.0f * PI * m_vecSamples[i].x);
+		float sin_phi = sin(2.0f * PI * m_vecSamples[i].x);
+
+		float cos_theta = pow((1.0f - m_vecSamples[i].y), 1.0f / (e + 1.0f));
+		float sin_theta = sqrt(1.0f - cos_theta * cos_theta);
+
+		float pu = sin_theta * cos_phi;
+		float pv = sin_theta * sin_phi;
+		float pw = cos_theta;
+
+		m_vecHemisphereSamples.push_back(glm::vec3(pu, pv, pw));
+	}
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void RandomSampler::GenerateSamples(uint32_t _numSamples)
+{
+	m_strName = "RandomSampler";
+	m_uiNumSamples = _numSamples;
+	m_vecSamples.reserve(m_uiNumSamples);
+
+	for (uint32_t i = 0; i < m_uiNumSamples; ++i)
+	{
+		glm::vec2 sample = glm::vec2(Helper::GetRandom01(), Helper::GetRandom01());
+		m_vecSamples.push_back(sample);
+	}
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void RegularSampler::GenerateSamples(uint32_t _numSamples)
+{
+	m_strName = "RegularSampler";
+	m_uiNumSamples = _numSamples;
+	m_vecSamples.reserve(m_uiNumSamples);
+
+	uint32_t numSets;				// horizontal or vertical sections
+	uint32_t numGrids;				// total number of grids in a pixel
+	uint32_t numSamplesPerGrid;		// per grid samples!
+
+	// derive number of sets based on sample count to avoid zero samples per grid!
+	numSets = (m_uiNumSamples < 4) ? 1 : sqrt(m_uiNumSamples);
+	
+	numGrids = numSets * numSets;
+	numSamplesPerGrid = m_uiNumSamples / numGrids;
+	
+	for (uint32_t i = 0; i < numSets; ++i)
+	{
+		for (uint32_t j = 0; j < numSets; ++j)
+		{
+			for (uint32_t k = 0; k < numSamplesPerGrid; ++k)
+			{
+				// This loop doesn't really matter since in Regular
+				// sampling, all the points will lie on same location!
+				// However, I have addded it to keep in sync with logic 
+				// in Jittered sampler!
+				float x = (i + 0.5f) / numSets;
+				float y = (j + 0.5f) / numSets;
+				glm::vec2 sample = glm::vec2(x, y);
+				m_vecSamples.push_back(sample);
+			}
+		}
+	}
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void JitteredSampler::GenerateSamples(uint32_t _numSamples)
+{
+	m_strName = "JitteredSampler";
+	m_uiNumSamples = _numSamples;
+	m_vecSamples.reserve(m_uiNumSamples);
+
+	uint32_t numSets;				// horizontal or vertical sections
+	uint32_t numGrids;				// total number of grids in a pixel
+	uint32_t numSamplesPerGrid;		// per grid samples!
+
+	// derive number of sets based on sample count to avoid zero samples per grid!
+	numSets = (m_uiNumSamples < 4) ? 1 : sqrt(m_uiNumSamples);
+
+	numGrids = numSets * numSets;
+	numSamplesPerGrid = m_uiNumSamples / numGrids;
+
+	for (uint32_t i = 0; i < numSets; ++i)
+	{
+		for (uint32_t j = 0; j < numSets; ++j)
+		{
+			for (uint32_t k = 0; k < numSamplesPerGrid; ++k)
+			{
+				// This loop doesn't really matter since in Regular
+				// sampling, all the points will lie on same location!
+				// However, I have addded it to keep in sync with logic 
+				// in Jittered sampler!
+				float x = (i + Helper::GetRandom01()) / numSets;
+				float y = (j + Helper::GetRandom01()) / numSets;
+				glm::vec2 sample = glm::vec2(x, y);
+				m_vecSamples.push_back(sample);
+			}
+		}
+	}
+}
+
diff --git a/RayTracer/Sampler.h b/RayTracer/Sampler.h
new file mode 100644
index 0000000..206955d
--- /dev/null
+++ b/RayTracer/Sampler.h
@@ -0,0 +1,63 @@
+#pragma once
+
+#include <vector>
+#include <string>
+#include "glm/glm.hpp"
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+class Sampler
+{
+public:
+	Sampler(); 
+	virtual ~Sampler() {};
+
+	// pure virtual function to be implemented by derived class!
+	virtual void					GenerateSamples(uint32_t _numSamples) = 0;
+
+	virtual void					MapSamplesToDisk();
+	virtual void					MapSamplesToHemisphere(const float e);
+
+	virtual std::vector<glm::vec2>  GetSamples()			{ return m_vecSamples; };
+	virtual std::vector<glm::vec2>	GetDiskSamples()		{ return m_vecDiskSamples; }
+	virtual std::vector<glm::vec3>	GetHemisphereSamples()	{ return m_vecHemisphereSamples; }
+	virtual std::string				GetName()				{ return m_strName; }
+
+protected:
+	uint32_t						m_uiNumSamples;
+	std::vector<glm::vec2>			m_vecSamples;
+	std::vector<glm::vec2>			m_vecDiskSamples;
+	std::vector<glm::vec3>			m_vecHemisphereSamples;
+	std::string						m_strName;
+};
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+class RandomSampler : public Sampler
+{
+public:
+	RandomSampler() {};
+	~RandomSampler() {};
+
+	virtual void					GenerateSamples(uint32_t _numSamples);
+};
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+class RegularSampler : public Sampler
+{
+public:
+	RegularSampler() {};
+	~RegularSampler() {};
+
+	virtual void					GenerateSamples(uint32_t _numSamples);
+};
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+class JitteredSampler : public Sampler
+{
+public:
+	JitteredSampler() {};
+	~JitteredSampler() {};
+
+	virtual void					GenerateSamples(uint32_t _numSamples);
+};
+
+
diff --git a/RayTracer/Scene.cpp b/RayTracer/Scene.cpp
index 0022bf9..f07444a 100644
--- a/RayTracer/Scene.cpp
+++ b/RayTracer/Scene.cpp
@@ -138,7 +138,7 @@ void Scene::InitTigerScene(float screenWidth, float screenHeight)
 	glassTigerInfo.scale = glm::vec3(0.75f);
 	glassTigerInfo.matInfo.albedoColor = glm::vec4(0.3f, 0.8f, 1.0f, 1);
 	glassTigerInfo.matInfo.refrIndex = 1.4f;
-	TriangleMesh* pGlassTiger = new TriangleMesh(glassTigerInfo);
+	//TriangleMesh* pGlassTiger = new TriangleMesh(glassTigerInfo);
 
 	// Light Quad
 	MeshInfo lightInfo;
@@ -178,7 +178,7 @@ void Scene::InitTigerScene(float screenWidth, float screenHeight)
 void Scene::InitCornellScene(float screenWidth, float screenHeight)
 {
 	// Initialize Camera first...!!!
-	glm::vec3 cameraPosition = glm::vec3(0.0f, 2.5f, 8.5f);
+	glm::vec3 cameraPosition = glm::vec3(0.0f, 2.5f, 6.5f);
 	glm::vec3 cameraLookAt = glm::vec3(0.0f, 2.5f, 0.0f);
 	m_pCamera = new Camera();
 	m_pCamera->InitCamera(cameraPosition, cameraLookAt, screenWidth, screenHeight);
@@ -220,22 +220,22 @@ void Scene::InitCornellScene(float screenWidth, float screenHeight)
 	TriangleMesh* pLight = new TriangleMesh(lightInfo);
 
 	// Glass Mesh
-	MeshInfo glassTigerInfo;
-	glassTigerInfo.filePath = "models/tigerTransparent.fbx";
-	glassTigerInfo.leafSize = 512;
-	glassTigerInfo.position = glm::vec3(-2.0f, 0.0f, 1.0f);
-	glassTigerInfo.rotationAxis = glm::vec3(0, 1, 0);
-	glassTigerInfo.rotationAngle = -45.0f;
-	glassTigerInfo.scale = glm::vec3(0.5f);
-	glassTigerInfo.matInfo.albedoColor = glm::vec4(1.0f, 1.0f, 0, 1);
-	glassTigerInfo.matInfo.refrIndex = 1.4f;
-	TriangleMesh* pGlassTiger = new TriangleMesh(glassTigerInfo);
+	//MeshInfo glassTigerInfo;
+	//glassTigerInfo.filePath = "models/tigerTransparent.fbx";
+	//glassTigerInfo.leafSize = 512;
+	//glassTigerInfo.position = glm::vec3(-2.0f, 0.0f, 1.0f);
+	//glassTigerInfo.rotationAxis = glm::vec3(0, 1, 0);
+	//glassTigerInfo.rotationAngle = -45.0f;
+	//glassTigerInfo.scale = glm::vec3(0.5f);
+	//glassTigerInfo.matInfo.albedoColor = glm::vec4(1.0f, 1.0f, 0, 1);
+	//glassTigerInfo.matInfo.refrIndex = 1.4f;
+	//TriangleMesh* pGlassTiger = new TriangleMesh(glassTigerInfo);
 
 	vecHitables.push_back(pLight);
 	vecHitables.push_back(pRoom);
 	vecHitables.push_back(pLeftCube);
 	vecHitables.push_back(pSphereGlass);
-	vecHitables.push_back(pGlassTiger);
+	//vecHitables.push_back(pGlassTiger);
 
 	Profiler::getInstance().WriteToProfiler("Triangle Count:", pRoom->GetTriangleCount() + pLight->GetTriangleCount() + pLeftCube->GetTriangleCount());
 }
```

## `93d09c4` — 2020-04-26 _(OpenGL branch)_

> Added Progressive rendering for raytracer based on sample count!

```diff
diff --git a/Main/Application.cpp b/Main/Application.cpp
index 45fb0e1..74b392c 100644
--- a/Main/Application.cpp
+++ b/Main/Application.cpp
@@ -34,7 +34,7 @@ Application::Application()
 {
 	m_iBackbufferWidth = 500;
 	m_iBackbufferHeight = 500;
-	m_iNumSamples = 16;
+	m_iNumSamples = 1024;
 	m_dTotalRenderTime = 0;
 	m_dDenoiserTime = 0;
 	m_bThreaded = false;
@@ -273,33 +273,37 @@ void Application::ParallelTrace(std::mutex * threadMutex, int i, GLFWwindow* win
 	std::vector<glm::vec2> samples = m_pSampler->GetSamples();
 
 	// Error check for bounds!
-	if (startWidth < endWidth && startHeight < endHeight)
+	for (int s = 0; s < ns; ++s)
 	{
-		for (int j = startHeight; j <= endHeight; j++)
+		if (startWidth < endWidth && startHeight < endHeight)
 		{
-			for (int i = startWidth; i <= endWidth; i++)
+			for (int j = startHeight; j <= endHeight; j++)
 			{
-				glm::vec3 color(0, 0, 0);
-
-				for (int s = 0; s < ns; s++)
+				for (int i = startWidth; i <= endWidth; i++)
 				{
-					float u = float(i + samples[s].x); 
-					float v = float(j + samples[s].y); 
+					glm::vec3 color(0, 0, 0);
+
+					float u = float(i + samples[s].x);
+					float v = float(j + samples[s].y);
 
 					Ray r = m_pScene->getCamera()->get_ray(u, v);
 
 					color = color + TraceColor(r, 0, rayCount);
+				
+					//color = color / float(ns);
+					color = glm::vec3(sqrt(color.x), sqrt(color.y), sqrt(color.z));
+
+					//threadMutex->lock();
+					//!-- Accumulative buffer
+					// So instead of running all the samples in each iteration, we run one sample
+					// in each iteration & acumulate the result in final buffer!
+					m_vecSrcPixels[j * endWidth + i] += (color / (float)ns);
+					//threadMutex->unlock();
 				}
-
-				color = color / float(ns);
-				color = glm::vec3(sqrt(color.x), sqrt(color.y), sqrt(color.z));
-
-				//threadMutex->lock();
-				m_vecSrcPixels[j * endWidth + i] = color;
-				//threadMutex->unlock();
 			}
 		}
 	}
+	
 
 	m_iRayCount += rayCount;
 }
@@ -376,7 +380,7 @@ void Application::Trace(GLFWwindow* window)
 
 				color = color + TraceColor(r, 0, rayCount);
 			}
-
+			
 			color = color / float(m_iNumSamples);
 			color = glm::vec3(sqrt(color.x), sqrt(color.y), sqrt(color.z));
 
@@ -389,6 +393,7 @@ void Application::Trace(GLFWwindow* window)
 		glfwSwapBuffers(window);
 		rowColor.clear();
 	}
+	
 
 	m_iRayCount += rayCount;
 
diff --git a/RayTracer/Scene.cpp b/RayTracer/Scene.cpp
index e7c2c90..266b50c 100644
--- a/RayTracer/Scene.cpp
+++ b/RayTracer/Scene.cpp
@@ -268,20 +268,20 @@ void Scene::InitTowerScene(float screenWidth, float screenHeight)
 
 	// Sphere Ground
 	glm::vec3 center1(0.0f, -100.5f, 0.0f);
-	glm::vec3 albedo1(0.1f, 0.1f, 0.1f);
-	Material* pMatSphereGround = new Metal(new ConstantTexture(albedo1), 0.0f);
+	glm::vec3 albedo1(1.0f);
+	Material* pMatSphereGround = new Lambertian(new ConstantTexture(albedo1));
 	Sphere* pSphereGround = new Sphere(center1, 100.0f, pMatSphereGround);
 
 	// Tower
 	MeshInfo towerInfo;
 	towerInfo.filePath = "models/Tower.fbx";
-	towerInfo.isLightSource = true;
+	towerInfo.isLightSource = false;
 	towerInfo.leafSize = 512;
 	towerInfo.position = glm::vec3(-0.9f, 0.0f, 1.0f);
 	towerInfo.rotationAxis = glm::vec3(0, 1, 0);
 	towerInfo.rotationAngle = -60.0f;
 	towerInfo.scale = glm::vec3(0.5f);
-	towerInfo.matInfo.albedoColor = glm::vec4(2.0f, 1.5f, 1.5f, 1.0f);
+	towerInfo.matInfo.albedoColor = glm::vec4(1.0f, 0.5f, 0.8f, 1.0f);
 	TriangleMesh* pTower = new TriangleMesh(towerInfo);
 
 	vecHitables.push_back(pSphereGround);
```

