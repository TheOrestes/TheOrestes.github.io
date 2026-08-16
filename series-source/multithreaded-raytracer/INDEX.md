# Windows_RayTracer — blog series source material

17 posts extracted from https://github.com/TheOrestes/Windows_RayTracer

Every file is a **git diff** in a ```diff block, with `external/`, `models/`, and MSVC project
files filtered out. Posts 1–4 diff against the empty tree — the project's first commit dropped
852 lines at once, so those four are file-scoped slices of that single commit and show as all-`+`
additions. Posts 5–17 are ordinary commit-to-commit diffs.

The series follows `master` through the GDI era, then continues on the `OpenGL` branch — which at
the end of that work was 40 commits ahead of master (`ffc606d`..`ceb028e`) and holds the newest
work (through 2020-06-18). Both tips have moved since; the range is pinned here so the count
does not drift.

| # | Post | Source | Anchors |
|---|------|--------|---------|
| 1 | A Win32 window and the dumbest possible canvas | `24e60c1` slice | `24e60c1` |
| 2 | Vectors, rays, a camera, and a gradient sky | `24e60c1` slice | `24e60c1` |
| 3 | Spheres, hit records, and antialiasing | `24e60c1` slice | `24e60c1` |
| 4 | Lambertian, Metal, and dielectrics | `24e60c1` slice | `24e60c1` |
| 5 | First attempt at threading: std::thread and horizontal bands | commit diff | `0114729`, `7d1cdb1` |
| 6 | Fixing it: detached threads, no shared HDC, a real scheduler | commit diff | `55d3021`, `c36fae0`, `a911dbe` |
| 7 | Triangles | commit diff | `06912d4` |
| 8 | A Scene abstraction, and rethinking ownership | commit diff | `ef07d36`, `befe602`, `01bee25` |
| 9 | Assimp, and loading actual meshes | commit diff | `8b3ab6a` |
| 10 | Textures: stb_image and barycentric UVs | commit diff | `589f360`, `2aadee0`, `8f14d49` |
| 11 | A Maya to FBX material and transform pipeline | commit diff | `dd2400c`, `a83c30b`, `f4678f7` |
| 12 | AABBs, and the reflection bug they exposed | commit diff | `da1081d`, `5770d79` |
| 13 | LameBVH and the Profiler system | commit diff | `c5e1a44`, `d783830`, `cbb7202` |
| 14 | An application layer and ray counting | commit diff | `849e03f` |
| 15 | Killing SetPixel: a screen-aligned quad and texture upload | commit diff | `6064703`, `d6488bb` |
| 16 | Samplers and progressive rendering | commit diff | `ffc606d`, `f8aea40`, `93d09c4` |
| 17 | Importance sampling: the failed attempt, then the real one | commit diff | `44dd135`, `7e8263a`, `77bad97` |

## Reading these diffs yourself

The GDI-era sources are UTF-16LE, so git diffs them as binary by default. To fix it in a
checkout of Windows_RayTracer, commit `gitattributes-for-upstream` as `.gitattributes` and run:

    git config diff.utf16.textconv <path-to>/utf16-textconv.sh
    git config diff.utf16.cachetextconv true

Note: `git show --stat` still reports `Bin` (stats come from raw blobs) but the diff body is text.

## Building it today

The repository is public and builds from a clean clone with nothing preinstalled but Visual
Studio 2022 (Desktop development with C++) and git. See `BUILDING.md` upstream:

    git clone https://github.com/TheOrestes/Windows_RayTracer
    cd Windows_RayTracer
    .\build.ps1 -Run

CMake fetches and builds every dependency at configure time — glm, stb, assimp and Open Image
Denoise on `master`, plus GLFW, GLEW and marl on `OpenGL`. The first configure takes a few
minutes, almost all of it assimp. CI builds Debug and Release on all three branches.

VS 2022 specifically: `CMakePresets.json` names the `Visual Studio 17 2022` generator, so that is
the version verified to work. Newer releases may be fine but nothing tests them.

### Building a commit this series actually covers

The build files only exist from `0a569ea` (2026) onward, so checking out a 2019–2020 anchor gets
you that commit's sources with no `CMakeLists.txt`. Overlay the build system onto the old tree
instead of the other way around:

    git worktree add --detach ../rt-<sha> <sha>
    git -C ../rt-<sha> checkout 0a569ea -- CMakeLists.txt CMakePresets.json cmake build.ps1
    cd ../rt-<sha>
    .\build.ps1 -Run

Sources are globbed and the dependency set is detected from the includes, so the same build files
work across the GDI and OpenGL layouts unchanged. Use `git -C <worktree>`, not
`git --work-tree=`, which writes into the main checkout too.

The renderer writes an `.hdr` into the working directory when it finishes, so run it from the
worktree root. Scene, sample count and resolution are compile-time values in `Application.cpp`.

Two Unity Asset Store meshes (`barb1.fbx`, `car.fbx`) were removed from the branch tips for
licensing reasons, but they remain in history — every commit this series covers still has them,
so the scenes in these posts load as written.

## Deliberately excluded

- 16 README-only commits, 5 merges, ~7 vendor/asset dumps
- The enkiTS "experiment" — it only ever existed as vendored code in `external/` plus one
  `#elif defined ENKITS` macro branch; there is no meaningful source diff for it
- Duplicate implementations on master vs OpenGL (AABB, textures, BVH, samplers, denoiser
  were each written twice); the series follows one path
