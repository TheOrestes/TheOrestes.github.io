# Post 15 — Killing SetPixel: a screen-aligned quad and texture upload

## `6064703` — 2018-11-10 _(master)_

> Added GL based ray tracing renderer. Single threaded implementation.

```diff
diff --git a/Main/GLSLShader.cpp b/Main/GLSLShader.cpp
new file mode 100644
index 0000000..3d821ce
--- /dev/null
+++ b/Main/GLSLShader.cpp
@@ -0,0 +1,109 @@
+
+#include "GLSLShader.h"
+#include <iostream>
+#include <fstream>
+
+//////////////////////////////////////////////////////////////////////////
+GLSLShader::GLSLShader(const std::string& vertShader, const std::string& fragShader)
+{
+	shaderID = LoadShader(vertShader, fragShader);
+}
+
+//////////////////////////////////////////////////////////////////////////
+GLSLShader::~GLSLShader()
+{
+	glDeleteProgram(shaderID);
+}
+
+//////////////////////////////////////////////////////////////////////////
+GLuint GLSLShader::LoadShader(const std::string& vShader, const std::string& fShader)
+{
+	/// Read vertex shader code from the file...
+	std::string vertexShaderSrc;
+	std::ifstream vsStream(vShader.c_str(), std::ios::in);
+
+	if(vsStream.is_open())
+	{
+		std::string line;
+		while(std::getline(vsStream, line))
+		{
+			vertexShaderSrc += "\n" + line;
+		}
+
+		vsStream.close();
+	}
+
+	/// Read pixel shader code from the file...
+	std::string pixelShaderSrc;
+	std::ifstream psStream(fShader.c_str(), std::ios::in);
+
+	if(psStream.is_open())
+	{
+		std::string line;
+		while(std::getline(psStream, line))
+		{
+			pixelShaderSrc += "\n" + line;
+		}
+
+		psStream.close();
+	}
+
+	// create shaders
+	GLuint vertexShaderID = glCreateShader(GL_VERTEX_SHADER);
+	GLuint fragmentShaderID = glCreateShader(GL_FRAGMENT_SHADER);
+
+	/// Compile Vertex shader...
+	const char* ptrVertexShaderSrc = vertexShaderSrc.c_str();
+	glShaderSource(vertexShaderID, 1, &ptrVertexShaderSrc, NULL);
+	glCompileShader(vertexShaderID);
+
+	// Check for shader compilation errors...
+	if(!IsShaderCompiled(vertexShaderID, vShader))
+		return 0;
+
+	/// Compile fragment shader...
+	const char* ptrFragShaderSrc = pixelShaderSrc.c_str();
+	glShaderSource(fragmentShaderID, 1, &ptrFragShaderSrc, NULL);
+	glCompileShader(fragmentShaderID);
+
+	// Check for shader compilation errors...
+	if(!IsShaderCompiled(fragmentShaderID, fShader))
+		return 0;
+
+	// Create shader program
+	GLuint shaderProgramID = glCreateProgram();
+	glAttachShader(shaderProgramID, vertexShaderID);
+	glAttachShader(shaderProgramID, fragmentShaderID);
+	glLinkProgram(shaderProgramID);
+
+	glDeleteShader(vertexShaderID);
+	glDeleteShader(fragmentShaderID);
+
+	return shaderProgramID;
+}
+
+//////////////////////////////////////////////////////////////////////////
+bool GLSLShader::IsShaderCompiled(GLuint shaderID, const std::string& name)
+{
+	GLint result = GL_FALSE;
+	int infoLogLength;
+	char infoLog[2048];
+
+	glGetShaderiv(shaderID, GL_COMPILE_STATUS, &result);
+	glGetShaderiv(shaderID, GL_INFO_LOG_LENGTH, &infoLogLength);
+
+	if(!result)
+	{
+		glGetShaderInfoLog(shaderID, infoLogLength, NULL, infoLog);
+		std::cout << "Error compiling shader :" << name.c_str() << " : " << infoLog;
+		return false;
+	}
+
+	return true;
+}
+
+//////////////////////////////////////////////////////////////////////////
+void GLSLShader::Use()
+{
+	glUseProgram(shaderID);
+}
\ No newline at end of file
diff --git a/Main/GLSLShader.h b/Main/GLSLShader.h
new file mode 100644
index 0000000..8c7b658
--- /dev/null
+++ b/Main/GLSLShader.h
@@ -0,0 +1,20 @@
+
+#pragma once
+
+#include "GL/glew.h"
+#include <string>
+
+class GLSLShader
+{
+public:
+	GLSLShader(const std::string& vertShader, const std::string& fragShader);
+	~GLSLShader();
+
+	void			Use();
+	inline GLuint	GetShaderID(){ return shaderID; }
+
+private:
+	GLuint			shaderID;
+	GLuint			LoadShader(const std::string& vShader, const std::string& fShader);
+	bool			IsShaderCompiled(GLuint shaderID, const std::string& name);
+};
\ No newline at end of file
diff --git a/Main/Main.cpp b/Main/Main.cpp
new file mode 100644
index 0000000..cd87b09
--- /dev/null
+++ b/Main/Main.cpp
@@ -0,0 +1,413 @@
+// WindowsRayTracer.cpp : Defines the entry point for the application.
+//
+
+#include <iostream>
+#include "GL\glew.h"
+#include "GLFW\glfw3.h"
+#include <vector>
+#include <string>
+#include <thread>
+#include <mutex>
+
+/////------- Ray Tracer based Includes -------/////
+#include "glm/glm.hpp"
+#include "glm\gtc\type_ptr.hpp"
+#include "../RayTracer/Ray.h"
+#include "../RayTracer/Sphere.h"
+#include "../RayTracer/Triangle.h"
+#include "../RayTracer/Scene.h"
+#include "../RayTracer/Camera.h"
+#include "../RayTracer/Helper.h"
+#include "../RayTracer/Material.h"
+#include "../RayTracer/Lambertian.h"
+#include "../RayTracer/Metal.h"
+#include "../RayTracer/Transparent.h"
+#include "ScreenAlignedQuad.h"
+
+const int COLOR_CHANNELS = 3; // RGB
+const int gBackbufferWidth = 480;
+const int gBackbufferHeight = 270;
+const int nSamples = 1;
+
+unsigned long long int numRays = 0;
+
+int maxNumThreads = 0;
+double TotalRenderTime = 0;
+
+GLFWwindow* window = nullptr;
+Camera* gCam = nullptr;
+ScreenAlignedQuad* gQuad = nullptr;
+
+glm::vec3 gColorBuffer[gBackbufferWidth][gBackbufferHeight];
+float** ppColorBuffer = nullptr;
+
+std::vector<glm::vec3> vecBuffer;
+
+/////////////////////////////////////////////////////////////////////////////////////////////////////////////
+#pragma region RayTracer
+
+//Hitable* BasicTestScene()
+//{
+//	Hitable** list = new Hitable*[6];
+//	list[0] = new Sphere(glm::vec3(1.05f, 0, 0), 0.5, new Metal(glm::vec3(0.5, 0.2, 0.1), 0.5));
+//	list[1] = new Sphere(glm::vec3(0, -100.5, 0), 100, new Lambertian(glm::vec3(0.2, 0.2, 0.2)));
+//	list[2] = new Sphere(glm::vec3(0, 0, 2), 0.5, new Lambertian(glm::vec3(1.0f, 0.0f, 0.0f)));
+//	list[3] = new Sphere(glm::vec3(-1.05f, 0, 0), 0.5, new Metal(glm::vec3(1.0, 0.2, 0.0), 0));
+//	list[4] = new Sphere(glm::vec3(0.0f, 0, -3), 0.5, new Lambertian(glm::vec3(1.0, 1.0, 0.0)));
+//	list[5] = new Triangle(glm::vec3(-2.0f, 0.0f, -1.0f), glm::vec3(2.0f, 0.0f, -1.0f), glm::vec3(0.0f, 2.0f, -1.0f), new Lambertian(glm::vec3(0.0f, 1.0f, 0.0f)));
+//
+//	return new HitableList(list, 6);
+//}
+//
+//Hitable* random_scene()
+//{
+//	int n = 500;
+//	Hitable** list = new Hitable*[n + 1];
+//	list[0] = new Sphere(glm::vec3(0, -1000, 0), 1000, new Lambertian(glm::vec3(0.5, 0.5, 0.5)));
+//	int i = 1;
+//	for (int a = -11; a < 11; a++)
+//	{
+//		for (int b = -11; b < 11; b++)
+//		{
+//			float choose_mat = Helper::GetRandom01();
+//			glm::vec3 center(a + 0.9f*Helper::GetRandom01(), 0.2, b + 0.9*Helper::GetRandom01());
+//			if ((center - glm::vec3(4, 0.2, 0)).Length() > 0.9f)
+//			{
+//				if (choose_mat < 0.8f)
+//				{
+//					// diffuse
+//					list[i++] = new Sphere(center, 0.2f, new Lambertian(glm::vec3(Helper::GetRandom01()*Helper::GetRandom01(), Helper::GetRandom01()*Helper::GetRandom01(), Helper::GetRandom01()*Helper::GetRandom01())));
+//				}
+//				else if (choose_mat < 0.95)
+//				{
+//					// Metal
+//					list[i++] = new Sphere(center, 0.2f, new Metal(glm::vec3(0.5f*(1 + Helper::GetRandom01()), 0.5f*(1 + Helper::GetRandom01()), 0.5f*(1 + Helper::GetRandom01())), Helper::GetRandom01()));
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
+//	list[i++] = new Sphere(glm::vec3(0, 1, 0), 1.0f, new Transparent(1.5f));
+//	list[i++] = new Sphere(glm::vec3(-4, 1, 0), 1.0f, new Lambertian(glm::vec3(0.4f, 0.2f, 0.1f)));
+//	list[i++] = new Sphere(glm::vec3(4, 1, 0), 1.0f, new Metal(glm::vec3(0.7f, 0.6f, 0.5f), 0.0f));
+//
+//	return new HitableList(list, i);
+//}
+//
+//Hitable* world = BasicTestScene();
+glm::vec3 TraceColor(const Ray& r, int depth)
+{
+	HitRecord rec;
+
+	++numRays;
+	if (Scene::getInstance().Trace(r, 0.001f, FLT_MAX, rec))
+	{
+		Ray scatteredRay;
+		glm::vec3 attenuation;
+
+		if (depth < 50 && rec.mat_ptr->Scatter(r, rec, attenuation, scatteredRay))
+		{
+			return attenuation * TraceColor(scatteredRay, depth + 1);
+		}
+		else
+		{
+			return glm::vec3(0, 0, 0);
+		}
+	}
+	else
+	{
+		glm::vec3 unit_direction = glm::normalize(r.GetRayDirection());
+		float t = 0.5 * (unit_direction.y + 1.0f);
+		return Helper::LerpVector(glm::vec3(1.0f, 1.0f, 1.0f), glm::vec3(0.5f, 0.7f, 1.0f), t);
+	}
+}
+
+void ShowProgress(int percentage)
+{
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
+	GLFWwindow* hWindow = window;
+
+	threadMutex->unlock();
+
+	// Error check for bounds!
+	if (startWidth < endWidth && startHeight < endHeight)
+	{
+		for (int j = startHeight; j <= endHeight; j++)
+		{
+			std::vector<glm::vec3> rowColor;
+
+			for (int i = startWidth; i <= endWidth; i++)
+			{
+				glm::vec3 color(0, 0, 0);
+
+				for (int s = 0; s < ns; s++)
+				{
+					float u = float(i + Helper::GetRandom01()) / float(backBufferWidth);
+					float v = float(j + Helper::GetRandom01()) / float(backBufferHeight);
+
+					Ray r = gCam->get_ray(u, v);
+
+					color = color + TraceColor(r, 0);
+				}
+
+				color = color / float(ns);
+				color = glm::vec3(sqrt(color.x), sqrt(color.y), sqrt(color.z));
+
+				threadMutex->lock();
+				
+				vecBuffer[j * endHeight + i] = color;
+
+				threadMutex->unlock();
+
+				//rowColor.push_back(color);
+				
+				//SetPixel(hdc, backBufferWidth - i, backBufferHeight - j, RGB(ir, ig, ib));
+				//++counter;
+			}
+
+			//gQuad->UpdateTexture(i, j, backBufferWidth, 1, glm::value_ptr(rowColor[0]));
+			//gQuad->Render();
+			//glfwSwapBuffers(hWindow);
+			rowColor.clear();
+		}
+	}
+}
+
+
+void UpdateGL()
+{
+	gQuad->UpdateTexture(0, 0, gBackbufferWidth, gBackbufferHeight, glm::value_ptr(vecBuffer[0]));
+	gQuad->Render();
+	glfwSwapBuffers(window);
+}
+
+void Trace()
+{
+	if (gCam == nullptr)
+		return;
+
+#pragma region OLD_CODE
+
+	for (int j = gBackbufferHeight; j >= 0; j--)
+	{
+		std::vector<glm::vec3> rowColors;
+	
+		for (int i = 0; i <= gBackbufferWidth; i++)
+		{
+			glm::vec3 color(0, 0, 0);
+	
+			for (int s = 0; s < nSamples; s++)
+			{
+				float u = float(i + Helper::GetRandom01()) / float(gBackbufferWidth);
+				float v = float(j + Helper::GetRandom01()) / float(gBackbufferHeight);
+	
+				Ray r = gCam->get_ray(u, v);
+	
+				color = color + TraceColor(r, 0);
+			}
+	
+			color = color / float(nSamples);
+			color = glm::vec3(sqrt(color.x), sqrt(color.y), sqrt(color.z));
+	
+			//SetPixel(hdc, gBackbufferWidth - i, gBackbufferHeight - j, RGB(ir, ig, ib));
+	
+			rowColors.push_back(color);
+		}
+	
+		gQuad->UpdateTexture(0, j, gBackbufferWidth, 1, glm::value_ptr(rowColors[0]));
+		gQuad->Render();
+		glfwSwapBuffers(window);
+		rowColors.clear();
+		//percentageDone = (counter / (gBackbufferWidth*gBackbufferHeight)) * 100.0f;
+		//ShowProgress(percentageDone);
+	}
+#pragma endregion
+
+	//std::vector<std::thread*> ThreadGroup;
+	//std::mutex threadMutex;
+	//
+	//for (int i = 0; i < maxNumThreads; i++)
+	//{
+	//	std::thread* t = new std::thread(&ParallelTrace, &threadMutex, i);
+	//	ThreadGroup.push_back(t);
+	//}
+	//
+	//std::vector<std::thread*>::iterator iter = ThreadGroup.begin();
+	//for (; iter != ThreadGroup.end(); iter++)
+	//{
+	//	//if((*iter)->joinable())
+	//	(*iter)->join();
+	//}
+}
+
+void Execute()
+{
+
+	int percentageDone = 0.0f;
+
+	const clock_t begin_time = clock();
+	double counter = 0;
+
+	Trace();
+
+	const clock_t end_time = clock();
+	TotalRenderTime = (end_time - begin_time) / (double)CLOCKS_PER_SEC;
+
+	const size_t len = 256;
+	wchar_t buffer[len] = {};
+	swprintf(buffer, L"Windows Ray Tracer [Render Time : %0.2f seconds!]", TotalRenderTime);
+	//SetWindowText(hWnd, buffer);
+	//MessageBox(hWnd, buffer, L"Render Time!", MB_OKCANCEL);
+
+	//printf("Render Time : %.2f seconds\n", time);
+
+}
+
+#pragma endregion
+////////////////////////////////////////// END OF RAY TRACER CODE ///////////////////////////////////////////
+
+void InitGLFW()
+{
+	// Initialize & Setup basic 
+	glfwInit();
+	glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
+	glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 0);
+	glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
+	glfwWindowHint(GLFW_RESIZABLE, GL_FALSE);
+
+	// Create a window!
+	window = glfwCreateWindow(gBackbufferWidth, gBackbufferHeight, "Ray Tracer", nullptr, nullptr);
+
+	if (!window)
+	{
+		std::cout << "Create Window FAILED!!!\n";
+		glfwTerminate();
+		return;
+	}
+
+	// Window is created, now create context for the same window...
+	glfwMakeContextCurrent(window);
+}
+
+void InitGLEW()
+{
+	// Ensure glew uses all the modern techniques...
+	glewExperimental = GL_TRUE;
+
+	// Initialize GLEW
+	if (glewInit() != GLEW_OK)
+	{
+		std::cout << "Initialize GLEW FAILED!!!\n";
+		return;
+	}
+}
+
+//////////////////////////////////////////////////////////////////////////
+// 3. Inputs
+void KeyHandler(GLFWwindow* window, int key, int scancode, int action, int mode)
+{
+	if (key == GLFW_KEY_ESCAPE && action == GLFW_PRESS)
+	{
+		
+	}
+}
+
+int main()
+{
+	InitGLFW();
+	InitGLEW();
+
+	glfwSetKeyCallback(window, KeyHandler);
+
+	// get maximum number of supported threads!
+	maxNumThreads = std::thread::hardware_concurrency();
+
+	// Initialize Screen Aligned Quad
+	gQuad = new ScreenAlignedQuad();
+	gQuad->Init(gBackbufferWidth, gBackbufferHeight);
+
+	// Initialize global color buffer
+	//vecBuffer.resize(gBackbufferWidth*gBackbufferHeight);
+	glm::vec3 col = glm::vec3(1,0,0);
+	for (int i = 0; i < gBackbufferWidth * gBackbufferHeight; i++)
+	{
+		vecBuffer.push_back(col);
+	}
+	
+	// Initialize Camera!
+	Camera::getInstance().InitCamera(gBackbufferWidth, gBackbufferHeight);
+	gCam = &Camera::getInstance();
+
+	Execute();
+
+	glfwTerminate();
+
+	return 0;
+}
+
+
+void SaveImage()
+{
+	//static int count = 0;
+	//
+	//BITMAPINFO info;
+	//BITMAPFILEHEADER header;
+	//memset(&info, 0, sizeof(info));
+	//memset(&header, 0, sizeof(header));
+	//
+	//info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
+	//info.bmiHeader.biWidth = gBackbufferWidth;
+	//info.bmiHeader.biHeight = gBackbufferHeight;
+	//info.bmiHeader.biPlanes = 1;
+	//info.bmiHeader.biBitCount = 24;
+	//info.bmiHeader.biCompression = BI_RGB;
+	////info.bmiHeader.biSizeImage = width * height * 3;
+	//
+	//header.bfType = 0x4D42;
+	//header.bfOffBits = sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER);
+	//
+	//char* pixels = NULL;
+	//HDC hdc = GetDC(hWnd);
+	//HDC memDC = CreateCompatibleDC(hdc);
+	//HBITMAP section = CreateDIBSection(hdc, &info, DIB_RGB_COLORS, (void**)&pixels, 0, 0);
+	//DeleteObject(SelectObject(memDC, section));
+	//BitBlt(memDC, 0, 0, gBackbufferWidth, gBackbufferHeight, hdc, 0, 0, SRCCOPY);
+	//DeleteDC(memDC);
+	//
+	//count++;
+	//char buf[32] = { 0 };
+	//sprintf(buf, "RenderImage%d.bmp", count);
+	//std::fstream hFile(buf, std::ios::out | std::ios::binary);
+	//if (hFile.is_open())
+	//{
+	//	hFile.write((char*)&header, sizeof(header));
+	//	hFile.write((char*)&info.bmiHeader, sizeof(info.bmiHeader));
+	//	int bytes = (((24 * gBackbufferWidth + 31) & (~31)) / 8) * gBackbufferHeight;
+	//	hFile.write(pixels, bytes);
+	//	hFile.close();
+	//}
+	//
+	//DeleteObject(section);
+}
+
+
diff --git a/Main/ScreenAlignedQuad.cpp b/Main/ScreenAlignedQuad.cpp
new file mode 100644
index 0000000..056c07e
--- /dev/null
+++ b/Main/ScreenAlignedQuad.cpp
@@ -0,0 +1,99 @@
+
+#include "ScreenAlignedQuad.h"
+#include <iostream>
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+ScreenAlignedQuad::ScreenAlignedQuad()
+{
+	m_pFXShader = nullptr;
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+ScreenAlignedQuad::~ScreenAlignedQuad()
+{
+	Kill();
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void ScreenAlignedQuad::Init(int width, int height)
+{
+	// Create Shader that will used to draw screen aligned quad...
+	m_pFXShader = new GLSLShader("Main/vsScreenQuad.glsl", "Main/psScreenQuad.glsl");
+	if (m_pFXShader && m_pFXShader->GetShaderID() != -1)
+	{
+		hScreenTexture = glGetUniformLocation(m_pFXShader->GetShaderID(), "screenTexture");
+	}
+
+	// Create screen aligned quad data in NDC space.
+	quadVertices[0] = VertexPT(glm::vec3(-1, 1, 0), glm::vec2(0, 1));
+	quadVertices[1] = VertexPT(glm::vec3(-1, -1, 0), glm::vec2(0, 0));
+	quadVertices[2] = VertexPT(glm::vec3(1, -1, 0), glm::vec2(1, 0));
+	quadVertices[3] = VertexPT(glm::vec3(-1, 1, 0), glm::vec2(0, 1));
+	quadVertices[4] = VertexPT(glm::vec3(1, -1, 0), glm::vec2(1, 0));
+	quadVertices[5] = VertexPT(glm::vec3(1, 1, 0), glm::vec2(1, 1));
+
+	// Create VBO & VAO for the screen aligned quad...
+	glGenVertexArrays(1, &vao);
+	glGenBuffers(1, &vbo);
+
+	glBindVertexArray(vao);
+
+	glBindBuffer(GL_ARRAY_BUFFER, vbo);
+	glBufferData(GL_ARRAY_BUFFER, sizeof(quadVertices), quadVertices, GL_STATIC_DRAW);
+	glEnableVertexAttribArray(0);
+	glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(VertexPT), (void*)0);
+	glEnableVertexAttribArray(1);
+	glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, sizeof(VertexPT), (void*)offsetof(VertexPT, uv));
+	glBindBuffer(GL_ARRAY_BUFFER, 0);
+
+	glBindVertexArray(0);
+
+	// create texture buffer object
+	glGenTextures(1, &tbo);
+	glBindTexture(GL_TEXTURE_2D, tbo);
+	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, width, height, 0, GL_RGB, GL_FLOAT, NULL);
+	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
+	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);	
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void ScreenAlignedQuad::UpdateTexture(int xStart, int yStart, int width, int height, const float* pixels)
+{
+	glBindTexture(GL_TEXTURE_2D, tbo);
+
+	glTexSubImage2D(GL_TEXTURE_2D, 0, xStart, yStart, width, height, GL_RGB, GL_FLOAT, (void*)pixels);
+
+	glBindTexture(GL_TEXTURE_2D, 0);
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void ScreenAlignedQuad::Render()
+{
+	glDisable(GL_DEPTH_TEST);
+
+	m_pFXShader->Use();
+	glUniform1i(hScreenTexture, 0);
+
+	glActiveTexture(GL_TEXTURE0);
+	glBindTexture(GL_TEXTURE_2D, tbo);
+
+	glBindVertexArray(vao);
+	glDrawArrays(GL_TRIANGLES, 0, 6);
+	glBindVertexArray(0);
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void ScreenAlignedQuad::Kill()
+{
+	glDeleteVertexArrays(1, &vao);
+	glDeleteBuffers(1, &vbo);
+	glDeleteBuffers(1, &tbo);
+
+	delete m_pFXShader;
+	m_pFXShader = nullptr;
+
+	delete[] quadVertices;
+}
+
+
+
diff --git a/Main/ScreenAlignedQuad.h b/Main/ScreenAlignedQuad.h
new file mode 100644
index 0000000..4c09b23
--- /dev/null
+++ b/Main/ScreenAlignedQuad.h
@@ -0,0 +1,34 @@
+#pragma once
+
+#include "GL\glew.h"
+#include "GLSLShader.h"
+#include "VertexStructures.h"
+
+class ScreenAlignedQuad
+{
+public:
+	ScreenAlignedQuad();
+	~ScreenAlignedQuad();
+
+	void Init(int width, int height);
+	void UpdateTexture(int xStart, int yStart, int width, int height, const float* pixels);
+	void Render();
+	void Kill();
+
+private:
+	GLuint		vao;
+	GLuint		vbo;
+	GLuint		tbo;
+
+	GLint		posAttrib;
+	GLint		texAttrib;
+
+	VertexPT	quadVertices[6];
+	GLSLShader* m_pFXShader;
+
+	GLint		hScreenTexture;
+};
+
+
+
+
diff --git a/Main/VertexStructures.h b/Main/VertexStructures.h
new file mode 100644
index 0000000..f1dc953
--- /dev/null
+++ b/Main/VertexStructures.h
@@ -0,0 +1,123 @@
+
+#pragma once
+
+#include "GL/glew.h"
+#include <string>
+#include "glm/glm.hpp"
+
+#include "assimp/Importer.hpp"
+#include "assimp/postprocess.h"
+#include "assimp/scene.h"
+
+//////////////////////////////////////////////////////////////////////////////////////////
+struct VertexP
+{
+	VertexP() : position(0.0f){}
+	VertexP(glm::vec3 _p) : position(_p){}
+
+	glm::vec3 position;
+};
+
+//////////////////////////////////////////////////////////////////////////////////////////
+struct VertexPC
+{
+	VertexPC() : 
+		position(0.0f),
+		color(1.0f){}
+
+	VertexPC(const glm::vec3& _p, const glm::vec4& _c) : 
+		position(_p),
+		color(_c) {}
+
+	glm::vec3	position;
+	glm::vec4	color;
+};
+
+//////////////////////////////////////////////////////////////////////////////////////////
+struct VertexPT
+{
+	VertexPT() :
+		position(0.0f),
+		uv(0.0f) {}
+
+	VertexPT(const glm::vec3& _p, const glm::vec2& _uv) :
+		position(_p),
+		uv(_uv) {}
+
+	glm::vec3 position;
+	glm::vec2 uv;
+};
+
+//////////////////////////////////////////////////////////////////////////////////////////
+struct VertexPTN
+{
+	VertexPTN() :
+		position(0.0f), uv(0.0f), normal(1.0f) {}
+
+	VertexPTN(const glm::vec3& _p, const glm::vec2& _uv, const glm::vec3& _n) :
+		position(_p), uv(_uv), normal(_n) {}
+
+	glm::vec3	position;
+	glm::vec2	uv;
+	glm::vec3	normal;
+};
+
+//////////////////////////////////////////////////////////////////////////////////////////
+struct VertexPTNBT
+{
+	VertexPTNBT() :
+		position(0.0f),
+		uv(0.0f),
+		normal(1.0f),
+		binormal(0.0f),
+		tangent(0.0f) {}
+
+	VertexPTNBT(const glm::vec3& _p, const glm::vec3& _uv, const glm::vec3& _n, const glm::vec3& _b, const glm::vec3& _t ) :
+		position(_p),
+		uv(_uv),
+		normal(_n),
+		binormal(_b),
+		tangent(_t){}
+
+	glm::vec3	position;
+	glm::vec2	uv;
+	glm::vec3	normal;
+	glm::vec3   tangent;
+	glm::vec3   binormal;
+	
+};
+
+//////////////////////////////////////////////////////////////////////////////////////////
+struct Texture
+{
+	GLuint		id;
+	std::string name;
+	aiString	path;
+};
+
+//////////////////////////////////////////////////////////////////////////////////////////
+struct StaticObjectData
+{
+	StaticObjectData()
+	{
+		path.clear();
+		shader.clear();
+
+		position  = glm::vec3(0);
+		rotation  = glm::vec3(0,1,0);
+		angle	  = 0.0f;
+		scale     = glm::vec3(1);
+
+		showBBox  = false;
+	}
+
+	std::string path;
+	std::string shader;
+
+	glm::vec3	position;
+	glm::vec3	rotation;
+	float		angle;
+	glm::vec3	scale;
+
+	bool		showBBox;
+};
diff --git a/Main/psScreenQuad.glsl b/Main/psScreenQuad.glsl
new file mode 100644
index 0000000..94b7589
--- /dev/null
+++ b/Main/psScreenQuad.glsl
@@ -0,0 +1,12 @@
+
+#version 400
+
+in vec2 vs_outTexcoord;
+out vec4 outColor;
+
+uniform sampler2D screenTexture;
+
+void main()
+{
+	outColor = texture(screenTexture, vs_outTexcoord);
+}
\ No newline at end of file
diff --git a/Main/vsScreenQuad.glsl b/Main/vsScreenQuad.glsl
new file mode 100644
index 0000000..d2d6b88
--- /dev/null
+++ b/Main/vsScreenQuad.glsl
@@ -0,0 +1,13 @@
+
+#version 400
+
+layout(location=0) in vec3 in_Position;
+layout(location=1) in vec2 in_Texcoord;
+
+out vec2 vs_outTexcoord;
+
+void main()
+{
+	gl_Position = vec4(in_Position.x, in_Position.y, 0.0f, 1.0f);
+	vs_outTexcoord = in_Texcoord;
+}
\ No newline at end of file
diff --git a/RayTracer/Scene.cpp b/RayTracer/Scene.cpp
index b6a065b..04f64de 100644
--- a/RayTracer/Scene.cpp
+++ b/RayTracer/Scene.cpp
@@ -46,7 +46,7 @@ void Scene::InitScene()
 	vecHitables.push_back(pSphere3);
 	vecHitables.push_back(pSphere4);
 	//vecHitables.push_back(pTriangle0);
-	vecHitables.push_back(pMesh0);
+	//vecHitables.push_back(pMesh0);
 }
 
 void Scene::InitRandomScene()
```

## `d6488bb` — 2018-11-11 _(OpenGL branch)_

> Added Opengl based single threaded & multi-threaded support. Realtime visualization for multi-threaded still missing.

```diff
diff --git a/Main/GLSLShader.cpp b/Main/GLSLShader.cpp
new file mode 100644
index 0000000..3d821ce
--- /dev/null
+++ b/Main/GLSLShader.cpp
@@ -0,0 +1,109 @@
+
+#include "GLSLShader.h"
+#include <iostream>
+#include <fstream>
+
+//////////////////////////////////////////////////////////////////////////
+GLSLShader::GLSLShader(const std::string& vertShader, const std::string& fragShader)
+{
+	shaderID = LoadShader(vertShader, fragShader);
+}
+
+//////////////////////////////////////////////////////////////////////////
+GLSLShader::~GLSLShader()
+{
+	glDeleteProgram(shaderID);
+}
+
+//////////////////////////////////////////////////////////////////////////
+GLuint GLSLShader::LoadShader(const std::string& vShader, const std::string& fShader)
+{
+	/// Read vertex shader code from the file...
+	std::string vertexShaderSrc;
+	std::ifstream vsStream(vShader.c_str(), std::ios::in);
+
+	if(vsStream.is_open())
+	{
+		std::string line;
+		while(std::getline(vsStream, line))
+		{
+			vertexShaderSrc += "\n" + line;
+		}
+
+		vsStream.close();
+	}
+
+	/// Read pixel shader code from the file...
+	std::string pixelShaderSrc;
+	std::ifstream psStream(fShader.c_str(), std::ios::in);
+
+	if(psStream.is_open())
+	{
+		std::string line;
+		while(std::getline(psStream, line))
+		{
+			pixelShaderSrc += "\n" + line;
+		}
+
+		psStream.close();
+	}
+
+	// create shaders
+	GLuint vertexShaderID = glCreateShader(GL_VERTEX_SHADER);
+	GLuint fragmentShaderID = glCreateShader(GL_FRAGMENT_SHADER);
+
+	/// Compile Vertex shader...
+	const char* ptrVertexShaderSrc = vertexShaderSrc.c_str();
+	glShaderSource(vertexShaderID, 1, &ptrVertexShaderSrc, NULL);
+	glCompileShader(vertexShaderID);
+
+	// Check for shader compilation errors...
+	if(!IsShaderCompiled(vertexShaderID, vShader))
+		return 0;
+
+	/// Compile fragment shader...
+	const char* ptrFragShaderSrc = pixelShaderSrc.c_str();
+	glShaderSource(fragmentShaderID, 1, &ptrFragShaderSrc, NULL);
+	glCompileShader(fragmentShaderID);
+
+	// Check for shader compilation errors...
+	if(!IsShaderCompiled(fragmentShaderID, fShader))
+		return 0;
+
+	// Create shader program
+	GLuint shaderProgramID = glCreateProgram();
+	glAttachShader(shaderProgramID, vertexShaderID);
+	glAttachShader(shaderProgramID, fragmentShaderID);
+	glLinkProgram(shaderProgramID);
+
+	glDeleteShader(vertexShaderID);
+	glDeleteShader(fragmentShaderID);
+
+	return shaderProgramID;
+}
+
+//////////////////////////////////////////////////////////////////////////
+bool GLSLShader::IsShaderCompiled(GLuint shaderID, const std::string& name)
+{
+	GLint result = GL_FALSE;
+	int infoLogLength;
+	char infoLog[2048];
+
+	glGetShaderiv(shaderID, GL_COMPILE_STATUS, &result);
+	glGetShaderiv(shaderID, GL_INFO_LOG_LENGTH, &infoLogLength);
+
+	if(!result)
+	{
+		glGetShaderInfoLog(shaderID, infoLogLength, NULL, infoLog);
+		std::cout << "Error compiling shader :" << name.c_str() << " : " << infoLog;
+		return false;
+	}
+
+	return true;
+}
+
+//////////////////////////////////////////////////////////////////////////
+void GLSLShader::Use()
+{
+	glUseProgram(shaderID);
+}
\ No newline at end of file
diff --git a/Main/GLSLShader.h b/Main/GLSLShader.h
new file mode 100644
index 0000000..8c7b658
--- /dev/null
+++ b/Main/GLSLShader.h
@@ -0,0 +1,20 @@
+
+#pragma once
+
+#include "GL/glew.h"
+#include <string>
+
+class GLSLShader
+{
+public:
+	GLSLShader(const std::string& vertShader, const std::string& fragShader);
+	~GLSLShader();
+
+	void			Use();
+	inline GLuint	GetShaderID(){ return shaderID; }
+
+private:
+	GLuint			shaderID;
+	GLuint			LoadShader(const std::string& vShader, const std::string& fShader);
+	bool			IsShaderCompiled(GLuint shaderID, const std::string& name);
+};
\ No newline at end of file
diff --git a/Main/Main.cpp b/Main/Main.cpp
new file mode 100644
index 0000000..f7ebf2a
--- /dev/null
+++ b/Main/Main.cpp
@@ -0,0 +1,415 @@
+// WindowsRayTracer.cpp : Defines the entry point for the application.
+//
+
+#include <iostream>
+#include "GL\glew.h"
+#include "GLFW\glfw3.h"
+#include <vector>
+#include <string>
+#include <thread>
+#include <mutex>
+
+/////------- Ray Tracer based Includes -------/////
+#include "glm/glm.hpp"
+#include "glm\gtc\type_ptr.hpp"
+#include "../RayTracer/Ray.h"
+#include "../RayTracer/Sphere.h"
+#include "../RayTracer/Triangle.h"
+#include "../RayTracer/Scene.h"
+#include "../RayTracer/Camera.h"
+#include "../RayTracer/Helper.h"
+#include "../RayTracer/Material.h"
+#include "../RayTracer/Lambertian.h"
+#include "../RayTracer/Metal.h"
+#include "../RayTracer/Transparent.h"
+#include "ScreenAlignedQuad.h"
+
+const int COLOR_CHANNELS = 3; // RGB
+const int gBackbufferWidth = 480;
+const int gBackbufferHeight = 270;
+const int nSamples = 1;
+
+unsigned long long int numRays = 0;
+
+int maxNumThreads = 0;
+double TotalRenderTime = 0;
+
+GLFWwindow* window = nullptr;
+Camera* gCam = nullptr;
+ScreenAlignedQuad* gQuad = nullptr;
+
+std::vector<glm::vec3> copyBuffer;
+std::vector<glm::vec3> vecBuffer;
+
+/////////////////////////////////////////////////////////////////////////////////////////////////////////////
+#pragma region RayTracer
+
+//Hitable* BasicTestScene()
+//{
+//	Hitable** list = new Hitable*[6];
+//	list[0] = new Sphere(glm::vec3(1.05f, 0, 0), 0.5, new Metal(glm::vec3(0.5, 0.2, 0.1), 0.5));
+//	list[1] = new Sphere(glm::vec3(0, -100.5, 0), 100, new Lambertian(glm::vec3(0.2, 0.2, 0.2)));
+//	list[2] = new Sphere(glm::vec3(0, 0, 2), 0.5, new Lambertian(glm::vec3(1.0f, 0.0f, 0.0f)));
+//	list[3] = new Sphere(glm::vec3(-1.05f, 0, 0), 0.5, new Metal(glm::vec3(1.0, 0.2, 0.0), 0));
+//	list[4] = new Sphere(glm::vec3(0.0f, 0, -3), 0.5, new Lambertian(glm::vec3(1.0, 1.0, 0.0)));
+//	list[5] = new Triangle(glm::vec3(-2.0f, 0.0f, -1.0f), glm::vec3(2.0f, 0.0f, -1.0f), glm::vec3(0.0f, 2.0f, -1.0f), new Lambertian(glm::vec3(0.0f, 1.0f, 0.0f)));
+//
+//	return new HitableList(list, 6);
+//}
+//
+//Hitable* random_scene()
+//{
+//	int n = 500;
+//	Hitable** list = new Hitable*[n + 1];
+//	list[0] = new Sphere(glm::vec3(0, -1000, 0), 1000, new Lambertian(glm::vec3(0.5, 0.5, 0.5)));
+//	int i = 1;
+//	for (int a = -11; a < 11; a++)
+//	{
+//		for (int b = -11; b < 11; b++)
+//		{
+//			float choose_mat = Helper::GetRandom01();
+//			glm::vec3 center(a + 0.9f*Helper::GetRandom01(), 0.2, b + 0.9*Helper::GetRandom01());
+//			if ((center - glm::vec3(4, 0.2, 0)).Length() > 0.9f)
+//			{
+//				if (choose_mat < 0.8f)
+//				{
+//					// diffuse
+//					list[i++] = new Sphere(center, 0.2f, new Lambertian(glm::vec3(Helper::GetRandom01()*Helper::GetRandom01(), Helper::GetRandom01()*Helper::GetRandom01(), Helper::GetRandom01()*Helper::GetRandom01())));
+//				}
+//				else if (choose_mat < 0.95)
+//				{
+//					// Metal
+//					list[i++] = new Sphere(center, 0.2f, new Metal(glm::vec3(0.5f*(1 + Helper::GetRandom01()), 0.5f*(1 + Helper::GetRandom01()), 0.5f*(1 + Helper::GetRandom01())), Helper::GetRandom01()));
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
+//	list[i++] = new Sphere(glm::vec3(0, 1, 0), 1.0f, new Transparent(1.5f));
+//	list[i++] = new Sphere(glm::vec3(-4, 1, 0), 1.0f, new Lambertian(glm::vec3(0.4f, 0.2f, 0.1f)));
+//	list[i++] = new Sphere(glm::vec3(4, 1, 0), 1.0f, new Metal(glm::vec3(0.7f, 0.6f, 0.5f), 0.0f));
+//
+//	return new HitableList(list, i);
+//}
+//
+//Hitable* world = BasicTestScene();
+glm::vec3 TraceColor(const Ray& r, int depth)
+{
+	HitRecord rec;
+
+	++numRays;
+	if (Scene::getInstance().Trace(r, 0.001f, FLT_MAX, rec))
+	{
+		Ray scatteredRay;
+		glm::vec3 attenuation;
+
+		if (depth < 50 && rec.mat_ptr->Scatter(r, rec, attenuation, scatteredRay))
+		{
+			return attenuation * TraceColor(scatteredRay, depth + 1);
+		}
+		else
+		{
+			return glm::vec3(0, 0, 0);
+		}
+	}
+	else
+	{
+		glm::vec3 unit_direction = glm::normalize(r.GetRayDirection());
+		float t = 0.5 * (unit_direction.y + 1.0f);
+		return Helper::LerpVector(glm::vec3(1.0f, 1.0f, 1.0f), glm::vec3(0.5f, 0.7f, 1.0f), t);
+	}
+}
+
+void ShowProgress(int percentage)
+{
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
+	GLFWwindow* hWindow = window;
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
+					Ray r = gCam->get_ray(u, v);
+
+					color = color + TraceColor(r, 0);
+				}
+
+				color = color / float(ns);
+				color = glm::vec3(sqrt(color.x), sqrt(color.y), sqrt(color.z));
+
+				threadMutex->lock();
+				
+				vecBuffer[j * endWidth + i] = color;
+
+				threadMutex->unlock();
+
+				//rowColor.push_back(color);
+				
+				//SetPixel(hdc, backBufferWidth - i, backBufferHeight - j, RGB(ir, ig, ib));
+				//++counter;
+			}
+		}
+	}
+}
+
+
+void UpdateGL()
+{
+	copyBuffer.clear();
+	std::copy(vecBuffer.begin(), vecBuffer.end(), std::back_inserter(copyBuffer));
+
+	gQuad->UpdateTexture(0, 0, gBackbufferWidth, gBackbufferHeight, glm::value_ptr(vecBuffer[0]));
+	gQuad->Render();
+	glfwSwapBuffers(window);
+}
+
+void Trace()
+{
+	if (gCam == nullptr)
+		return;
+
+#pragma region OLD_CODE
+
+	//for (int j = 0; j < gBackbufferHeight; j++)
+	//{	
+	//	std::vector<glm::vec3> rowColor;
+	//	for (int i = 0; i < gBackbufferWidth; i++)
+	//	{
+	//		glm::vec3 color(0, 0, 0);
+	//
+	//		for (int s = 0; s < nSamples; s++)
+	//		{
+	//			float u = float(i + Helper::GetRandom01()) / float(gBackbufferWidth);
+	//			float v = float(j + Helper::GetRandom01()) / float(gBackbufferHeight);
+	//
+	//			Ray r = gCam->get_ray(u, v);
+	//
+	//			color = color + TraceColor(r, 0);
+	//		}
+	//
+	//		color = color / float(nSamples);
+	//		color = glm::vec3(sqrt(color.x), sqrt(color.y), sqrt(color.z));
+	//
+	//		//vecBuffer[j * gBackbufferWidth + i] = color;
+	//
+	//		rowColor.push_back(color);
+	//	}
+	//
+	//	gQuad->UpdateTexture(0, j, gBackbufferWidth, 1, glm::value_ptr(rowColor[0]));
+	//	gQuad->Render();
+	//	glfwSwapBuffers(window);
+	//	rowColor.clear();
+	//
+	//	//percentageDone = (counter / (gBackbufferWidth*gBackbufferHeight)) * 100.0f;
+	//	//ShowProgress(percentageDone);
+	//}
+#pragma endregion
+
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
+}
+
+void Execute()
+{
+
+	int percentageDone = 0.0f;
+
+	const clock_t begin_time = clock();
+	double counter = 0;
+
+	Trace();
+
+	const clock_t end_time = clock();
+	TotalRenderTime = (end_time - begin_time) / (double)CLOCKS_PER_SEC;
+
+	const size_t len = 256;
+	char buffer[len] = {};
+	sprintf(buffer, "Ray Tracer [Render Time : %0.2f seconds!]", TotalRenderTime);
+	glfwSetWindowTitle(window, buffer);
+	//SetWindowText(hWnd, buffer);
+	//MessageBox(hWnd, buffer, L"Render Time!", MB_OKCANCEL);
+
+	//printf("Render Time : %.2f seconds\n", time);
+
+}
+
+#pragma endregion
+////////////////////////////////////////// END OF RAY TRACER CODE ///////////////////////////////////////////
+
+void InitGLFW()
+{
+	// Initialize & Setup basic 
+	glfwInit();
+	glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
+	glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 0);
+	glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
+	glfwWindowHint(GLFW_RESIZABLE, GL_FALSE);
+
+	// Create a window!
+	window = glfwCreateWindow(gBackbufferWidth, gBackbufferHeight, "Ray Tracer", nullptr, nullptr);
+
+	if (!window)
+	{
+		std::cout << "Create Window FAILED!!!\n";
+		glfwTerminate();
+		return;
+	}
+
+	// Window is created, now create context for the same window...
+	glfwMakeContextCurrent(window);
+}
+
+void InitGLEW()
+{
+	// Ensure glew uses all the modern techniques...
+	glewExperimental = GL_TRUE;
+
+	// Initialize GLEW
+	if (glewInit() != GLEW_OK)
+	{
+		std::cout << "Initialize GLEW FAILED!!!\n";
+		return;
+	}
+}
+
+//////////////////////////////////////////////////////////////////////////
+// 3. Inputs
+void KeyHandler(GLFWwindow* window, int key, int scancode, int action, int mode)
+{
+	if (key == GLFW_KEY_ESCAPE && action == GLFW_PRESS)
+	{
+		
+	}
+}
+
+int main()
+{
+	InitGLFW();
+	InitGLEW();
+
+	glfwSetKeyCallback(window, KeyHandler);
+
+	// get maximum number of supported threads!
+	maxNumThreads = std::thread::hardware_concurrency();
+
+	// Initialize Screen Aligned Quad
+	gQuad = new ScreenAlignedQuad();
+	gQuad->Init(gBackbufferWidth, gBackbufferHeight);
+
+	// Initialize global color buffer
+	//vecBuffer.resize(gBackbufferWidth*gBackbufferHeight);
+	
+	glm::vec3 col = glm::vec3(1, 0, 0);
+	for (int i = 0; i < gBackbufferWidth * gBackbufferHeight; i++)
+	{
+		vecBuffer.push_back(col);	
+	}
+	std::copy(vecBuffer.begin(), vecBuffer.end(), std::back_inserter(copyBuffer));
+	
+	// Initialize Camera!
+	Camera::getInstance().InitCamera(gBackbufferWidth, gBackbufferHeight);
+	gCam = &Camera::getInstance();
+
+	Execute();
+
+	while (!glfwWindowShouldClose(window))
+	{
+		UpdateGL();
+	}
+
+	glfwTerminate();
+
+	return 0;
+}
+
+
+void SaveImage()
+{
+	//static int count = 0;
+	//
+	//BITMAPINFO info;
+	//BITMAPFILEHEADER header;
+	//memset(&info, 0, sizeof(info));
+	//memset(&header, 0, sizeof(header));
+	//
+	//info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
+	//info.bmiHeader.biWidth = gBackbufferWidth;
+	//info.bmiHeader.biHeight = gBackbufferHeight;
+	//info.bmiHeader.biPlanes = 1;
+	//info.bmiHeader.biBitCount = 24;
+	//info.bmiHeader.biCompression = BI_RGB;
+	////info.bmiHeader.biSizeImage = width * height * 3;
+	//
+	//header.bfType = 0x4D42;
+	//header.bfOffBits = sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER);
+	//
+	//char* pixels = NULL;
+	//HDC hdc = GetDC(hWnd);
+	//HDC memDC = CreateCompatibleDC(hdc);
+	//HBITMAP section = CreateDIBSection(hdc, &info, DIB_RGB_COLORS, (void**)&pixels, 0, 0);
+	//DeleteObject(SelectObject(memDC, section));
+	//BitBlt(memDC, 0, 0, gBackbufferWidth, gBackbufferHeight, hdc, 0, 0, SRCCOPY);
+	//DeleteDC(memDC);
+	//
+	//count++;
+	//char buf[32] = { 0 };
+	//sprintf(buf, "RenderImage%d.bmp", count);
+	//std::fstream hFile(buf, std::ios::out | std::ios::binary);
+	//if (hFile.is_open())
+	//{
+	//	hFile.write((char*)&header, sizeof(header));
+	//	hFile.write((char*)&info.bmiHeader, sizeof(info.bmiHeader));
+	//	int bytes = (((24 * gBackbufferWidth + 31) & (~31)) / 8) * gBackbufferHeight;
+	//	hFile.write(pixels, bytes);
+	//	hFile.close();
+	//}
+	//
+	//DeleteObject(section);
+}
+
+
diff --git a/Main/ScreenAlignedQuad.cpp b/Main/ScreenAlignedQuad.cpp
new file mode 100644
index 0000000..ffacb80
--- /dev/null
+++ b/Main/ScreenAlignedQuad.cpp
@@ -0,0 +1,99 @@
+
+#include "ScreenAlignedQuad.h"
+#include <iostream>
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+ScreenAlignedQuad::ScreenAlignedQuad()
+{
+	m_pFXShader = nullptr;
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+ScreenAlignedQuad::~ScreenAlignedQuad()
+{
+	Kill();
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void ScreenAlignedQuad::Init(int width, int height)
+{
+	// Create Shader that will used to draw screen aligned quad...
+	m_pFXShader = new GLSLShader("Main/vsScreenQuad.glsl", "Main/psScreenQuad.glsl");
+	if (m_pFXShader && m_pFXShader->GetShaderID() != -1)
+	{
+		hScreenTexture = glGetUniformLocation(m_pFXShader->GetShaderID(), "screenTexture");
+	}
+
+	// Create screen aligned quad data in NDC space.
+	quadVertices[0] = VertexPT(glm::vec3(-1, 1, 0), glm::vec2(0, 1));
+	quadVertices[1] = VertexPT(glm::vec3(-1, -1, 0), glm::vec2(0, 0));
+	quadVertices[2] = VertexPT(glm::vec3(1, -1, 0), glm::vec2(1, 0));
+	quadVertices[3] = VertexPT(glm::vec3(-1, 1, 0), glm::vec2(0, 1));
+	quadVertices[4] = VertexPT(glm::vec3(1, -1, 0), glm::vec2(1, 0));
+	quadVertices[5] = VertexPT(glm::vec3(1, 1, 0), glm::vec2(1, 1));
+
+	// Create VBO & VAO for the screen aligned quad...
+	glGenVertexArrays(1, &vao);
+	glGenBuffers(1, &vbo);
+
+	glBindVertexArray(vao);
+
+	glBindBuffer(GL_ARRAY_BUFFER, vbo);
+	glBufferData(GL_ARRAY_BUFFER, sizeof(quadVertices), quadVertices, GL_STATIC_DRAW);
+	glEnableVertexAttribArray(0);
+	glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(VertexPT), (void*)0);
+	glEnableVertexAttribArray(1);
+	glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, sizeof(VertexPT), (void*)offsetof(VertexPT, uv));
+	glBindBuffer(GL_ARRAY_BUFFER, 0);
+
+	glBindVertexArray(0);
+
+	// create texture buffer object
+	glGenTextures(1, &tbo);
+	glBindTexture(GL_TEXTURE_2D, tbo);
+	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, width, height, 0, GL_RGB, GL_FLOAT, NULL);
+	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
+	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);	
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void ScreenAlignedQuad::UpdateTexture(int xStart, int yStart, int width, int height, float* pixels)
+{
+	glBindTexture(GL_TEXTURE_2D, tbo);
+
+	glTexSubImage2D(GL_TEXTURE_2D, 0, xStart, yStart, width, height, GL_RGB, GL_FLOAT, (void*)pixels);
+
+	glBindTexture(GL_TEXTURE_2D, 0);
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void ScreenAlignedQuad::Render()
+{
+	glDisable(GL_DEPTH_TEST);
+
+	m_pFXShader->Use();
+	glUniform1i(hScreenTexture, 0);
+
+	glActiveTexture(GL_TEXTURE0);
+	glBindTexture(GL_TEXTURE_2D, tbo);
+
+	glBindVertexArray(vao);
+	glDrawArrays(GL_TRIANGLES, 0, 6);
+	glBindVertexArray(0);
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+void ScreenAlignedQuad::Kill()
+{
+	glDeleteVertexArrays(1, &vao);
+	glDeleteBuffers(1, &vbo);
+	glDeleteBuffers(1, &tbo);
+
+	delete m_pFXShader;
+	m_pFXShader = nullptr;
+
+	delete[] quadVertices;
+}
+
+
+
diff --git a/Main/ScreenAlignedQuad.h b/Main/ScreenAlignedQuad.h
new file mode 100644
index 0000000..4ffe2be
--- /dev/null
+++ b/Main/ScreenAlignedQuad.h
@@ -0,0 +1,34 @@
+#pragma once
+
+#include "GL\glew.h"
+#include "GLSLShader.h"
+#include "VertexStructures.h"
+
+class ScreenAlignedQuad
+{
+public:
+	ScreenAlignedQuad();
+	~ScreenAlignedQuad();
+
+	void Init(int width, int height);
+	void UpdateTexture(int xStart, int yStart, int width, int height, float* pixels);
+	void Render();
+	void Kill();
+
+private:
+	GLuint		vao;
+	GLuint		vbo;
+	GLuint		tbo;
+
+	GLint		posAttrib;
+	GLint		texAttrib;
+
+	VertexPT	quadVertices[6];
+	GLSLShader* m_pFXShader;
+
+	GLint		hScreenTexture;
+};
+
+
+
+
diff --git a/Main/VertexStructures.h b/Main/VertexStructures.h
new file mode 100644
index 0000000..f1dc953
--- /dev/null
+++ b/Main/VertexStructures.h
@@ -0,0 +1,123 @@
+
+#pragma once
+
+#include "GL/glew.h"
+#include <string>
+#include "glm/glm.hpp"
+
+#include "assimp/Importer.hpp"
+#include "assimp/postprocess.h"
+#include "assimp/scene.h"
+
+//////////////////////////////////////////////////////////////////////////////////////////
+struct VertexP
+{
+	VertexP() : position(0.0f){}
+	VertexP(glm::vec3 _p) : position(_p){}
+
+	glm::vec3 position;
+};
+
+//////////////////////////////////////////////////////////////////////////////////////////
+struct VertexPC
+{
+	VertexPC() : 
+		position(0.0f),
+		color(1.0f){}
+
+	VertexPC(const glm::vec3& _p, const glm::vec4& _c) : 
+		position(_p),
+		color(_c) {}
+
+	glm::vec3	position;
+	glm::vec4	color;
+};
+
+//////////////////////////////////////////////////////////////////////////////////////////
+struct VertexPT
+{
+	VertexPT() :
+		position(0.0f),
+		uv(0.0f) {}
+
+	VertexPT(const glm::vec3& _p, const glm::vec2& _uv) :
+		position(_p),
+		uv(_uv) {}
+
+	glm::vec3 position;
+	glm::vec2 uv;
+};
+
+//////////////////////////////////////////////////////////////////////////////////////////
+struct VertexPTN
+{
+	VertexPTN() :
+		position(0.0f), uv(0.0f), normal(1.0f) {}
+
+	VertexPTN(const glm::vec3& _p, const glm::vec2& _uv, const glm::vec3& _n) :
+		position(_p), uv(_uv), normal(_n) {}
+
+	glm::vec3	position;
+	glm::vec2	uv;
+	glm::vec3	normal;
+};
+
+//////////////////////////////////////////////////////////////////////////////////////////
+struct VertexPTNBT
+{
+	VertexPTNBT() :
+		position(0.0f),
+		uv(0.0f),
+		normal(1.0f),
+		binormal(0.0f),
+		tangent(0.0f) {}
+
+	VertexPTNBT(const glm::vec3& _p, const glm::vec3& _uv, const glm::vec3& _n, const glm::vec3& _b, const glm::vec3& _t ) :
+		position(_p),
+		uv(_uv),
+		normal(_n),
+		binormal(_b),
+		tangent(_t){}
+
+	glm::vec3	position;
+	glm::vec2	uv;
+	glm::vec3	normal;
+	glm::vec3   tangent;
+	glm::vec3   binormal;
+	
+};
+
+//////////////////////////////////////////////////////////////////////////////////////////
+struct Texture
+{
+	GLuint		id;
+	std::string name;
+	aiString	path;
+};
+
+//////////////////////////////////////////////////////////////////////////////////////////
+struct StaticObjectData
+{
+	StaticObjectData()
+	{
+		path.clear();
+		shader.clear();
+
+		position  = glm::vec3(0);
+		rotation  = glm::vec3(0,1,0);
+		angle	  = 0.0f;
+		scale     = glm::vec3(1);
+
+		showBBox  = false;
+	}
+
+	std::string path;
+	std::string shader;
+
+	glm::vec3	position;
+	glm::vec3	rotation;
+	float		angle;
+	glm::vec3	scale;
+
+	bool		showBBox;
+};
diff --git a/Main/psScreenQuad.glsl b/Main/psScreenQuad.glsl
new file mode 100644
index 0000000..94b7589
--- /dev/null
+++ b/Main/psScreenQuad.glsl
@@ -0,0 +1,12 @@
+
+#version 400
+
+in vec2 vs_outTexcoord;
+out vec4 outColor;
+
+uniform sampler2D screenTexture;
+
+void main()
+{
+	outColor = texture(screenTexture, vs_outTexcoord);
+}
\ No newline at end of file
diff --git a/Main/vsScreenQuad.glsl b/Main/vsScreenQuad.glsl
new file mode 100644
index 0000000..d2d6b88
--- /dev/null
+++ b/Main/vsScreenQuad.glsl
@@ -0,0 +1,13 @@
+
+#version 400
+
+layout(location=0) in vec3 in_Position;
+layout(location=1) in vec2 in_Texcoord;
+
+out vec2 vs_outTexcoord;
+
+void main()
+{
+	gl_Position = vec4(in_Position.x, in_Position.y, 0.0f, 1.0f);
+	vs_outTexcoord = in_Texcoord;
+}
\ No newline at end of file
```

