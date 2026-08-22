+++
title = "Seven Billion Questions"
date = 2026-08-19T11:00:00+05:30
tags = ["raytracing", "performance", "bvh", "profiling", "cpp"]
description = "Building a profiler before building the optimisation, and then a bounding volume hierarchy to answer for the numbers it reported."
+++

Last post ended with one box around the whole deer, and a ray that hits that box still asking all 1503 triangles.

&nbsp;

The obvious next move is a tree of boxes. What I did first was count.

&nbsp;

These three commits are in that order — two that add a profiler, then one that adds the BVH. It's the right order, because "the renderer feels slow" is not a number and you can't tell whether you've improved it.

&nbsp;

*(One thing to carry into this post: the box test here is still the version last post was about, the one that swaps on the wrong axis. It gets replaced immediately after the BVH lands, and it turns out to matter for the numbers.)*

## The instrument

`Profiler` is a singleton holding one string:

&nbsp;

```cpp
class Profiler
{
public:
	static Profiler& getInstance()
	{
		static Profiler instance;
		return instance;
	}

	std::string GetProfilerTexts() { return m_strInfo; }

	void WriteToProfiler(const std::string& _inputStr);
	void WriteToProfiler(const std::string& _inputStr, float _value);
	void WriteToProfiler(const std::string& _inputStr, double _value);
	void WriteToProfiler(const std::string& _inputStr, int _value);

private:
	Profiler();

	std::string m_strInfo;
};
```

&nbsp;

Four overloads that append a label and a formatted value, and a menu item that shows the accumulated text in a message box. The old **File → Render Time** entry gets deleted and a **Profiler → Render Stats** popup takes its place.

&nbsp;

There's nothing clever here and that's rather the point. It has no dependencies, it took an afternoon, and it turned a vague feeling into a list of integers I could act on.

## Counters that ride with the ray

The interesting decision is where the counts live. They go into `HitRecord`:

&nbsp;

```cpp
struct HitRecord
{
	HitRecord()
	{
		t = 0.0f;
		P = glm::vec3(0);
		N = glm::vec3(0);
		uv = glm::vec2(0);
		mat_ptr = nullptr;

		rayTriangleTestCount = 0;
		rayTriangleIntersectionCount = 0;
		rayBoxTestCount = 0;
	}
	...
	// Debug...
	int rayTriangleTestCount;
	int rayTriangleIntersectionCount;
	int rayBoxTestCount;
};
```

&nbsp;

`HitRecord` is already passed by reference into every `hit` function in the renderer — spheres, triangles, meshes, boxes. It's the one thing that already goes everywhere, so hanging counters off it lets every intersection routine increment one without a single new parameter:

&nbsp;

```cpp
bool Triangle::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
{
	++rec.rayTriangleTestCount;
	...
```

&nbsp;

Then `TraceColor` folds each ray's tally into an atomic once that ray is finished:

&nbsp;

```cpp
// debug info...
m_iRayTriangleTest += rec.rayTriangleTestCount;
m_iRayTriangleIntersections += rec.rayTriangleIntersectionCount;
m_iRayBoxTest += rec.rayBoxTestCount;
```

&nbsp;

Per-ray counting in a plain `int` on the stack, one atomic add at the end. That's the same shape as the fix in post 6, where a shared `++numRays` in the inner loop cost more than the work it was counting. Sixteen threads hammering one atomic several billion times would dwarf the thing being measured; sixteen threads doing one atomic add per ray costs nothing worth talking about.

## Two things the first version got wrong about counting

The second commit is titled *"Added More data for profiling with uint64_t support"* — and it's the more interesting of the two.

&nbsp;

First, the counters overflow. The ray-triangle count for a single 640 × 480 frame at 8 samples, with no acceleration, comes to **7,044,126,633**. A signed 32-bit int tops out at 2,147,483,647, so that wraps three times over and reports whatever's left. Everything becomes `uint64_t`, including the format string:

&nbsp;

```cpp
-	sprintf(buffer, "%d", _value);
+	sprintf(buffer, "%" PRId64, _value);
```

&nbsp;

Second, and this is the part I like, the counters get renamed:

&nbsp;

```cpp
-	rayTriangleTestCount;
-	rayTriangleIntersectionCount;
-	rayBoxTestCount;
+	rayTriangleQuery;
+	rayTriangleSuccess;
+	rayBoxQuery;
+	rayBoxSuccess;
```

&nbsp;

Query and success, for both boxes and triangles. A raw test count tells you how much work you did. A query/success pair tells you how much of that work was **wasted**, and that ratio is the entire subject of this post. An acceleration structure isn't trying to make intersection tests faster — it's trying to stop you asking questions whose answer is no.

&nbsp;

There's also a small correctness fix for the measurement itself, in `Scene::Trace`:

&nbsp;

```cpp
else
{
	// This is needed for Profile information
	// If ray doesn't hit anything, still it could have done BBox query or
	// Traiangle Query which needs to be accumulated..!
	rec = temp_rec;
}
```

&nbsp;

Without it, a ray that tests a thousand triangles and hits none discards its own tally — and the misses, exactly the work I was trying to eliminate, never appear in the numbers at all. That one would have made the renderer look better than it was.

## The baseline

The same commit comments out the bounding box gate in `TriangleMesh::hit`:

&nbsp;

```cpp
-	if (m_ptrAABB->hit(r, tmin, tmax, rec))
+	//if (m_ptrAABB->hit(r, tmin, tmax, rec))
	{
		for (int i = 0; i < m_vecTriangles.size(); i++)
```

&nbsp;

Which reads like a regression and isn't one. With a working profiler you want a floor to measure against, and the floor is every ray asking every triangle. On the deer at 640 × 480 and 8 samples, that floor is 7.04 billion triangle queries and **461,360** of them hitting something.

&nbsp;

Six thousandths of one percent. That's the number the rest of this post exists to attack.

## The tree

Then `LameBVH.h` arrives, opening with a credit.

&nbsp;

```cpp
///////////////////////////////////////////////////////////////////////////////////////////////////
// Based on Implementation by : https://github.com/DarrenSweeney/Dazzer_Ray
///////////////////////////////////////////////////////////////////////////////////////////////////
```

&nbsp;

A node is a box, two children, and — if it's a leaf — a range into the triangle array:

&nbsp;

```cpp
struct BVHNode
{
	BVHNode* leftNode;
	BVHNode* rightNode;
	AABB	 bbox;
	bool	 isLeaf;
	uint64_t startIndex;
	uint64_t numTriangles;
};
```

&nbsp;

Note what a leaf stores: a start index and a count, not a list of triangles. The build sorts one shared vector in place, so every node's contents are a contiguous slice of it. No copying, and no per-node allocation of triangle pointers.

&nbsp;

The build itself is five steps in `BuildRecursive`:

&nbsp;

```cpp
// 4. Find AABB's longest axis & sort each object along this direction
int longestAxis = node->bbox.GetLongestAxis();
glm::vec3 nodeAxis = node->bbox.minBound + node->bbox.maxBound;
float axisMidPoint = nodeAxis[longestAxis] * 0.5f;

switch (longestAxis)
{
case 0:
	std::sort(primsVector->begin() + startIndex, primsVector->begin() + endIndex, CompareBB_X);
	break;
	...
}

// 5. Find split index according to midPoint on largest axis
int splitIndex = startIndex;
for (int i = startIndex; i < endIndex; i++)
{
	glm::vec3 centroid = primsVector->at(i)->Centroid();
	if (centroid[longestAxis] > axisMidPoint)
	{
		splitIndex = i;
		break;
	}
}
```

&nbsp;

Split along whichever axis the box is longest in — that's the direction with the most room to separate things. Sort the triangles in that slice by centroid. Then walk forward until a centroid passes the midpoint of the box, and that index is the partition.

&nbsp;

![Sorting by centroid along the longest axis is what makes the split a single index rather than a partition pass](/images/blog/raytracer/bvh_split.svg)

&nbsp;

The sort is what makes step 5 legal. Once the slice is ordered along that axis, everything below the midpoint is already contiguous, so "the first centroid past the midpoint" is a clean boundary and the two halves are just two ranges of the same array.

&nbsp;

Each half is then bounded, given a node, and recursed into, until a node holds few enough triangles to be a leaf.

## Traversal

`BVHTree::Hit` is a recursive descent that tests both children's boxes and only walks into the ones the ray actually entered:

&nbsp;

```cpp
if (firstNode)
{
	float thit1 = tMax;
	bool isIntersect1 = Hit(firstNode, ray, tMin, thit1, rec);

	if (isIntersect1 && thit1 < tMax)
	{
		tMax = thit1;
		isIntersection = true;
	}
}

if (secondNode)
{
	float thit2 = tMax;
	bool isIntersect2 = Hit(secondNode, ray, tMin, thit2, rec);
	...
```

&nbsp;

The detail worth noticing is `tMax = thit1` between the two. Once the left subtree has found a hit at some distance, the right subtree is searched with a tighter ceiling — anything further away can't win, so whole branches fail their box test on distance alone. It's the same closest-hit bookkeeping as post 8's `closest_so_far`, now doing double duty as a pruning device.

&nbsp;

And at a leaf, the loop this whole structure exists to shrink:

&nbsp;

```cpp
for (uint64_t i = startIndex; i < startIndex + noOfTriangles; i++)
{
	if (primsVector->at(i)->hit(ray, tMin, tMax, rec))
	{
		isIntersection = true;
		tMax = rec.t;
	}
}
```

## The numbers

Same scene, same camera, same 640 × 480 frame at 8 samples. The only thing changing is what stands between a ray and the triangle list:

&nbsp;

| | render time | ray-triangle queries | of which hit |
|---|---|---|---|
| no acceleration | 25.04 s | 7,044,126,633 | 461,360 |
| one box per mesh | 10.34 s | 2,057,204,196 | 461,360 |
| BVH | **1.36 s** | **157,446,066** | 459,442 |

&nbsp;

![](/images/blog/raytracer/bvh_queries_chart.svg)

&nbsp;

![The frame all three rows are rendering. It's the same picture in every case, which is the point — the tree changes what the renderer asks, not what it finds](/images/blog/raytracer/bvh_scene.png)

&nbsp;

Forty-five times fewer triangle tests, and the frame goes from twenty-five seconds to one and a bit. The hit rate climbs from 0.0065% to 0.29% — still low, because most rays in a scene this open are heading for the sky, but it's a factor of forty-five less work to establish that.

&nbsp;

What buys it is 13.9 million box tests. Each one is six subtractions, six multiplies and some comparisons; each triangle test is a pair of cross products and a division. Trading fourteen million of the cheap ones for seven billion of the expensive ones is the whole idea, stated as a ratio: **every box query the BVH added saved about 495 triangle queries.**

&nbsp;

The middle row is worth a moment too. One box per mesh — last post's version — already removes two thirds of the work, for about thirty lines of code. The tree removes 97.8% of what remains. Most of the available win was in the first, cheapest idea, which is usually how this goes.

## A caveat on those numbers, and one on the tree

The table above uses the corrected slab test. Built exactly as it stands in this commit, the same BVH renders the frame in 0.81 seconds rather than 1.36 — because the Z slab is still asking about `rayInvDirection[1]`, and a box test that wrongly rejects geometry is very fast indeed. It shows up in the one column that can't be argued with:

&nbsp;

| | of which hit |
|---|---|
| no acceleration (no box test involved) | 461,360 |
| one box per mesh, as committed | 379,920 |
| one box per mesh, corrected | 461,360 |

&nbsp;

Eighteen percent of the deer's real intersections, discarded. Putting that test into every node of a tree instead of once per mesh is what made it impossible to keep missing, and it was replaced in the very next commit — which is where last post picked it up.

&nbsp;

There's one more gap in that table, and it belongs to the tree rather than the box. With the corrected test the BVH finds 459,442 hits where brute force finds 461,360: **1,918 short, about four in a thousand.** Those are triangles the build loses. The left child gets `[startIndex, splitIndex)` and the right gets `[splitIndex + 1, endIndex)`, so the triangle sitting exactly on the split belongs to neither — its bounds are inside the right node's box, but it's outside the range that leaf will ever loop over. One triangle per split, and it's the sort of off-by-one that comparing the BVH against brute force catches in a single run.

## What I'd change

Two more I know about.

&nbsp;

**The leaf size is a fraction, not a constant.**

&nbsp;

```cpp
m_ptrBVH->BuildBVHTree(&m_vecTriangles, m_iTriangleCount/8);
```

&nbsp;

A node stops splitting once it holds an eighth of the mesh or fewer, so the tree bottoms out around three levels down no matter how big the model is, and a ray reaching a leaf still tests nearly two hundred triangles. Changing that divisor to a small constant is a one-line change and most of the win that's left.

&nbsp;

**The mesh forces one material.**

&nbsp;

```cpp
if (m_ptrBVH->hit(r, tmin, tmax, rec))
{
	rec.mat_ptr = m_ptrMaterial;
	isIntersection = true;
}
```

&nbsp;

Every triangle in this mesh is built with the mesh's material anyway, so today it changes nothing. But post 11 was entirely about materials arriving per mesh from the FBX, and this line would quietly overwrite anything more granular. It should be the triangle's own pointer, which `Triangle::hit` has already written into `rec`.

## Where this leaves us

There's a profiler, and it reports enough to say whether a change helped. There's a tree, and it removes forty-four out of every forty-five questions the renderer used to ask.

&nbsp;

The part I'd keep from these three commits isn't the BVH. It's that the measurement came first — every number above exists because of an afternoon spent on a class that appends strings.

&nbsp;

---

**Commits:** [`c5e1a44` — Added Profiling data capturing](https://github.com/TheOrestes/Windows_RayTracer/commit/c5e1a44) · [`d783830` — More data for profiling with uint64_t support](https://github.com/TheOrestes/Windows_RayTracer/commit/d783830) · [`cbb7202` — Added Profiler system, added BVH implementation](https://github.com/TheOrestes/Windows_RayTracer/commit/cbb7202)

&nbsp;

*Next up: pulling the renderer out of the window procedure.*
