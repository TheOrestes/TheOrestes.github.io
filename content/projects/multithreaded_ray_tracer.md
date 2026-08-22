+++
title= "Multi-threaded Ray Tracer"
date= 2026-08-08T14:30:00+05:30
tags= ["c++", "raytracing", "multithreading", "win32"]
summary= "A CPU path tracer built from scratch on Win32 and GDI — no engine, no framework, no third-party math library."
repo= "https://github.com/TheOrestes/Windows_RayTracer"
series= "/blog/multithreaded-raytracer"
+++

A CPU path tracer written from the ground up, starting from an empty Win32 window and `SetPixel`. It began as a walk through the *Ray Tracing in One Weekend* books and kept going well past where those books stop.

&nbsp;

There is no engine here and no third-party math library — `Vector3`, `Ray`, and the camera are all hand-rolled. The camera never builds a view or projection matrix; it constructs an orthonormal basis and fires rays through a virtual image plane instead.

&nbsp;

## What it does

- Sphere and triangle intersection, with Lambertian, metal, and dielectric materials
- A BVH over the scene, plus a profiler to prove it was worth building
- Mesh loading through Assimp, including an FBX pipeline
- Texture mapping via barycentric coordinates
- Multi-threaded tile rendering, all threads drawing into the same window

&nbsp;

## What the series covers

The posts follow the project commit by commit — including the parts that went wrong. The threading chapter in particular starts with a naive attempt, explains why it stalled, and then rebuilds the scheduling around a job system.
