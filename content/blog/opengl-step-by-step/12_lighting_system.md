+++
title = "Building a Lighting System: Point Lights Arrive, and Reflection Quietly Steps Aside"
date = 2019-12-26T18:03:00+05:30
tags = ["opengl", "rendering"]
description = "Introducing a LightsManager, PointLightObject, and visual GLLight marker cubes for a real multi-light system with per-light attenuation, and finding last post's reflection term computed and then commented out of the final sum."
math = true
+++

# Building a Lighting System: Point Lights Arrive, and Reflection Quietly Steps Aside

By the end of this post, the scene has three colored point lights instead of one fixed direction baked into a shader uniform, each with its own position, color, intensity, and a small glowing marker cube so you can actually see where it sits in the world. The mesh accumulates diffuse and specular contributions from all of them in a loop. It's the first time this series manages more than one light at a time, and the code that manages them is already shaped to hold a second kind of light it doesn't implement yet.

&nbsp;

{{< youtube 7T_qQnixc6M >}}

&nbsp;

$$
\text{one fixed lightDirection} \;\longrightarrow\; \text{array of point lights, accumulated per pixel}
$$

## A Cube Learns a New Job, Again

`GLLight` uses the exact same eight corners and thirty-six indices as `GLCube` from several posts back, `VertexPC`, the whole layout, unchanged. This time it's not the subject being rendered, it's a marker: a small cube, scaled down to `0.2`, dropped at a light's position so the light itself has something visible to sit inside.

```cpp
glm::mat4 T  = glm::translate(glm::mat4(1), position);
glm::mat4 TS = glm::scale(T, glm::vec3(0.2f, 0.2f, 0.2f));
matWorld = TS;
```

No rotation, just translation and a fixed small scale. Between `GLCube`, `GLSkybox`, and now `GLLight`, this is the third distinct job the same eight-vertex cube shape has been given in this series.

## A Light Object and a Manager to Track Them

`PointLightObject` pairs a `GLLight` with the actual light data, position, color, intensity, radius:

```cpp
PointLightObject::PointLightObject(const glm::vec4& color)
{
    m_vecLightPosition = glm::vec3(0);
    m_vecLightColor = color;
    m_fIntensity = 2.0f;
    m_fRadius = 50.0f;

    Init();
}
```

`LightsManager` is a new singleton that owns a growing list of them:

```cpp
void LightsManager::GatherPointLights(PointLightObject* obj)
{
    m_vecPointLights.push_back(obj);
    m_iNumPointLights = m_vecPointLights.size();
}
```

`RenderLights()` and `UpdateLights()` just walk that list and call `Render()` / `Update()` on each entry. What's more interesting is what's sitting there commented out. `LightsManager.h` and `.cpp` both carry an entire parallel structure for a `DirectionalLightObject` that doesn't exist yet, a forward declaration, a `m_vecDirLights` vector, `GatherDirectionalLights()`, `GetDirectionalLight()`, a count getter, every one of them written and immediately commented out. This "lighting system" was clearly scoped for more than point lights from the start; only one half of it showed up this commit.

## Uploading an Array of Lights

`Mesh::PointLightIlluminance()` walks the same list from the C++ side and uploads each light as an indexed struct in a uniform array:

```cpp
std::string pointLightPosStr = "pointLights[" + std::to_string(i) + "].position";
std::string pointLightColStr = "pointLights[" + std::to_string(i) + "].color";
std::string pointLightIntStr = "pointLights[" + std::to_string(i) + "].intensity";
std::string pointLightRadStr = "pointLights[" + std::to_string(i) + "].radius";

glUniform3fv(glGetUniformLocation(shaderID, pointLightPosStr.c_str()), 1, glm::value_ptr(position));
glUniform4fv(glGetUniformLocation(shaderID, pointLightColStr.c_str()), 1, glm::value_ptr(color));
glUniform1f(glGetUniformLocation(shaderID, pointLightIntStr.c_str()), intensity);
glUniform1f(glGetUniformLocation(shaderID, pointLightRadStr.c_str()), radius);
```

On the shader side, `psBasicLighting.glsl` matches that layout with a capped array:

```glsl
#define MAX_POINT_LIGHTS 8

struct PointLight
{
    float radius;
    float intensity;
    vec3 position;
    vec4 color;
};

uniform PointLight pointLights[MAX_POINT_LIGHTS];
```

Eight lights is the ceiling for now; the scene only uses three of them.

## Two Loops, One Per Light Property

`psBasicLighting.glsl` computes diffuse and specular contributions in two separate loops over the same `numPointLights`, rather than one loop doing both:

```glsl
for(int i = 0 ; i < numPointLights ; ++i)
{
    LightDir = normalize(vs_outPosition - pointLights[i].position);
    float dist = length(LightDir);
    float r = pointLights[i].radius;

    atten = 1 / dist; //(1 + ((2/r)*dist) + ((1/r*r)*(dist*dist)));

    NdotLPoint = max(dot(vs_outNormal, -LightDir), 0);
    DiffusePoint += pointLights[i].color * atten * NdotLPoint * pointLights[i].intensity;
}
```

$$
\text{DiffusePoint} = \sum_{i=0}^{n-1} \text{color}_i \cdot \frac{1}{d_i} \cdot \max(0,\ \hat{n}\cdot(-\hat{l}_i)) \cdot \text{intensity}_i.
$$

The attenuation in use, `1 / dist`, falls off with straight-line distance. Right next to it, commented out with a link to the blog post it came from, is a more complete inverse-square-style falloff that actually uses the light's `radius` to control how far it reaches. `r` is fetched from every light every loop iteration; the active formula never touches it. The specular loop below repeats the same structure, `reflect()` off each light's direction instead of one fixed direction, accumulated the same way.

## Reflection, Computed and Set Aside

Last post's whole feature is still in this shader. It's just not in the final sum:

```glsl
// Reflection
vec3 viewReflection = normalize(reflect(viewDir, vs_outNormal));
Reflection = texture(texture_skybox, viewReflection);

// control reflection
Reflection *= 0.3;

// Final Accumulation
outColor = Ambient * DiffusePoint + SpecularPoint;// + Reflection;
```

`Reflection` gets sampled from the skybox and scaled down exactly like it did last post, and then the line that would actually add it in is commented out at the end of `outColor`'s assignment. The mesh computes its own environment reflection every frame and throws the result away.

## Three Lights, Placed by Hand

`Source.cpp` creates three point lights directly in `main()`:

```cpp
PointLightObject ptRedLight(glm::vec4(1, 0, 0, 1));
ptRedLight.SetLightPosition(glm::vec3(2, 5, 5));
LightsManager::getInstance()->GatherPointLights(&ptRedLight);

PointLightObject ptGreenLight(glm::vec4(0, 1, 0, 1));
ptGreenLight.SetLightPosition(glm::vec3(5, 15, 0));
ptGreenLight.SetLightIntensity(5.0f);
LightsManager::getInstance()->GatherPointLights(&ptGreenLight);

PointLightObject ptBlueLight(glm::vec4(0, 0, 1, 1));
ptBlueLight.SetLightPosition(glm::vec3(-8, 15, 5));
ptBlueLight.SetLightIntensity(3.0f);
LightsManager::getInstance()->GatherPointLights(&ptBlueLight);
```

Red, green, and blue, scattered at different heights and intensities. All three live as ordinary local variables in `main()`, and `LightsManager` just stores their addresses, they stay valid for as long as `main()`'s loop keeps running. In the same commit, the `GLCube` fallback that's been commented out since the custom-mesh post, `//GLCube cube; //GLCube cube(glm::vec4(1,1,0,1)); //cube.Init();`, finally gets deleted outright instead of just sitting there.

## What We Have Now

$$
\text{outColor} = \text{Ambient} \cdot \sum_i \text{Diffuse}_i \;+\; \sum_i \text{Specular}_i \qquad (\text{Reflection: computed, unused}).
$$

Three point lights, each with a visible marker cube, a manager that already has room for a light type it hasn't built yet, and a reflection term sitting one uncommented character away from being back in the picture. The lighting system this post's title promises is real, it's just clearly not finished promising things.
