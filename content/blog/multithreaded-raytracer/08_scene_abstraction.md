+++
title = "Who Owns the Spheres?"
date = 2026-08-18T00:00:00+05:30
tags = ["raytracing", "architecture", "cpp"]
description = "Three commits moving the scene from free-floating globals to something with an owner — and the one-definition-rule problem I'd been carrying since post 3."
+++

Post 7 ended with a prediction: a raw `Hitable**` array with a hand-counted size, `new`ed and never freed, was not going to survive a model with tens of thousands of triangles in it.

&nbsp;

These three commits are me doing something about that. It takes two goes to land somewhere I'd defend, and the intermediate step is a singleton, which I still think was the right thing to reach for at the time even though I moved off it later.

## First, the headers

Before any of the scene work, there's a change spread across half the files.

&nbsp;

```cpp
-	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, Vector3& attenuation, Ray& scatterd) const
-	{
-		Vector3 target = rec.P + rec.N + Helper::RandomInUnitSphere();
-		scatterd = Ray(rec.P, target - rec.P);
-		attenuation = Albedo;
-		return true;
-	}
+	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, Vector3& attenuation, Ray& scatterd) const;
```

&nbsp;

The body moves out to `Lambertian.cpp`. `Metal`, `Sphere` and `Triangle` all get the same treatment, and the free functions in `Helper.h` that stay in the header get marked `inline`:

&nbsp;

```cpp
-	float schlick(float cosine, float ref_idx)
+	inline float schlick(float cosine, float ref_idx)
```

&nbsp;

This is the thing I flagged back in post 3 and said was on the list. A non-inline function defined in a header gets a full definition in every translation unit that includes it, and the moment there are two such units the linker has a duplicate symbol and stops. It hadn't bitten me because there was barely a second `.cpp` in the project — and this commit is where that stops being true, because `Scene.cpp` is about to arrive and pull most of these headers in.

&nbsp;

Two ways to fix it, and the commit uses both: move the definition to a `.cpp` if it's a class member, or mark it `inline` if it's a free function you want to stay in the header. There's a pleasant side effect too — changing how a material scatters now rebuilds one file instead of everything that transitively included it.

## A Scene, and a vector

Then the new class:

&nbsp;

```cpp
class Scene
{
public:
	static Scene& getInstance()
	{
		static Scene instance;
		return instance;
	}

	void InitScene();
	bool Trace(const Ray& r, float tmin, float tmax, HitRecord& rec);

private:
	Scene();

	std::vector<Hitable*> vecHitables;
};
```

&nbsp;

Two things happen here and they're worth separating.

&nbsp;

The first is the container. `Hitable** list` plus a hand-maintained count becomes `std::vector<Hitable*>`. That sounds small and it removes an entire category of mistake — post 7's scene allocated `new Hitable*[6]`, filled six slots and passed `6` to the constructor, and every one of those numbers had to be updated together. Add a seventh object and forget one of them and you either drop it silently or walk off the end. The vector knows how big it is because it's the only thing that could.

&nbsp;

The second is `Trace`:

&nbsp;

```cpp
bool Scene::Trace(const Ray& r, float tmin, float tmax, HitRecord& rec)
{
	bool hit_anything = false;
	HitRecord temp_rec;
	double closest_so_far = tmax;

	for (int i = 0; i < vecHitables.size(); i++)
	{
		if (vecHitables[i]->hit(r, tmin, closest_so_far, temp_rec))
		{
			hit_anything = true;
			closest_so_far = temp_rec.t;
			rec = temp_rec;
		}
	}

	return hit_anything;
}
```

&nbsp;

Which is `HitableList::hit` from post 3, moved and renamed. Same running minimum, same trick of feeding `closest_so_far` back in as the next object's `tmax`. `HitableList` itself stops being included anywhere — the scene absorbed its one job.

&nbsp;

And the call site barely notices:

&nbsp;

```cpp
-	if (world->hit(r, 0.001f, FLT_MAX, rec))
+	if (Scene::getInstance().Trace(r, 0.001f, FLT_MAX, rec))
```

&nbsp;

One line. The global `Hitable* world` is gone, along with the free functions that built it — although "gone" is generous, since I commented them out rather than deleting them, and they sit at the top of the file for another few weeks.

&nbsp;

The resolution drops to 480×270 and the samples to 10 in the same commit. That's not a decision about the renderer, that's me wanting a two-second turnaround while moving code around.

## Scenes become methods

The second commit ports the big random scene — 500-odd spheres in a grid, the one from the cover of the book — into the class:

&nbsp;

```cpp
void Scene::InitRandomScene()
{
	Sphere* pSphere0 = new Sphere(Vector3(0, -1000, 0), 1000, new Lambertian(Vector3(0.5, 0.5, 0.5)));
	vecHitables.push_back(pSphere0);
	...
}
```

&nbsp;

Mechanically it's the same loop as before with `list[i++] = ...` replaced by `push_back`. What changes is what a scene *is*. It used to be a free function that returned a raw array and left you to remember its length. Now it's a method that fills the object's own storage, and the constructor picks one:

&nbsp;

```cpp
Scene::Scene()
{
	vecHitables.clear();
	//InitScene();
	InitRandomScene();
}
```

&nbsp;

Switching scenes is a commented line. That's not elegant, but it's honest about what I was doing — flipping between a small test scene and a heavy one depending on whether I was debugging or admiring.

## Then the singletons go

The third commit is the one that actually settles ownership, and its message says exactly what it does: *Camera is part of Scene instead of singleton — Scene is part of Application instead of singleton.*

&nbsp;

```cpp
-	static Camera& getInstance()
-	{
-		static Camera instance;
-		return instance;
-	}
-
+	Camera();
```

&nbsp;

```cpp
+	Scene();
 	~Scene();
-	
-	static Scene& getInstance()
-	{
-		static Scene instance;
-		return instance;
-	}
```

&nbsp;

Both `getInstance` methods delete, both constructors become public, and the objects get held instead:

&nbsp;

```cpp
-	Camera*			m_pCamera;
+	Scene*			m_pScene;
```

&nbsp;

`Application` holds a `Scene`. `Scene` holds a `Camera` and the geometry. Asking for the camera goes through the thing that owns it:

&nbsp;

```cpp
-					Ray r = m_pCamera->get_ray(u, v);
+					Ray r = m_pScene->getCamera()->get_ray(u, v);
```

&nbsp;

![Where the scene lived across the three commits. The middle stage is a real step rather than a wrong turn — a singleton is what you reach for when you know there is exactly one of something and haven't yet decided who should be responsible for it](/images/blog/raytracer/scene_ownership.svg)

&nbsp;

I don't regret the singleton stage. When I pulled the scene out of those globals I knew two things — there's exactly one scene, and everything needs to reach it — and a singleton answers both immediately without requiring me to decide anything about lifetimes. The cost is that it answers "who owns this" with "nobody", which is fine right up until you want two of something, or want to tear one down and build another.

&nbsp;

The camera change is what made that concrete. `InitCamera` used to hardcode where it was:

&nbsp;

```cpp
-	lookFrom = glm::vec3(5.0f, 3.0f, 5.0f);
-	lookAt = glm::vec3(0.0f, 0.0f, 0.0f);
+	position = _position;
+	lookAt = _lookAt;
```

&nbsp;

Once each scene sets up its own camera, a global camera stops making sense — the Cornell box wants a different viewpoint than the sphere grid, and they can't both be the one true camera. Scenes owning their cameras falls out of that, and once `Scene` owns something, `Scene` needs an owner of its own.

&nbsp;

You can also see in that snippet that my hand-rolled `Vector3` from post 2 has quietly become `glm::vec3`. That happened somewhere between here and there and deserves its own mention when I get to it.

## What I didn't fix

Every object in that vector is still a raw `new` with no matching `delete`.

&nbsp;

The vector manages its own storage and knows its own length, so the *container* is sorted. The things it points at are not — they're allocated during scene setup and reclaimed when the process exits. For a renderer that builds one scene and then runs, that's a leak in the technical sense and a non-event in practice. It becomes a real problem the day I want to unload a scene and load another, and I'd fix it with `unique_ptr` rather than by adding a destructor loop.

&nbsp;

There's also this, which I noticed writing this post rather than at the time:

&nbsp;

```cpp
inline Camera* getCamera() { if(m_pCamera) return m_pCamera; }
```

&nbsp;

No return on the false branch. If `m_pCamera` were ever null the function would fall off the end and hand back whatever happened to be in the return register. It never is null, because `Scene` creates it, so the bug is unreachable — but "unreachable" is doing a lot of work in that sentence, and the fix is to return the pointer unconditionally.

## Where this leaves us

The scene is a thing now. It holds anything that can answer the hit question, it knows how many of them there are, it owns the camera it's viewed through, and something above it owns the whole arrangement.

&nbsp;

Which means I can finally point it at a file full of triangles instead of typing vertices in by hand.

&nbsp;

---

**Commits:** [`ef07d36` — Added Scene class for common objects](https://github.com/TheOrestes/Windows_RayTracer/commit/ef07d36) · [`befe602` — Added Scene class](https://github.com/TheOrestes/Windows_RayTracer/commit/befe602) · [`01bee25` — Camera is part of Scene, Scene is part of Application](https://github.com/TheOrestes/Windows_RayTracer/commit/01bee25)

&nbsp;

*Next up: assimp, and loading a model that somebody else made.*
