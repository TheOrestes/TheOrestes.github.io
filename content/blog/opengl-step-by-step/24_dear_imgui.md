+++
title = "Dear ImGui: Twenty-Four Posts of Console Prints Become a Live Editor"
date = 2020-03-08T18:03:00+05:30
tags = ["opengl", "rendering"]
description = "Wiring Dear ImGui into the engine: every std::cout and std::cerr this series has accumulated since post one gets rerouted into an in-engine console panel, the scene's two hardcoded objects become a browsable, editable list, and last post's wireframe overlay gets a checkbox."
math = true
+++

Every diagnostic this series has ever produced, a shader failing to compile, a texture failing to load, a framebuffer coming back incomplete, an Assimp import failing, has gone to the same place: a console window nobody's looking at while the actual render fills the screen. This commit gives all of it a second home, inside the application itself, as one of several panels built with Dear ImGui.

&nbsp;

{{< youtube zFi-abgNR14 >}}

&nbsp;

## Every std::cout Becomes a Console Panel

`UIManager::WriteToConsole()` is the new single entry point for engine diagnostics, timestamped and categorized:

```cpp
void UIManager::WriteToConsole( LOGTYPE type, const std::string& file, const std::string& message )
{
    UIConsoleMsg msg;

    switch (type)
    {
        case LOG_INFO:
        {
            msg.color = ImVec4(0, 255, 0, 255);
            msg.msg = "INFO\t " + CurrentDateTime() + "\t" + file + "\t     " + message;
            msg.type = LOG_INFO;

            consoleMsgs.push_back(msg);
            break;
        }
        // LOG_ERROR, LOG_DEBUG, LOG_RAW follow the same shape
    }
}
```

Every call site that used to write straight to `std::cout` or `std::cerr` now routes here instead. `GLSLShader::IsShaderCompiled()` reports both outcomes:

```cpp
if(!result)
{
    glGetShaderInfoLog(shaderID, infoLogLength, NULL, infoLog);
    std::string error = "Error compiling shader : " + name + ":" + infoLog;
    UIManager::getInstance().WriteToConsole(LOG_ERROR, "GLSLShader", error);
}
else
{
    std::string info = name + " compiled!";
    UIManager::getInstance().WriteToConsole(LOG_DEBUG, "GLSLShader", info);
}
```

`TextureManager::Load2DTextureFromFile()`'s `if (data != nullptr)` check from a couple posts ago now has somewhere real to report to instead of `std::cerr`, `Model::LoadModel()`'s Assimp error string goes here too, and every framebuffer-completeness check in `PostProcess` (`CreateDeferredBuffers()`, `CreateShadowMappingBuffers()`, `CreateBloomBuffers()`) reports success or failure the same way. `RenderConsole()` draws all of it as a filterable panel:

```cpp
ImGui::RadioButton("Info",  &option, 0); ImGui::SameLine();
ImGui::RadioButton("Debug", &option, 1); ImGui::SameLine();
ImGui::RadioButton("Error", &option, 2); ImGui::SameLine();
ImGui::RadioButton("Raw",   &option, 3);

for (; iter != consoleMsgs.end(); iter++)
{
    if ((*iter).type == option)
        ImGui::TextColored((*iter).color, (*iter).msg.c_str());
}
```

Everything this engine has ever wanted to tell somebody now has a filterable, color-coded, on-screen home.

## The Scene Gets a Manager

`Scene` used to hold exactly two hardcoded `StaticObject*` members, one model and one shadow-catching plane, with no way to address either of them by name. `StaticObjectManager` replaces that with a vector:

```cpp
void StaticObjectManager::GatherStaticObject(StaticObject* _object)
{
    _object->Init();
    m_vecStaticObjects.push_back(_object);
}
```

`Scene::InitScene()` now builds each object with a name before handing it off:

```cpp
data.name = "SteamPunk";
data.path = "../Assets/models/Robot/SteamPunk.fbx";
// ...
StaticObject* objMesh = new StaticObject(data);
StaticObjectManager::getInstance().GatherStaticObject(objMesh);
```

That name is what makes the object addressable in the UI. `RenderSceneUI()` walks the manager's list and gives every object its own collapsible tree node, material and transform editable right there:

```cpp
for (uint32_t i = 0; i < objectCount; ++i)
{
    StaticObject* object = StaticObjectManager::getInstance().GetStaticObjectAt(i);

    if (ImGui::TreeNode(object->GetName().c_str()))
    {
        // Material: Albedo, Roughness, Wireframe
        // Transform: Position, Rotation Axis, Rotation Angle, Scale, Auto Rotate
    }
}
```

Two hardcoded pointers become an arbitrarily long, named, browsable list, which is the difference between a scene you can only edit by recompiling and one you can edit while it's running.

## The Wireframe Toggle Goes Live

Last post's wireframe overlay had its color and edge width baked into the shader as constants. Both become uniforms with default values instead:

```glsl
uniform vec3  wireframeColor = vec3(0.0f, 0.0f, 0.0f);
uniform float wireframeWidth = 0.75f;
```

`Material` gains a matching flag, and `Mesh::SetMaterialProperties()` drives the shader's edge width from it:

```cpp
if (mat->m_bWireframe)
    glUniform1f(glGetUniformLocation(shaderID, "wireframeWidth"), 0.75f);
else
    glUniform1f(glGetUniformLocation(shaderID, "wireframeWidth"), 0.0f);
```

With the width at `0`, `edgeFactor()`'s `smoothstep()` threshold collapses to nothing and every fragment reads as fully interior, no wireframe. The Scene Objects panel exposes the flag as a plain checkbox:

```cpp
bool showWireframe = mat->m_bWireframe;
if(ImGui::Checkbox("Wireframe", &showWireframe))
    mat->m_bWireframe = showWireframe;
```

The barycentric math from last post hasn't changed at all, it's exactly the same `fwidth()`/`smoothstep()` edge test. What changed is who controls it: a shader constant became a per-object switch you can flip while the scene is rendering.

## The Directional Light Gets Real Rotation, and a Visible Frustum

`DirectionalLightObject` used to take its direction directly through `SetLightDirection()`. It now takes three rotation angles and derives the direction from them:

```cpp
void DirectionalLightObject::SetLightAngleXYZ(const glm::vec3& angleXYZ)
{
    m_vecLightAngleXYZ = angleXYZ;
    glm::mat4 rotateXYZ = glm::mat4(1);
    rotateXYZ = glm::rotate(rotateXYZ, glm::radians(m_vecLightAngleXYZ.z), glm::vec3(0, 0, 1));
    rotateXYZ = glm::rotate(rotateXYZ, glm::radians(m_vecLightAngleXYZ.y), glm::vec3(0, 1, 0));
    rotateXYZ = glm::rotate(rotateXYZ, glm::radians(m_vecLightAngleXYZ.x), glm::vec3(1, 0, 0));

    m_matWorld = rotateXYZ;
    m_vecLightDirection = glm::column(rotateXYZ, 1);

    glm::vec3 lightPosition = -m_vecLightDirection * 20.0f;
    m_matWorldToLightViewMatrix = glm::lookAt(lightPosition, glm::vec3(0.0, 0.0f, 0.0f), glm::vec3(0.0f, 1.0f, 0.0f));
}
```

$$
R = R_z(\theta_z)\, R_y(\theta_y)\, R_x(\theta_x), \qquad \text{lightDirection} = \text{column}_1(R).
$$

Composing the rotation as Z, then Y, then X and reading the light's direction back out of the resulting matrix's Y column means the Scene UI's `SliderFloat3("Rotation", ...)` can drive the sun by three intuitive angles instead of a raw direction vector.

The light's shadow frustum, near plane, far plane, and bounds, becomes visible too. `BBoxCube`, a new class built from the same eight-corner, edge-only geometry `GLLight` uses for its filled cube, gets instantiated as a wireframe volume matching the directional light's orthographic projection:

```cpp
m_pDebugShadowVolume = new BBoxCube(volumeData);
m_pDebugShadowVolume->Init();
```

Dragging the Scene UI's Bounds, Near Plane, or Far Plane sliders calls `UpdateBounds()`, which recomputes the eight corner positions and pushes them straight into the existing vertex buffer:

```cpp
m_pDebugShadowVolume = glMapBuffer(GL_ARRAY_BUFFER, GL_READ_WRITE);
memcpy(m_pDynamicVertData, vertices, sizeof(vertices));
glUnmapBuffer(GL_ARRAY_BUFFER);
```

The box you see on screen is the actual volume the shadow map's orthographic projection covers, so widening it, tightening it, or watching it clip through geometry is now something you do by dragging a slider instead of guessing from code.

## The Rest of the Panels

`RenderFPS()` gives the frame counter from a couple posts back an actual home, `ImGui::GetIO().Framerate` in its own small window, and `Application::Run()`'s console-printed version is gone. The Postprocess panel exposes a Bloom checkbox and a `Bloom Cutoff` slider tied to a new `fBloomThreshold` uniform, so the lighting pass only feeds a pixel into the bright buffer once its luminance crosses that threshold, rather than always passing emission through unconditionally. A Debug panel's `Draw G-Buffers` checkbox does the same job the commented-out `DrawDebugBuffers()` call has done manually for the last few posts, now a runtime switch instead of a recompile.

## What We Have Now

$$
\text{scattered std::cout/cerr} \;\rightarrow\; \text{one console panel}, \qquad \text{two hardcoded objects} \;\rightarrow\; \text{a named, editable list}.
$$

Nothing about how the engine renders changed this commit, the deferred pipeline, the shadow map, the wireframe edge test are all exactly what they were last post. What changed is how much of it you can see and touch without a rebuild: every log line, every object's material and transform, every light's rotation and shadow bounds, one shared window into a scene that used to only be legible by reading the source.
