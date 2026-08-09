# Post 4 — Lambertian, Metal, and dielectrics

## `24e60c1` — 2018-05-13 _(master)_

> GDI based ray tracer, First commit.

_This commit introduces the whole project at once (852 lines, 26 files). The diff below is scoped to just the files relevant to this post._

```diff
diff --git a/RayTracer/Lambertian.h b/RayTracer/Lambertian.h
new file mode 100644
index 0000000..518dc38
--- /dev/null
+++ b/RayTracer/Lambertian.h
@@ -0,0 +1,23 @@
+#pragma once
+
+#include "Ray.h"
+#include "Hitable.h"
+#include "Material.h"
+#include "Helper.h"
+
+class Lambertian : public Material
+{
+public:
+	Lambertian(const Vector3& _albedo) : Albedo(_albedo) {}
+
+	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, Vector3& attenuation, Ray& scatterd) const
+	{
+		Vector3 target = rec.P + rec.N + Helper::RandomInUnitSphere();
+		scatterd = Ray(rec.P, target - rec.P);
+		attenuation = Albedo;
+		return true;
+	}
+
+private:
+	Vector3 Albedo;
+};
\ No newline at end of file
diff --git a/RayTracer/Material.h b/RayTracer/Material.h
new file mode 100644
index 0000000..fabaa21
--- /dev/null
+++ b/RayTracer/Material.h
@@ -0,0 +1,10 @@
+#pragma once
+
+#include "Ray.h"
+#include "Hitable.h"
+
+class Material
+{
+public:
+	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, Vector3& attenuation, Ray& scattered) const = 0;
+};
diff --git a/RayTracer/Metal.h b/RayTracer/Metal.h
new file mode 100644
index 0000000..496181f
--- /dev/null
+++ b/RayTracer/Metal.h
@@ -0,0 +1,30 @@
+#pragma once
+
+#include "Ray.h"
+#include "Hitable.h"
+#include "Material.h"
+#include "Helper.h"
+
+class Metal : public Material
+{
+public:
+	Metal (const Vector3& _albedo, float f) : Albedo(_albedo) 
+	{
+		if (f < 1)
+			fuzz = f;
+		else
+			fuzz = 1;
+	}
+
+	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, Vector3& attenuation, Ray& scatterd) const
+	{
+		Vector3 target = Helper::Reflect(unit_vector(r_in.GetRayDirection()), rec.N);
+		scatterd = Ray(rec.P, target + fuzz * Helper::RandomInUnitSphere());
+		attenuation = Albedo;
+		return (dot(scatterd.GetRayDirection(), rec.N) > 0);
+	}
+
+private:
+	Vector3 Albedo;
+	float fuzz;
+};
diff --git a/RayTracer/Transparent.h b/RayTracer/Transparent.h
new file mode 100644
index 0000000..0f227c7
--- /dev/null
+++ b/RayTracer/Transparent.h
@@ -0,0 +1,63 @@
+#pragma once
+
+#include "Ray.h"
+#include "Hitable.h"
+#include "Helper.h"
+#include "Material.h"
+
+class Transparent : public Material
+{
+public:
+	Transparent(float ri) : refr_index(ri) {}
+
+	virtual bool Scatter(const Ray& r_in, const HitRecord& rec, Vector3& attenuation, Ray& scattered) const
+	{
+		Vector3 outward_normal;
+		Vector3 ray_direction = r_in.GetRayDirection();
+		
+		Vector3 reflected = Helper::Reflect(ray_direction, rec.N);
+		float ni_over_nt;
+		attenuation = Vector3(1, 1, 1);
+
+		Vector3 refracted;
+		float reflect_prob;
+		float cosine;
+
+		if (dot(ray_direction, rec.N) > 0)
+		{
+			outward_normal = -1 * rec.N;  // because we want inverted image for refraction? 
+			ni_over_nt = refr_index;
+			cosine = refr_index * dot(ray_direction, rec.N) / ray_direction.length();
+		}
+		else
+		{
+			outward_normal = rec.N;
+			ni_over_nt = 1 / refr_index;
+			cosine = -dot(ray_direction, rec.N) / ray_direction.length();
+		}
+
+		if (Helper::Refract(ray_direction, outward_normal, ni_over_nt, refracted))
+		{
+			reflect_prob = Helper::schlick(cosine, refr_index);
+		}
+		else
+		{
+			reflect_prob = 1.0f;
+		}
+
+		// this logic is not clear? 
+		if (Helper::GetRandom01() < reflect_prob)
+		{
+			scattered = Ray(rec.P, reflected);
+		}
+		else
+		{
+			scattered = Ray(rec.P, refracted);
+		}
+
+		return true;
+	}
+
+private:
+	float refr_index;
+};
\ No newline at end of file
```

