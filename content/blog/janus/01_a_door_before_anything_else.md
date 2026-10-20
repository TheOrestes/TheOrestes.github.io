+++
title = "Janus: A Door Before Anything Else"
date = 2026-10-20T19:00:00+05:30
tags = ["janus", "d3d12", "cmake", "cpp"]
description = "Starting the Janus renderer over from nothing: a CMake skeleton, logging, a window, input, math conventions, asset paths, and a D3D12 device that picks the right GPU."
math = false
+++

I have rewritten this renderer more times than I would like to admit.

&nbsp;

The old repo has a branch list that reads like a graveyard: `RTX`, `HPC_Tracer`, `Simple_Base`, `Simple_Compute`, `Simple_Forward`, `Simple_AVX`, `ML`. Roughly eight restarts. The one that got furthest is the one that built on top of old scaffolding instead of replacing it, which is a lesson I am choosing to ignore, because this restart is deliberate.

&nbsp;

This time the goal is not a running renderer. It is understanding. I wrote a working D3D12 renderer over about two years, and then went rusty enough that I could not explain half my own design choices. So Janus is a rewrite on purpose, because a rewrite forces me back through every concept, and the concepts are the point.

## Why "Janus"

Janus is the two-faced Roman god of doorways and beginnings. One head, two faces looking in opposite directions.

&nbsp;

That is the architecture: one renderer, one abstraction layer, two backends. D3D12 first, Vulkan second, and **bindless on both**. The god of beginnings also suits a restart. If the design ever drifts far enough that the name stops describing it, something has gone wrong.

&nbsp;

Before any code, there were a few decisions to make:

- **Math:** DirectXMath
- **Build system:** CMake
- **Dependencies:** CMake `FetchContent`, no submodules
- **Engine as a DLL?** No, a static library
- **Root namespace:** `JN`, because it gets typed constantly

&nbsp;

And one rule that does most of the work: **no file outside `RHI/D3D12/` or `RHI/Vulkan/` may include a graphics API header.** The old engine let `d3d12.h` leak into the scene and the camera because one header became the dumping ground for anything global. This time the boundary is written down before there is anything to violate it.

![Janus is a static library with an executable on top. Core has no graphics headers. The D3D12 backend is the only place d3d12.h appears, and the Vulkan folder is drawn dashed because it does not exist yet.](/images/blog/janus/janus_layers.svg)

## A build that does nothing

The first milestone ended with an empty executable. That was the goal: `cmake --build` produces a `.exe` that does nothing.

&nbsp;

The top-level `CMakeLists.txt` is small, and I commented it heavily on purpose, because CMake is the one tool where I forget the reason for a line the moment I look away:

```cmake
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
```

&nbsp;

`REQUIRED ON` means no silent fallback to an older standard if the compiler balks. `EXTENSIONS OFF` means standard C++20 rather than a compiler-specific dialect.

&nbsp;

Dependencies come in through `FetchContent`, with tags pinned:

```cmake
FetchContent_Declare(spdlog
    GIT_REPOSITORY https://github.com/gabime/spdlog.git
    GIT_TAG        v1.15.3
    GIT_SHALLOW    TRUE)
FetchContent_MakeAvailable(spdlog)
```

&nbsp;

GLFW gets the same treatment, with a handful of `GLFW_BUILD_*` options switched off first. Those have to be set **before** `MakeAvailable`, because that call is what reads them. Set them after and CMake happily builds the examples you told it you did not want.

&nbsp;

The order of the last two lines matters too: `Sandbox` links against `Janus`, so `Janus` has to be defined first.

```cmake
add_subdirectory(Janus)   # the engine, built as a static library
add_subdirectory(Sandbox) # the test application
```

## Logging that stops the program

The second milestone was logging and assertions. The old engine had a vocabulary I liked, so it came along: spdlog behind `JN_LOG_*` macros, plus two check macros.

```cpp
// Always on. Logs, then breaks into the debugger.
#define JN_CHECK(cond, ...)                          \
    do                                               \
    {                                                \
        if (!(cond))                                 \
        {                                            \
            JN_LOG_FATAL("CHECK failed: {}", #cond); \
            JN_LOG_FATAL(__VA_ARGS__);               \
            __debugbreak();                          \
        }                                            \
    } while (0)
```

&nbsp;

`JN_CHECK` is always on, in every build. `JN_ASSERT` is the same thing but compiles to `((void)0)` when `NDEBUG` is set. The split is the point: a check guards something that can fail in production (a file that is missing, an API call that returns an error), and an assert documents something that can only fail if I wrote a bug.

&nbsp;

Note what `JN_CHECK` does **not** do. It does not throw, and it does not abort. It breaks into the debugger and then falls through, so if you press continue the program keeps running in a state it should not be in. That is deliberate for a learning project where I am always attached to a debugger, and it is not what you would ship.

## A window with no API

Next, a window. GLFW does the platform work, with one hint that matters for a renderer:

```cpp
// No OpenGL context: D3D12/Vulkan create their own swapchain for this window.
glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
m_pHandle = glfwCreateWindow(width, height, title, nullptr, nullptr);
```

&nbsp;

By default GLFW creates an OpenGL context for every window. `GLFW_NO_API` tells it not to, which leaves the window as a plain native window that D3D12 or Vulkan can attach a swapchain to later.

&nbsp;

GLFW reports failures only through a callback, so the very first thing the constructor does is route that callback into the log. A window that silently fails to open is a great way to lose an afternoon.

## Input stops at the boundary

The old engine had one input idea worth keeping, and I kept it: **GLFW key codes get translated once, at the edge, and never appear again.**

```cpp
enum class InputAction
{
    Quit,
    MoveForward,
    MoveBack,
    MoveLeft,
    MoveRight
};

bool IsActionDown(const Window& window, InputAction action);
```

&nbsp;

`Input.h` has no GLFW in it. The only place that knows `W` is `GLFW_KEY_W` is a `static` function in `Input.cpp`:

```cpp
static int ToKey(InputAction action)
{
    switch (action)
    {
        case InputAction::Quit:        return GLFW_KEY_ESCAPE;
        case InputAction::MoveForward: return GLFW_KEY_W;
        // ...
    }
    return GLFW_KEY_UNKNOWN;
}
```

&nbsp;

This version is a polling model: ask whether an action is down right now, with `glfwGetKey`. It is stateless and tiny. It also cannot tell you that a key was *just* pressed this frame, which a jump button will eventually want, and when that day comes the fix lives in this one file.

![A W key press becomes GLFW_KEY_W, then ToKey maps it to InputAction::MoveForward. Only the left side of the boundary knows GLFW exists.](/images/blog/janus/janus_input_boundary.svg)

## Writing the math rules down

The fourth milestone produced no behavior at all, just a header with a comment block:

```cpp
//   Handedness      left-handed, Y up, +Z forward, +X right
//   Vectors         row vectors, transform with v * M (reads left to right:
//                   world * view * proj)
//   Matrix storage  row-major; the CPU uses XMFLOAT4X4. HLSL must declare
//                   #pragma pack_matrix(row_major) and use mul(v, M), so no
//                   transpose is needed between CPU and shader
//   UV origin       top-left, v increases downward (D3D style)
//   Depth           clip-space z in 0..1 (D3D12 and Vulkan agree)
```

&nbsp;

None of that is clever. All of it is a bug waiting to happen if it lives only in my head. A matrix that is transposed relative to what the shader expects does not crash, it just draws the wrong thing, and it takes a very long time to notice that "wrong" is a transpose. The rule is simple: change the convention in this header first, then everywhere else.

&nbsp;

The line I want future me to read twice is the last one. D3D12 and Vulkan agree on a `0..1` depth range, which is one fewer thing to reconcile when the second face turns up. They disagree about which way Y points in NDC, and that is a problem for another day.

## Assets next to the exe

Fifth and last of the foundation milestones: finding files. The rule is that assets are copied next to the executable after every build and resolved against the executable's location, never the current working directory.

```cpp
std::filesystem::path GetAssetPath(const std::filesystem::path& relative)
{
    return GetExecutableDirectory() / "Assets" / relative;
}
```

&nbsp;

Launch the exe from Visual Studio, from a terminal, or by double-clicking it, and `Assets/test.txt` is found in all three. The old engine did this too, and it never once caused a problem.

&nbsp;

The one known corner is `GetModuleFileNameW` with a `MAX_PATH` buffer. A path over 260 characters trips the `JN_CHECK` instead of quietly truncating, which I would rather have than the alternative.

## The actual D3D12 part

That was Phase A: no graphics API anywhere. Phase B starts the real thing, and the first milestone is just getting a device.

&nbsp;

It is a short function, and the order of the lines is most of what there is to learn:

```cpp
void Init()
{
    EnableDebugLayer();

    JN_CHECK_HRESULT(CreateDXGIFactory2(DXGI_CREATE_FACTORY_DEBUG,
                                        IID_PPV_ARGS(&G_pFactory)));

    IDXGIAdapter1* pAdapter = PickAdapter();
    JN_CHECK_HRESULT(D3D12CreateDevice(pAdapter, D3D_FEATURE_LEVEL_12_0,
                                       IID_PPV_ARGS(&G_pDevice)));
    EnableBreakOnError();
    SafeRelease(pAdapter);
}
```

![Core::Init in order: debug layer, DXGI factory with the debug flag, adapter pick, device creation, break on error.](/images/blog/janus/janus_d3d12_init.svg)

&nbsp;

**The debug layer comes first.** Enabling it after the device exists makes the runtime remove the device, so it has to be on before `D3D12CreateDevice` is ever called. I turn on GPU-based validation too, which instruments shaders at runtime to catch bad resource access. It is slow, and I want it on from the very first line anyway, because developing with validation off is how bugs get baked in.

```cpp
G_pDebug->EnableDebugLayer();
G_pDebug->SetEnableGPUBasedValidation(TRUE);
```

&nbsp;

Right now GPU-based validation has nothing to validate, because the program submits no GPU work at all. It is switched on early so that the first command list I ever record is already being watched.

### Index 0 is not the GPU you want

My laptop has two adapters: an NVIDIA RTX 3080 and an Intel integrated GPU. Asking for adapter 0 and hoping is exactly how you end up benchmarking the wrong chip. The fix is to ask DXGI for what I actually want:

```cpp
JN_CHECK_HRESULT(G_pFactory->EnumAdapterByGpuPreference(
    0, DXGI_GPU_PREFERENCE_HIGH_PERFORMANCE, IID_PPV_ARGS(&pAdapter)));
```

&nbsp;

`EnumAdapterByGpuPreference` returns adapters sorted by the preference, so index 0 now means "the fastest one". The adapter name and dedicated VRAM go into the log, which turned out to be the cheapest possible way to confirm the right chip was picked.

&nbsp;

One shortcut worth owning up to: the adapter name is a wide string, and I convert it with `std::filesystem::path(desc.Description).string()`. It is fine for GPU names, which are plain ASCII, and it is not a conversion I would trust with arbitrary text.

### Making errors impossible to ignore

The last line of `Init` makes the debug layer loud:

```cpp
pQueue->SetBreakOnSeverity(D3D12_MESSAGE_SEVERITY_CORRUPTION, TRUE);
pQueue->SetBreakOnSeverity(D3D12_MESSAGE_SEVERITY_ERROR, TRUE);
```

&nbsp;

Without this, the debug layer writes complaints to the output window and carries on, and the complaints scroll away unread. With it, the first real error stops the program in the debugger, right at the call that caused it.

### Shutdown runs the other way

```cpp
pDebugDevice->ReportLiveDeviceObjects(D3D12_RLDO_DETAIL | D3D12_RLDO_IGNORE_INTERNAL);
```

&nbsp;

Before releasing the device, `Shutdown` asks the debug device to list every object still alive. Right now the answer should be "none", and checking it from day one means the first leak shows up on the day it is introduced, not twenty milestones later.

## What is still missing

There is a lot of Phase A and B1 that is deliberately unfinished, and I would rather list it than hide it:

- **No window resize or minimize handling.** The old engine logged a message and did nothing for years. The plan this time is to design size-dependent resources as a create/destroy pair from the first milestone that has a swapchain.
- **Feature level 12_0.** Enough for now, but not what Enhanced Barriers will need. That comes with the Agility SDK, which is the next decision.
- **Globals.** The D3D12 device lives in namespace-level globals (`G_pDevice`, `G_pFactory`). That is deliberate for the raw bring-up phase. The abstraction gets extracted later, from working code, not designed up front.
- **No GPU work.** The device exists and nothing uses it. That changes next.

&nbsp;

The next post gets a swapchain, a command queue, and a window that turns a solid color. Before that, there is a pile of new ideas to get straight: what a command queue actually is, what a barrier tells the driver, and why I am going to use Enhanced Barriers instead of the legacy resource states. I am going to write the concepts down before I write the code.

## GitHub Link
[Janus repo](https://github.com/TheOrestes/Janus)
