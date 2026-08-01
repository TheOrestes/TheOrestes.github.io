+++
title = "Cutting the Camera Loose: From a Fixed lookAt to WASD and Mouse Look"
date = 2019-11-08T18:03:00+05:30
tags = ["opengl", "rendering"]
description = "Replacing the cube's hardcoded lookAt view with a WASD-and-mouse free camera, handing brightColor its first real job, and giving the scene three cubes actually worth flying around to see."
math = true
+++

# Cutting the Camera Loose: From a Fixed lookAt to WASD and Mouse Look

By the end of this post, the camera stops being a single hardcoded `glm::lookAt()` call and becomes an actual object you can steer: WASD to move, mouse to look around. That's not a cosmetic upgrade. Every post so far has been staring at geometry from the exact same fixed vantage point, which was fine for one cube but stops being fine the moment a scene has more than one thing in it worth walking around, and this commit makes sure it does: three cubes now sit at three different positions instead of one spinning in place. A skybox, in a few steps, is going to need somewhere to fly through it.

&nbsp;

{{< youtube wXB-I-ThUhM >}}

&nbsp;

$$
\text{fixed } \texttt{lookAt()} \;\longrightarrow\; \text{Camera object (yaw, pitch, WASD, mouse)}
$$

## A Camera Class Enters

`Camera` is a new singleton, accessed the same way `TextureManager` used to be:

```cpp
static Camera& getInstance()
{
    static Camera instance;
    return instance;
}
```

Its constructor sets up a starting pose:

```cpp
Camera::Camera() :
    m_vecPosition(0,5,8),
    m_vecDirection(0,0,1),
    m_vecRight(1,0,0),
    m_vecUp(0,1,0),
    m_vecWorldUp(0,1,0),
    m_fYaw(-90.0f),
    m_fPitch(-5.0f),
    m_fSpeed(30.0f),
    m_fSensitivity(0.05f),
    m_fZoom(45.0f)
{
    Update();
}
```

The camera starts elevated and pulled back at \((0,5,8)\), which makes sense once you know the scene is about to gain a cube sitting up at \(y=2\). A camera parked at the origin's eye level wouldn't see much of it.

## From Yaw and Pitch to a Direction Vector

Position alone doesn't tell you which way a camera is looking. This class stores that as two angles, yaw and pitch, and rebuilds the look direction from them every time either one changes:

```cpp
glm::vec3 front;
front.x = cos(glm::radians(m_fYaw)) * cos(glm::radians(m_fPitch));
front.y = sin(glm::radians(m_fPitch));
front.z = sin(glm::radians(m_fYaw)) * cos(glm::radians(m_fPitch));

m_vecDirection = glm::normalize(front);
```

In other words,

$$
\mathbf{d} = \big(\cos(\text{yaw})\cos(\text{pitch}),\ \sin(\text{pitch}),\ \sin(\text{yaw})\cos(\text{pitch})\big), \qquad \hat{\mathbf{d}} = \frac{\mathbf{d}}{\lVert \mathbf{d} \rVert}.
$$

Yaw is rotation around the vertical axis, the "turn your head left or right" angle. Pitch is rotation around the horizontal axis, "tilt your head up or down." Plug the defaults in and the starting direction works out to roughly \((0, -0.087, -0.996)\): almost straight down the \(-z\) axis with a slight downward tilt, which lines up with every previous post's camera looking into the screen along \(-z\).

&nbsp;

Why \(-90^\circ\) yaw specifically? Because \(\cos(-90^\circ) = 0\), which zeroes out the \(x\) component and points the camera down \(-z\) instead of sideways down \(+x\), where a yaw of \(0^\circ\) would otherwise send it.

## Right, Up, and the Missing Roll

Direction alone isn't enough to build a view matrix; the camera also needs to know which way is "right" and which way is "up" relative to itself. Both come from cross products against a fixed world-up vector:

```cpp
m_vecRight = glm::normalize(glm::cross(m_vecDirection, m_vecWorldUp));
m_vecUp = glm::normalize(glm::cross(m_vecRight, m_vecDirection));
```

$$
\hat{\mathbf{r}} = \frac{\hat{\mathbf{d}} \times \mathbf{u}_{world}}{\lVert \hat{\mathbf{d}} \times \mathbf{u}_{world} \rVert}, \qquad \hat{\mathbf{u}} = \frac{\hat{\mathbf{r}} \times \hat{\mathbf{d}}}{\lVert \hat{\mathbf{r}} \times \hat{\mathbf{d}} \rVert}.
$$

`m_vecWorldUp` is a constant \((0,1,0)\) that never changes, which is exactly why there's no roll here: nothing in `Camera` ever tilts the world-up reference, so the camera can pan and tilt but can never bank sideways like a plane. That's a deliberate limitation of this two-angle setup, not a bug, it's the standard first-pass FPS camera, and rolling would need a third angle this class simply doesn't track yet.

## Moving the Camera: WASD

`ProcessKeyboard()` nudges position along direction or right, scaled by speed and delta time:

```cpp
float speed = m_fSpeed * dt;

switch (mov)
{
case FORWARD: m_vecPosition += m_vecDirection * speed; break;
case BACK:    m_vecPosition -= m_vecDirection * speed; break;
case LEFT:    m_vecPosition -= m_vecRight * speed;     break;
case RIGHT:   m_vecPosition += m_vecRight * speed;     break;
}
```

`Source.cpp` wires this to WASD inside `KeyHandler()`:

```cpp
if (key == GLFW_KEY_W && (action == GLFW_REPEAT || GLFW_PRESS))
{
    Camera::getInstance().ProcessKeyboard(CameraMovement::FORWARD, tick);
}
```

The same pattern repeats for `A`, `S`, and `D`, each mapped to its own `CameraMovement` value.

## Looking Around: the Mouse

`MouseHandler()` in `Source.cpp` tracks the cursor and feeds the delta to the camera:

```cpp
GLfloat xoffset = xPos - lastX;
GLfloat yoffset = lastY - yPos;
lastX = xPos;
lastY = yPos;

Camera::getInstance().ProcessMouseMovement(xoffset, yoffset);
```

`yoffset` is deliberately flipped (`lastY - yPos` instead of `yPos - lastY`) because screen coordinates grow downward while the camera's pitch should increase as the mouse moves up. `bFirstMouse` exists so the very first mouse event doesn't compute a huge offset from an uninitialized `lastX`/`lastY`; it seeds them from the current cursor position once, then gets out of the way.

&nbsp;

Inside the camera, the offsets are scaled by sensitivity and added straight onto yaw and pitch:

```cpp
xOffset *= m_fSensitivity;
yOffset *= m_fSensitivity;

m_fYaw += xOffset;
m_fPitch += yOffset;

if (bConstraintPitch)
{
    if (m_fPitch > 89.0f)  m_fPitch = 89.0f;
    if (m_fPitch < -89.0f) m_fPitch = -89.0f;
}

Update();
```

Clamping pitch to \(\pm 89^\circ\) instead of a full \(\pm 90^\circ\) avoids the direction vector's \(y\) component hitting exactly \(\pm 1\), which is the classic gimbal-flip pole where yaw suddenly stops meaning anything. One caveat worth knowing: `main()` sets `glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_NORMAL)`, not `GLFW_CURSOR_DISABLED`. The cursor stays visible and unlocked, so mouse-look works, but nothing recenters the pointer, and it can wander off the window edge.

## GLCube Finally Asks the Camera

`GLCube::Update()` used to build its own view and projection matrices from scratch every frame. Now it just asks:

```cpp
matView = Camera::getInstance().getViewMatrix(); //glm::lookAt(glm::vec3(0,0,5), glm::vec3(0,0,0), glm::vec3(0,1,0));	
matProj = Camera::getInstance().getProjectionMatrix(); //glm::perspective(45.0f, 1.6f, 0.1f, 1000.0f);
```

The old lines were commented out rather than deleted, and the second comment is quietly wrong: the code it's supposedly preserving actually called `glm::perspectiveFovRH(45.0f, gWindowWidth, gWindowHeight, 0.1f, 1000.0f)` in the previous post, not `glm::perspective(45.0f, 1.6f, ...)` with a hardcoded aspect ratio. Harmless, since the old line isn't running anymore either way, but a small reminder that comments drift out of sync with code faster than either author usually notices.

## Wireframe Mode Gets Logic, Loses Its Switch

`GLCube::Init()` finally does something with the wireframe flag that's been sitting unused since the very first post:

```cpp
if (m_bWireframe)
    glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
```

In the same commit, `GLCube.h` deletes `void SetWireframe(bool flag);` from the public interface. `m_bWireframe` is still a private member, still initialized to `false` in both constructors, but there is no longer any way from outside the class to set it to `true`. The check now works; nothing can reach it. This is the same flavor of quiet dead end the rotation setter turned out to be last post, just relocated.

## Bloom's First Ingredient

`ps.glsl` finally gives `brightColor`, declared and unused since the very first post, something to compute:

```glsl
float brightness = dot(outColor.rgb, vec3(0.2126f, 0.7152f, 0.0722f));
if (brightness > 1.0f)
    brightColor = vec4(outColor.rgb, 1.0f);
```

That weighted dot product is the standard Rec. 709 luminance formula,

$$
L = 0.2126\,R + 0.7152\,G + 0.0722\,B,
$$

and thresholding it against \(1.0\) is the first ingredient of a bloom pass: find the pixels bright enough to glow, route them somewhere separate. Two things keep this from doing anything visible yet. First, the vertex colors in play are still the flat debug palette from two posts ago, red \((1,0,0)\), green \((0,1,0)\), blue \((0,0,1)\), yellow \((1,1,0)\), and the brightest of those, yellow, has \(L = 0.2126 + 0.7152 = 0.9278\), which never clears the \(1.0\) threshold. Second, even if it did, there's still no second render target or framebuffer configured anywhere in this commit for `brightColor` to actually land in. The guest has a job description now; the venue still doesn't exist.

## Three Cubes Now

`Source.cpp` stops building one multicolored cube and builds three flat-colored ones instead:

```cpp
GLCube cube(glm::vec4(1,1,0,1));
GLCube cube2(glm::vec4(1,0,0,1));
GLCube cube3(glm::vec4(0,1,0,1));
cube.Init();
cube2.Init();
cube3.Init();

cube2.SetPosition(glm::vec3(-3,0,0));
cube3.SetPosition(glm::vec3(3,2,0));
cube3.SetScale(glm::vec3(1.2));
```

Yellow in the middle, red off to the left, green up and to the right and slightly larger. All three now update and render with the shared `tick` constant instead of a hardcoded `0.016f` sprinkled around by hand. None of this changes what a cube looks like up close, but it finally gives the new free camera something worth flying between.

## What We Have Now

A running theme in this commit: a lot of things get *set up* without being fully *switched on*. `brightColor` has math but no framebuffer to write into. `m_fZoom` exists and feeds the projection matrix, but nothing calls `ProcessMouseScroll()` yet, no scroll callback is even registered, so the field is permanently \(45^\circ\). `assimp` and `stb` are linked but uncalled. The one piece that is fully switched on is the camera itself:

$$
\text{keyboard} \rightarrow \text{position} \qquad \text{mouse} \rightarrow \text{yaw, pitch} \qquad (\text{position}, \text{yaw}, \text{pitch}) \rightarrow \text{view matrix}.
$$

The scene finally has somewhere to walk, three cubes to walk between, and a small pile of scaffolding, bloom, zoom, mesh loading, quietly waiting for the posts that will actually turn it on.
