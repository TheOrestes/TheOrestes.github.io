# Post 2 — Vectors, rays, a camera, and a gradient sky

## `24e60c1` — 2018-05-13 _(master)_

> GDI based ray tracer, First commit.

_This commit introduces the whole project at once (852 lines, 26 files). The diff below is scoped to just the files relevant to this post._

```diff
diff --git a/RayTracer/Camera.h b/RayTracer/Camera.h
new file mode 100644
index 0000000..f7c2eac
--- /dev/null
+++ b/RayTracer/Camera.h
@@ -0,0 +1,41 @@
+#pragma once
+
+#include "Ray.h"
+#include "Helper.h"
+
+class Camera
+{
+public:
+	Camera(Vector3 lookFrom, Vector3 lookAt, Vector3 Up, float vfov, float aspect, float aperture, float focus_dist)	// vofv is vertical fov
+	{
+		lens_radius = aperture / 2.0f;
+
+		float theta = vfov * PI / 180.0f;
+		float half_height = tan(theta / 2);
+		float half_width = aspect * half_height;
+
+		origin = lookFrom;
+		w = unit_vector(lookFrom - lookAt);
+		u = unit_vector(cross(Up, w));
+		v = cross(w, u);
+
+		lower_left_corner = origin - half_width * focus_dist * u - half_height * focus_dist * v - focus_dist * w;
+		horizontal = 2 * half_width * focus_dist * u;
+		vertical = 2 * half_height * focus_dist * v;
+	}
+
+	Ray get_ray(float s, float t)
+	{
+		Vector3 rd = lens_radius * Helper::GetRandomInUnitDisk();
+		Vector3 offset = rd.x * u + rd.y * v;
+		return Ray(origin + offset, lower_left_corner + s * horizontal + t * vertical - origin - offset);
+	}
+
+private:
+	Vector3 origin;
+	Vector3 lower_left_corner;
+	Vector3 horizontal;
+	Vector3 vertical;
+	Vector3 u, v, w;
+	float lens_radius;
+};
diff --git a/RayTracer/Helper.h b/RayTracer/Helper.h
new file mode 100644
index 0000000..66e5d1b
--- /dev/null
+++ b/RayTracer/Helper.h
@@ -0,0 +1,68 @@
+#pragma once
+
+#include "Vector3.h"
+
+const float PI = 3.14159265358f;
+
+namespace Helper
+{
+	Vector3 LerpVector(const Vector3& vec1, const Vector3& vec2, float t)
+	{
+		return (1.0f - t) * vec1 + t * vec2;
+	}
+
+	double GetRandom01()
+	{
+		return ((double)rand() / (RAND_MAX + 1));
+	}
+
+	Vector3 GetRandomInUnitDisk()
+	{
+		Vector3 p;
+		do
+		{
+			p = 2.0f * Vector3(GetRandom01(), GetRandom01(), 0.0f) - Vector3(1, 1, 0);
+		} while (dot(p, p) >= 1.0f);
+		
+		return p;
+	}
+
+	Vector3 RandomInUnitSphere()
+	{
+		Vector3 P;
+
+		do
+		{
+			P = 2.0f * Vector3(GetRandom01(), GetRandom01(), GetRandom01()) - Vector3(1, 1, 1);
+		} while (P.squaredLength() >= 1.0f);
+
+		return P;
+	}
+
+	Vector3 Reflect(const Vector3& v, const Vector3& n)
+	{
+		return v - 2 * dot(v, n) * n;
+	}
+
+	bool Refract(const Vector3& v, const Vector3& n, float ni_over_nt, Vector3& refracted)
+	{
+		Vector3 unit_v = unit_vector(v);
+		float NdotV = dot(unit_v, n);
+		float discriminant = 1.0 - ni_over_nt * ni_over_nt * (1 - NdotV * NdotV);
+
+		if (discriminant > 0)
+		{
+			refracted = ni_over_nt * (unit_v - NdotV * n) - sqrt(discriminant) * n;
+			return true;
+		}
+		else
+			return false;
+	}
+
+	float schlick(float cosine, float ref_idx)
+	{
+		float r0 = (1 - ref_idx) / (1 + ref_idx);
+		r0 = r0 * r0;
+		return r0 + (1 - r0)*pow((1 - cosine), 5);
+	}
+}
diff --git a/RayTracer/Ray.h b/RayTracer/Ray.h
new file mode 100644
index 0000000..4eb083b
--- /dev/null
+++ b/RayTracer/Ray.h
@@ -0,0 +1,22 @@
+#pragma once
+
+#include "Vector3.h"
+
+class Ray
+{
+public:
+	Ray() {}
+	Ray(const Vector3& A, const Vector3& B) 
+	{ 
+		origin = A;
+		direction = B; 
+	}
+
+	Vector3 GetRayOrigin() const { return origin; }
+	Vector3 GetRayDirection() const { return direction; }
+	Vector3 GetPointAt(float t) const { return origin + t * direction; }
+
+private:
+	Vector3 origin;
+	Vector3 direction;
+};
\ No newline at end of file
diff --git a/RayTracer/Vector3.cpp b/RayTracer/Vector3.cpp
new file mode 100644
index 0000000..0c9d583
--- /dev/null
+++ b/RayTracer/Vector3.cpp
@@ -0,0 +1,72 @@
+
+#include "Vector3.h"
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+inline Vector3& Vector3::operator+=(const Vector3& v)
+{
+	x += v.x;
+	y += v.y;
+	z += v.z;
+	
+	return *this;
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+inline Vector3& Vector3::operator-=(const Vector3& v)
+{
+	x -= v.x;
+	y -= v.y;
+	z -= v.z;
+
+	return *this;
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+inline Vector3& Vector3::operator*=(const Vector3& v)
+{
+	x *= v.x;
+	y *= v.y;
+	z *= v.z;
+
+	return *this;
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+inline Vector3& Vector3::operator/=(const Vector3& v)
+{
+	x /= v.x;
+	y /= v.y;
+	z /= v.z;
+
+	return *this;
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+inline Vector3& Vector3::operator*=(const float v)
+{
+	x *= v;
+	y *= v;
+	z *= v;
+
+	return *this;
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+inline Vector3& Vector3::operator/=(const float v)
+{
+	x /= v;
+	y /= v;
+	z /= v;
+
+	return *this;
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+inline void Vector3::MakeUnitVector()
+{
+	float k = 1.0 / sqrt(x * x + y * y + z * z);
+	x *= k;
+	y *= k;
+	z *= k;
+}
+/////////////////////////////////////////////////////////////////////////////////////////
\ No newline at end of file
diff --git a/RayTracer/Vector3.h b/RayTracer/Vector3.h
new file mode 100644
index 0000000..eb5cdd8
--- /dev/null
+++ b/RayTracer/Vector3.h
@@ -0,0 +1,99 @@
+#pragma once
+
+#include <math.h>
+#include <stdlib.h>
+#include <iostream>
+
+class Vector3
+{
+public:
+	Vector3() {}
+	Vector3(float _x, float _y, float _z) { x = _x; y = _y; z = _z; }
+
+	inline const Vector3& operator+() const { return *this; }
+	inline Vector3 operator-() { return Vector3(-x, -y, -z); }
+
+	inline Vector3& operator+=(const Vector3& v2);
+	inline Vector3& operator-=(const Vector3& v2);
+	inline Vector3& operator*=(const Vector3& v2);
+	inline Vector3& operator/=(const Vector3& v2);
+	inline Vector3& operator*=(const float t);
+	inline Vector3& operator/=(const float t);
+
+	inline float length() const { return sqrt(x * x + y * y + z * z); }
+	inline float squaredLength() const { return(x*x + y * y + z * z); }
+	inline void  MakeUnitVector();
+
+	float x, y, z;
+};
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+inline std::ostream& operator<<(std::ostream& os, const Vector3& v)
+{
+	os << v.x << " " << v.y << " " << v.z;
+	return os;
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+inline std::istream& operator>>(std::istream &is, Vector3 &v) 
+{
+	is >> v.x >> v.y >> v.z;
+	return is;
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+inline Vector3 operator+(const Vector3& v1, const Vector3& v2)
+{
+	return Vector3(v1.x + v2.x, v1.y + v2.y, v1.z + v2.z);
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+inline Vector3 operator-(const Vector3& v1, const Vector3& v2)
+{
+	return Vector3(v1.x - v2.x, v1.y - v2.y, v1.z - v2.z);
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+inline Vector3 operator*(const Vector3& v1, const Vector3& v2)
+{
+	return Vector3(v1.x * v2.x, v1.y * v2.y, v1.z * v2.z);
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+inline Vector3 operator/(const Vector3& v1, const Vector3& v2)
+{
+	return Vector3(v1.x / v2.x, v1.y / v2.y, v1.z / v2.z);
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+inline Vector3 operator*(float t, const Vector3& v2)
+{
+	return Vector3(t * v2.x, t * v2.y, t * v2.z);
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+inline Vector3 operator/(const Vector3& v2, float t)
+{
+	return Vector3(v2.x / t, v2.y / t, v2.z / t);
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+inline float dot(const Vector3& v1, const Vector3& v2)
+{
+	return v1.x*v2.x + v1.y*v2.y + v1.z*v2.z;
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+inline Vector3 cross(const Vector3& v1, const Vector3& v2)
+{
+	return Vector3((v1.y*v2.z - v1.z*v2.y), (-(v1.x*v2.z - v1.z*v2.x)), (v1.x*v2.y-v1.y*v2.x));
+}
+
+///////////////////////////////////////////////////////////////////////////////////////////////////
+inline Vector3 unit_vector(Vector3 v)
+{
+	return v / v.length();
+}
+
+
+
```

