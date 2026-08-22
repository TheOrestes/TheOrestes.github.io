+++
title = "Two Triangles and a Texture"
date = 2026-08-20T10:00:00+05:30
tags = ["raytracing", "opengl", "glfw", "threading", "cpp"]
description = "Replacing the per-pixel GDI call with a texture upload and a screen-aligned quad — and the branch that came out of it."
+++

`SetPixel` has been the antagonist of this series since post 1. Post 5 measured sixteen threads coming out *slower* than one because of it. Post 6 traced the cost to a device context that can only be used by one thread at a time. Post 14 ended with the renderer neatly packaged in a class and still drawing one pixel at a time.

&nbsp;

These two commits are the answer, and they're the oldest ones in the last stretch of this series — they come well before the AABB and the profiler. I built the display path early, then went back to the GDI version on master and kept adding features to it. This is where the alternative came from.

## The idea

Stop treating the window as something you draw *into*, and start treating it as something you *upload to*.

&nbsp;

The tracer writes colours into a plain `std::vector<glm::vec3>`. That array is uploaded to the GPU as a texture. The texture is drawn on two triangles that exactly cover the window. There is no per-pixel call to anything.

&nbsp;

![The device context is a shared resource and the array isn't — that's the whole change](/images/blog/raytracer/setpixel_vs_texture.svg)

&nbsp;

The quad is six vertices in normalised device coordinates, which is to say the corners of the screen, with no camera or transform anywhere near them:

&nbsp;

```cpp
// Create screen aligned quad data in NDC space.
quadVertices[0] = VertexPT(glm::vec3(-1, 1, 0), glm::vec2(0, 1));
quadVertices[1] = VertexPT(glm::vec3(-1, -1, 0), glm::vec2(0, 0));
quadVertices[2] = VertexPT(glm::vec3(1, -1, 0), glm::vec2(1, 0));
quadVertices[3] = VertexPT(glm::vec3(-1, 1, 0), glm::vec2(0, 1));
quadVertices[4] = VertexPT(glm::vec3(1, -1, 0), glm::vec2(1, 0));
quadVertices[5] = VertexPT(glm::vec3(1, 1, 0), glm::vec2(1, 1));
```

&nbsp;

And the shaders are as small as shaders get. The vertex shader passes the position through untouched:

&nbsp;

```glsl
void main()
{
	gl_Position = vec4(in_Position.x, in_Position.y, 0.0f, 1.0f);
	vs_outTexcoord = in_Texcoord;
}
```

&nbsp;

The fragment shader is one line:

&nbsp;

```glsl
void main()
{
	outColor = texture(screenTexture, vs_outTexcoord);
}
```

&nbsp;

That is the entire display pipeline. Everything else the GPU can do is unused — no lighting, no depth, no transforms. It's being asked to do exactly one thing that GDI was bad at: move a rectangle of pixels to the screen quickly.

&nbsp;

Uploading is one call:

&nbsp;

```cpp
void ScreenAlignedQuad::UpdateTexture(int xStart, int yStart, int width, int height, const float* pixels)
{
	glBindTexture(GL_TEXTURE_2D, tbo);

	glTexSubImage2D(GL_TEXTURE_2D, 0, xStart, yStart, width, height, GL_RGB, GL_FLOAT, (void*)pixels);

	glBindTexture(GL_TEXTURE_2D, 0);
}
```

&nbsp;

Note `GL_FLOAT`. The renderer's colours are `glm::vec3`, and they go to the GPU as floats — the `255.99f *` conversion that every previous post ended with simply isn't in this path.

## Watching it fill in

The first commit is single-threaded, and it does something the GDI version never could comfortably: it shows you the render as it happens, a row at a time.

&nbsp;

```cpp
for (int j = gBackbufferHeight; j >= 0; j--)
{
	std::vector<glm::vec3> rowColors;

	for (int i = 0; i <= gBackbufferWidth; i++)
	{
		...
		rowColors.push_back(color);
	}

	gQuad->UpdateTexture(0, j, gBackbufferWidth, 1, glm::value_ptr(rowColors[0]));
	gQuad->Render();
	glfwSwapBuffers(window);
	rowColors.clear();
}
```

&nbsp;

One row traced, one row uploaded, one frame presented. 270 uploads for a whole image instead of 129,600 individual calls, and you get a progress bar for free — the picture *is* the progress bar.

&nbsp;

<!-- VIDEO: 6064703 rendering row by row, top to bottom, 480x270 at 64 samples. Frames read back with glReadPixels between Render() and SwapBuffers rather than captured off screen — see blog-videos/multithreaded-raytracer/README.md for why. Recorded, awaiting upload — replace this with the YouTube link. Master: post15_6064703_row-by-row-fill_480x270_64spp.mp4 -->

*Video coming soon…*

&nbsp;

![`6064703`, single threaded, once it has finished. The mesh is commented out of the scene at this commit, so it's spheres only](/images/blog/raytracer/gl_single_threaded.png)

## Then the threads went back in

In the next commit, on a new branch, `ParallelTrace` comes back — and the per-row display goes away:

&nbsp;

```cpp
int main()
{
	...
	Execute();

	while (!glfwWindowShouldClose(window))
	{
		UpdateGL();
	}
```

&nbsp;

`Execute()` runs the whole threaded trace and joins every thread before it returns. Only then does the loop start uploading and drawing. So the window sits there showing the colour the buffer was initialised with — red — until the entire image is finished, and then it appears all at once.

&nbsp;

The commit message says so plainly: *"Added Opengl based single threaded & multi-threaded support. Realtime visualization for multi-threaded still missing."*

&nbsp;

Threads writing into a shared array can be displayed while they work — that's the advantage the array has over a device context — but wiring the display to run on the main thread while the workers fill the buffer is a different job, and it isn't in this commit.

## Thirteen red rows

Here's what that commit actually renders:

&nbsp;

![`d6488bb`, sixteen threads. The band across the top is the initial buffer colour, never written by any thread](/images/blog/raytracer/gl_threaded_band.png)

&nbsp;

The band is arithmetic. Each thread gets a slice of the height:

&nbsp;

```cpp
int quarterHeight = gBackbufferHeight / maxNumThreads;
int startHeight = i * quarterHeight;
int endHeight = (i + 1) * quarterHeight;
```

&nbsp;

At 480 × 270 on a sixteen-core machine, `270 / 16` truncates to 16. The last thread's band ends at row 256, and because the loop is written `j <= endHeight` it does cover that row — so rows 0 to 256 get traced and rows 257 to 269 belong to nobody. Thirteen rows keep the red they were filled with at startup.

&nbsp;

Two things fall out of that, and both are worth keeping:

&nbsp;

The bands are inclusive at both ends, so neighbouring threads both write the row where they meet. Harmless when every thread computes the same colour for it, and the sort of thing that stops being harmless the moment the buffer holds accumulated samples rather than final ones.

&nbsp;

And the leftover comes from integer division, so it changes with the machine. On a core count that divides 270 exactly there is no band at all, and the bug simply doesn't appear. Choosing a resolution that divided evenly would have hidden it rather than fixed it; the fix is for the last band to run to the end of the buffer.

## The mutex that isn't needed

One more thing in `ParallelTrace`:

&nbsp;

```cpp
threadMutex->lock();

vecBuffer[j * endWidth + i] = color;

threadMutex->unlock();
```

&nbsp;

A global mutex, locked and unlocked around a single `vec3` write, once per pixel. That's the same shape as the problem this whole commit exists to solve — every thread queuing for one shared thing in the innermost loop.

&nbsp;

It also isn't needed. Each thread owns a disjoint range of rows, the vector is sized once up front and never resized, so the threads are writing to addresses that don't overlap. Concurrent writes to distinct elements are fine. Deleting both lines is the entire fix, and it's on the list.

&nbsp;

The texture upload is the part that genuinely can't be done from a worker thread — an OpenGL context belongs to one thread at a time — and that constraint is real. Showing a threaded render as it happens means the workers fill the array and the main thread uploads whatever is in it whenever it feels like drawing a frame, which is a small amount of code and none of it difficult. It just isn't here yet.

## Where this leaves us

Two triangles, a texture, and about a hundred lines of GLFW setup replace the thing that had been throttling this renderer since the first commit. The tracer no longer knows or cares how its pixels reach the screen; it fills an array.

&nbsp;

Then I branched. `d6488bb` is the first commit on the `OpenGL` branch, and `ed7b215` immediately stripped the GL files back off `master`:

&nbsp;

> Cleanup for Windows(master) branch

&nbsp;

So the two lines ran side by side from there. Everything in posts 12, 13 and 14 — the bounding boxes, the profiler, the BVH, the application layer — was built on master, still calling `SetPixel`, while the display fix sat on a branch. Both got the same features, twice, from that point on.

&nbsp;

I don't think that was the right call, and it's why the last two posts in this series are on `OpenGL` rather than `master`.

&nbsp;

---

**Commits:** [`6064703` — GL based ray tracing renderer, single threaded](https://github.com/TheOrestes/Windows_RayTracer/commit/6064703) · [`d6488bb` — OpenGL based single & multi-threaded support](https://github.com/TheOrestes/Windows_RayTracer/commit/d6488bb)

&nbsp;

*Next up: where the samples inside a pixel actually land.*
