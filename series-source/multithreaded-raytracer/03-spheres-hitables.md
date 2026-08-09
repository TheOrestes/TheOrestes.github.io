# Post 3 — Spheres, hit records, and antialiasing

## `24e60c1` — 2018-05-13 _(master)_

> GDI based ray tracer, First commit.

_This commit introduces the whole project at once (852 lines, 26 files). The diff below is scoped to just the files relevant to this post._

```diff
diff --git a/RayTracer/Hitable.h b/RayTracer/Hitable.h
new file mode 100644
index 0000000..2f43e47
--- /dev/null
+++ b/RayTracer/Hitable.h
@@ -0,0 +1,19 @@
+#pragma once
+
+#include "Ray.h"
+
+class Material;
+
+struct HitRecord
+{
+	float t;
+	Vector3 P;
+	Vector3 N;
+	Material* mat_ptr;
+};
+
+class Hitable
+{
+public:
+	virtual bool hit(const Ray& r, float t_min, float t_max, HitRecord& rec) const = 0;
+};
\ No newline at end of file
diff --git a/RayTracer/HitableList.h b/RayTracer/HitableList.h
new file mode 100644
index 0000000..978a12d
--- /dev/null
+++ b/RayTracer/HitableList.h
@@ -0,0 +1,41 @@
+#pragma once
+
+#include "Hitable.h"
+
+class HitableList : public Hitable
+{
+public:
+	HitableList();
+	HitableList(Hitable** _list, int _n)
+	{
+		hitable_list = _list;
+		list_size = _n;
+	}
+
+	virtual bool hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const;
+
+private:
+	Hitable** hitable_list;
+	int list_size;
+};
+
+
+/////////////////////////////////////////////////////////////////////////////////////////
+bool HitableList::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
+{
+	HitRecord temp_rec;
+	bool hit_anything = false;
+	double closest_so_far = tmax;
+
+	for (int i = 0; i < list_size; i++)
+	{
+		if (hitable_list[i]->hit(r, tmin, closest_so_far, temp_rec))
+		{
+			hit_anything = true;
+			closest_so_far = temp_rec.t;
+			rec = temp_rec;
+		}
+	}
+
+	return hit_anything;
+}
\ No newline at end of file
diff --git a/RayTracer/Sphere.h b/RayTracer/Sphere.h
new file mode 100644
index 0000000..e9ef16a
--- /dev/null
+++ b/RayTracer/Sphere.h
@@ -0,0 +1,59 @@
+#pragma once
+
+#include "Hitable.h"
+
+class Material;
+
+class Sphere : public Hitable
+{
+public:
+	Sphere() {}
+	Sphere(Vector3 _center, float _r, Material* ptr_mat) :
+		center(_center),
+		radius(_r),
+		mat_ptr(ptr_mat) {};
+
+	virtual bool hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const;
+
+private:
+	Vector3 center;
+	float radius;
+	Material* mat_ptr;
+};
+
+/////////////////////////////////////////////////////////////////////////////////////////
+bool Sphere::hit(const Ray& r, float tmin, float tmax, HitRecord& rec) const
+{
+	Vector3 oc = r.GetRayOrigin() - center;
+	float a = dot(r.GetRayDirection(), r.GetRayDirection());
+	float b = 2.0f * dot(oc, r.GetRayDirection());
+	float c = dot(oc, oc) - radius * radius;
+	float discriminant = b * b - 4 * a* c;
+
+	float t;
+
+	if (discriminant > 0)
+	{
+		t = (-b - sqrt(discriminant)) / (2.0 * a);
+		if (t < tmax && t > tmin)
+		{
+			rec.t = t;
+			rec.P = r.GetPointAt(t);
+			rec.N = (rec.P - center) / radius;
+			rec.mat_ptr = mat_ptr;
+			return true;
+		}
+
+		t = (-b + sqrt(discriminant)) / (2.0 * a);
+		if (t < tmax && t > tmin)
+		{
+			rec.t = t;
+			rec.P = r.GetPointAt(t);
+			rec.N = (rec.P - center) / radius;
+			rec.mat_ptr = mat_ptr;
+			return true;
+		}
+	}
+
+	return false;
+}
\ No newline at end of file
```

