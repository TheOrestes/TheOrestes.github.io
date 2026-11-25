+++
title = "Janus: A Queue, a Fence and a Rulebook"
date = 2026-11-25T18:00:00+05:30
tags = ["janus", "d3d12", "cmake", "cpp", "agility-sdk"]
description = "Giving the D3D12 device something to talk to: a command queue, a fence, named loggers that also carry the debug layer's messages, and the Agility SDK that Enhanced Barriers need. Concepts first."
math = true
+++

Post 01 ended with a device that existed and did nothing. This one gives it a mouth and an ear: a command queue to hand work to, and a fence to find out when the work is done. Nothing is drawn yet. I promised the concepts before the code, so the concepts come first.

## Concepts: the CPU and the GPU are two timelines

Calling a D3D12 function does not run anything. It either records a command into a buffer or submits that buffer. The GPU runs it later, on its own clock.

&nbsp;

So the CPU can be a frame or two ahead of the GPU, recording frame N+1 while the GPU is still busy with frame N. That overlap is the whole reason the API is built this way, and it has a price: anything the GPU might still be reading (a buffer, the memory a command list was written into) must not be changed or freed by the CPU until the GPU is finished with it.

![The CPU records frame 0, 1, 2 one after the other. The GPU runs each frame after the CPU has recorded it, so it trails the CPU by about one frame.](/images/blog/janus/janus_cpu_gpu_timeline.svg)

&nbsp;

The price in latency is easy to work out in plain words. If the CPU is allowed to run $F$ frames ahead, then what you see on screen is up to $F$ frames old. At 60 frames per second a frame lasts about 16.67 ms, so:

$$\text{extra delay} \approx F \times 16.67\ \text{ms}$$

&nbsp;

Two frames ahead is about 33 ms. More frames in flight means fewer stalls and more lag, and the dial is mine to set.

### The restaurant version

You are the waiter. The GPU is the cook. You write orders on cards and drop them in the order slot, and then you walk away. You do not stand there while the food cooks.

&nbsp;

- **The order slot** is the command queue.
- **The cards** are the commands, written into a command list.
- **The tray the cards sit on** is the command allocator, the memory the commands live in. The cook reads off that tray while cooking, so you cannot wipe it until the cook is done with it.
- **The scoreboard on the wall** is the fence: one number that only goes up.

&nbsp;

After each batch of cards you add one more card that says "when you get here, write 4 on the scoreboard". The cook works in order, so a 4 on the board means everything before that card is cooked. To find out, you glance at the board. If it is not there yet, you take a nap and ask to be woken when it shows 4.

### The command queue

A queue is the GPU's inbox. It does two things: it accepts closed command lists (`ExecuteCommandLists`) and it accepts fence signals (`Signal`). There are three kinds, `DIRECT` (graphics, compute and copy), `COMPUTE` and `COPY`. Janus uses `DIRECT` for now, because one queue that can do everything is the simplest thing that works.

&nbsp;

There are three objects involved in recording and submitting, and the allocator is the one people trip on. A command list can be reset and reused the moment it has been submitted. Its allocator cannot, because the GPU reads the allocator's memory while it executes. That is why a renderer ends up with one allocator per frame in flight. None of those exist yet, but it is worth saying now so the shape of the fence code makes sense.

### The fence

A fence is a 64-bit counter that the GPU can raise and the CPU can read. The CPU owns a second number alongside it, the value it wants to see next.

![A queue holds batches of work with Signal commands between them. When the GPU passes Signal 1, the fence counter becomes 1, which tells the CPU everything before that point is finished.](/images/blog/janus/janus_fence.svg)

&nbsp;

Four calls cover the whole idea:

&nbsp;

- `queue->Signal(fence, N)`: "after everything before this, set the counter to N". It is itself a queue command, so it lands after the work it follows.
- `fence->GetCompletedValue()`: what the GPU has reached so far.
- `fence->SetEventOnCompletion(N, e)`: raise an operating system event when the counter reaches N.
- `WaitForSingleObject(e)`: the CPU sleeps until that event fires.

&nbsp;

Two rules. Check `GetCompletedValue()` first, because if the GPU is already there then waiting at all is wasted effort. And fence values only ever go up, never reused, because a counter that can go backwards cannot tell you anything.

### Frames in flight

With one frame in flight the CPU records frame N, the GPU runs it, the CPU waits, and only then does it record N+1. Simple, but one side is always idle. With two, the CPU records N+1 while the GPU runs N, and neither sits waiting.

![The CPU records frames 0 to 3 while the GPU runs them one step behind. Record 2 reuses the first slot, so it starts only once Run 0 is done and the fence has reached 1.](/images/blog/janus/janus_frames_overlap.svg)

&nbsp;

Each slot owns its own allocator, because the GPU may still be reading slot 0 while the CPU works on slot 1. Before reusing a slot, wait for the fence value that slot was tagged with last time, **not** the value the new frame is about to signal. Frame 2 reuses slot 0, so it waits for 1, which frame 0 signalled. Waiting for 3 would deadlock, because 3 is only signalled after frame 2's own work, and that has not been submitted yet.

![Frames alternate between slot 0 and slot 1. Frame 2 reuses slot 0 and waits for fence value 1 from frame 0. Frame 3 reuses slot 1 and waits for value 2 from frame 1.](/images/blog/janus/janus_frame_slots.svg)

&nbsp;

Janus will start with two. More frames means fewer stalls and more lag, as the timeline earlier showed.

### Barriers: three questions, not one

The GPU is not one processor reading one memory. It is many units (the rasterizer, shader cores, copy engines, the display) with their own caches, running in parallel and often out of order. Submitting command A and then command B does not mean B starts after A finishes. A barrier is the rule that fixes that, and it answers three separate questions at once.

![A barrier sits between earlier and later work. Sync decides when the later work may start, access decides whose writes must be visible, layout decides how the bytes are arranged for the next user.](/images/blog/janus/janus_barrier.svg)

&nbsp;

- **Sync: when may the later work start?** This is scheduling. The later stage waits until the earlier stage has finished.
- **Access: whose writes must the later work see?** This is caches. The writer's cache is flushed and the reader's cache is invalidated, so the reader does not look at stale data.
- **Layout: how are the bytes arranged?** This is only for textures. The same texture can be stored in different internal formats depending on who uses it next. Rendering is happy with a compressed, tiled arrangement. The display engine wants a plain one it can scan out.

&nbsp;

The third one is why a fence alone is not enough. A fence says "that work is done". It says nothing about how the memory is laid out for the next user.

### Legacy states versus Enhanced Barriers

Old D3D12 had one combined idea, `D3D12_RESOURCE_STATES`. A value like `RENDER_TARGET` meant sync, cache and layout all at once, and the driver guessed the rest, often by waiting longer than it needed to. Enhanced Barriers pull the three apart into separate fields, each with a before and an after:

&nbsp;

| D3D12 Enhanced | Vulkan 1.3 |
|---|---|
| `SyncBefore` / `SyncAfter` | `srcStageMask` / `dstStageMask` |
| `AccessBefore` / `AccessAfter` | `srcAccessMask` / `dstAccessMask` |
| `LayoutBefore` / `LayoutAfter` | `oldLayout` / `newLayout` |

&nbsp;

That near one to one mapping is the reason Janus uses them. There is a Vulkan face coming, and I would rather learn one vocabulary than two. The rule of thumb for filling them in: **Before describes the previous user of the resource, After describes the next one.** Reverse them and the debug layer will tell you off.

&nbsp;

The example I will need next post is the swapchain back buffer, which has two users each frame, the renderer and the display, so it needs two barriers:

&nbsp;

| Barrier | Sync | Access | Layout |
|---|---|---|---|
| Before drawing | `NONE` to `RENDER_TARGET` | `NO_ACCESS` to `RENDER_TARGET` | `PRESENT` to `RENDER_TARGET` |
| Before present | `RENDER_TARGET` to `NONE` | `RENDER_TARGET` to `NO_ACCESS` | `RENDER_TARGET` to `PRESENT` |

&nbsp;

Skip the first and the GPU writes into a layout meant for the display. Skip the second and the display may read a cache that was never flushed.

## Enhanced Barriers need the Agility SDK

Here is the catch. Enhanced Barriers are not in the D3D12 runtime that ships with Windows. They live in the Agility SDK, a side-by-side runtime (`D3D12Core.dll`) that the exe can load instead of the system one. The upside is that new D3D12 features arrive without waiting for a Windows update. The downside is three deployment rules.

&nbsp;

First, get the package. It is a NuGet package, which is just a zip, so it is fetched at configure time like every other dependency, with the version pinned:

```cmake
FetchContent_Declare(agility
    URL           https://www.nuget.org/api/v2/package/Microsoft.Direct3D.D3D12/1.620.1
    DOWNLOAD_NAME agility.zip)
FetchContent_MakeAvailable(agility)
# Not a CMake project, so only agility_SOURCE_DIR is defined, no target.
```

&nbsp;

`DOWNLOAD_NAME` exists only to force a `.zip` extension, because CMake decides whether to unpack by looking at the name.

&nbsp;

Second, copy the DLLs next to the exe, into a `D3D12` folder. The debug layer DLL has to come from the same package as the runtime, or the debug layer fails to load:

```cmake
add_custom_command(TARGET Sandbox POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory $<TARGET_FILE_DIR:Sandbox>/D3D12
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            ${agility_SOURCE_DIR}/build/native/bin/x64/D3D12Core.dll
            ${agility_SOURCE_DIR}/build/native/bin/x64/d3d12SDKLayers.dll
            $<TARGET_FILE_DIR:Sandbox>/D3D12)
```

&nbsp;

Third, tell the loader which runtime to use. It looks for two exported symbols in the exe:

```cpp
extern "C"
{
    __declspec(dllexport) extern const UINT D3D12SDKVersion = 620;
    __declspec(dllexport) extern const char* D3D12SDKPath = ".\\D3D12\\";
}
```

&nbsp;

Package `1.620.1` ships SDK version `620`, and the number in the exe must match. A mismatch makes `D3D12CreateDevice` fail or, worse, quietly use the system runtime and leave you wondering why barriers are missing.

&nbsp;

Even with all of that, the GPU driver has to support Enhanced Barriers too. So the device checks, and refuses to continue if the answer is no:

```cpp
static void RequireEnhancedBarriers()
{
    D3D12_FEATURE_DATA_D3D12_OPTIONS12 options12 = {};
    JN_CHECK_HRESULT(G_pDevice->CheckFeatureSupport(
        D3D12_FEATURE_D3D12_OPTIONS12, &options12, sizeof(options12)));
    JN_CHECK(options12.EnhancedBarriersSupported,
             "Enhanced Barriers not supported: check the Agility SDK export/D3D12 folder and the GPU driver");
    JN_LOG_INFO("Enhanced Barriers: supported");
}
```

&nbsp;

There is a small tension I should own up to. The device is still created at feature level 12_0, which is what it was last time, and the barrier support is checked separately through a feature query. That works, and the check is the real gate, but it is a thing to revisit when the abstraction gets extracted.

## The command queue and the fence, in code

With the concepts down, the code is short. The queue is a description with one meaningful field:

```cpp
static void CreateCommandQueue()
{
    D3D12_COMMAND_QUEUE_DESC desc = {};
    desc.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
    desc.Flags = D3D12_COMMAND_QUEUE_FLAG_NONE;

    JN_CHECK_HRESULT(G_pDevice->CreateCommandQueue(&desc, IID_PPV_ARGS(&G_pCommandQueue)));
    JN_LOG_DEBUG("Command Queue created...");
}
```

&nbsp;

The fence starts at zero, and next to it lives a Windows event for the CPU to sleep on:

```cpp
static void CreateFence()
{
    JN_CHECK_HRESULT(G_pDevice->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&G_pFence)));
    JN_LOG_DEBUG("Fence created...");

    G_hFenceEvent = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    JN_CHECK(G_hFenceEvent != nullptr, "CreateEventW failed!");
}
```

&nbsp;

Three small functions then do everything the restaurant needed. `SignalFence` adds one to the CPU's counter, puts that number on the queue, and hands it back, so the caller knows which number to wait for:

```cpp
UINT64 SignalFence()
{
    ++G_uiFenceValue;

    JN_CHECK_HRESULT(G_pCommandQueue->Signal(G_pFence, G_uiFenceValue));
    return G_uiFenceValue;
}
```

&nbsp;

`WaitForFence` is the glance at the scoreboard, with the early-out from the rules above:

```cpp
void WaitForFence(UINT64 uiValue)
{
    if (G_pFence->GetCompletedValue() >= uiValue)
    {
        return;
    }

    JN_CHECK_HRESULT(G_pFence->SetEventOnCompletion(uiValue, G_hFenceEvent));
    WaitForSingleObject(G_hFenceEvent, INFINITE);
}
```

&nbsp;

And `WaitIdle` is the two of them glued together, "put a new number on the board and wait for it", which means "wait until the GPU has finished everything I ever gave it":

```cpp
void WaitIdle()
{
    WaitForFence(SignalFence());
}
```

&nbsp;

The only caller so far is `Shutdown`, and that is the closing-time rule from the restaurant. You do not take the stove away while the cook is still cooking:

```cpp
void Shutdown()
{
    WaitIdle();

    CloseHandle(G_hFenceEvent);
    G_hFenceEvent = nullptr;
    SafeRelease(G_pFence);

    SafeRelease(G_pCommandQueue);
```

&nbsp;

Right now the GPU has nothing to finish, so `WaitIdle` returns almost instantly. It is there so that the day the queue has real work in it, the shutdown is already correct. `INFINITE` on the wait is also a choice I know is rude: if the GPU hangs, so does the program. Fine for development, not what I would ship.

### A window handle for later

One tiny change rides along. A swapchain needs the native window handle (`HWND`), and the queue is what the swapchain is created from, so both are about to meet. `Window` gets a getter:

```cpp
void* GetNativeHandle() const; // the Win32 HWND, as void* so this header stays free of windows.h
```

&nbsp;

It returns `void*` on purpose. The rule from post 01 was that no header outside the backend folders includes a graphics or platform header, and `windows.h` counts. The cast to `HWND` happens in the one file that is allowed to know.

## Logging that knows who is talking

The other half of this phase was not about the GPU at all. Once the debug layer is on and breaking into the debugger, I wanted its complaints in the same place as everything else, and I wanted to tell at a glance whether a line came from the engine, the app or D3D12.

&nbsp;

So there are now three named loggers, `JANUS`, `APP` and `D3D12`, and two sinks they all share: a coloured console and a plain `janus.log` file.

![Three loggers, JANUS, APP and D3D12, feed the same two sinks. The console gets colour codes, the log file gets plain text, and the log file is wiped each run.](/images/blog/janus/janus_logging.svg)

&nbsp;

The setup is a handful of lines. One thing I got wrong first: the formatter has to be set after the loggers are registered, because registering a logger resets its sinks' formatter. The comment in the code is there so I do not learn that twice.

```cpp
G_pEngineLogger = MakeLogger("JANUS", sinks);
G_pAppLogger    = MakeLogger("APP",   sinks);
G_pD3D12Logger  = MakeLogger("D3D12", sinks);

// Set after the loggers exist: registering a logger resets its sinks' formatter.
// Each sink gets its own formatter (console coloured, file plain) and the loggers
// share them.
pConsole->set_formatter(MakeFormatter("\x1b[90m%T\x1b[0m %* %k %&%v\x1b[0m", true));
pFile->set_formatter(MakeFormatter("%T %* %k %v", false));
```

&nbsp;

The pattern strings use three custom flags I wrote: `%*` for the source badge, `%k` for the bracketed level tag, and `%&` to start the message colour. Each takes a "colour on or off" switch, so the same pattern prints coloured text on the console and nothing but the words in the file. A log file full of escape codes is unreadable, and I have been bitten by that.

&nbsp;

The console needs one Windows-specific nudge before it understands any of it:

```cpp
const HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
DWORD mode = 0;
if (GetConsoleMode(hOut, &mode))
{
    SetConsoleMode(hOut, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING); // lets the console read ANSI colour codes
}
```

### Routing the debug layer into it

The D3D12 debug layer normally writes to the debugger's output window, where it scrolls away. There is a callback API that hands each message to you instead. I translate the severity into a log level and send it to the `D3D12` logger:

```cpp
static void CALLBACK OnD3D12Message(D3D12_MESSAGE_CATEGORY, D3D12_MESSAGE_SEVERITY severity,
                                    D3D12_MESSAGE_ID, LPCSTR pDescription, void*)
{
    spdlog::level::level_enum level = spdlog::level::debug;
    switch (severity)
    {
        case D3D12_MESSAGE_SEVERITY_CORRUPTION: level = spdlog::level::critical; break;
        case D3D12_MESSAGE_SEVERITY_ERROR:      level = spdlog::level::err;      break;
        case D3D12_MESSAGE_SEVERITY_WARNING:    level = spdlog::level::warn;     break;
        case D3D12_MESSAGE_SEVERITY_INFO:       level = spdlog::level::info;     break;
        default:                                break;
    }
    G_pD3D12Logger->log(level, "{}", pDescription);
}
```

&nbsp;

Registering it is a query for the newer info queue interface, and `Shutdown` unregisters it with the cookie it was handed:

```cpp
JN_CHECK_HRESULT(pQueue->RegisterMessageCallback(
    OnD3D12Message, D3D12_MESSAGE_CALLBACK_FLAG_NONE, nullptr, &G_uiMessageCookie));
```

&nbsp;

Break-on-error from last time is still on, so a real error now does both: it appears in the log with an orange `D3D12` badge, and then the debugger stops on the offending call.

## The order of Init now

`Init` grew two steps and gained a rule: the routing and the barrier check come right after the device exists, and the queue and fence come after those.

```cpp
void Init()
{
    EnableDebugLayer();

    JN_CHECK_HRESULT(CreateDXGIFactory2(DXGI_CREATE_FACTORY_DEBUG, IID_PPV_ARGS(&G_pFactory)));

    IDXGIAdapter1* pAdapter = PickAdapter();
    JN_CHECK_HRESULT(D3D12CreateDevice(pAdapter, D3D_FEATURE_LEVEL_12_0, IID_PPV_ARGS(&G_pDevice)));

    RouteDebugMessagesToLogger();
    RequireEnhancedBarriers();
    EnableBreakOnError();

    CreateCommandQueue();
    CreateFence();

    SafeRelease(pAdapter);
}
```

## What is still missing

- **No GPU work.** The queue and the fence exist and `WaitIdle` works, but nothing is ever submitted. The next phase adds the first command list.
- **No swapchain, no barriers in code.** The concepts are down, the Agility SDK is wired and verified, and the actual barrier helper is still to be written.
- **No frames in flight.** One fence and a `WaitIdle` is the "one frame in flight" case. Per-frame allocators and the slot logic come after the first clear works.
- **Globals again.** The queue, fence and event are namespace-level globals alongside the device. Still deliberate, still to be extracted from working code.
- **Infinite waits.** `WaitForFence` will wait forever on a hung GPU.
- **Hardcoded SDK version.** The `620` in the exe and the `1.620.1` in CMake are two copies of one fact, kept in sync by hand and a comment.

&nbsp;

Next up is the swapchain, a descriptor heap for render target views, and a window that turns a solid colour. That is the first time the barrier table above stops being a table.

## GitHub Link
[Janus repo](https://github.com/TheOrestes/Janus)
