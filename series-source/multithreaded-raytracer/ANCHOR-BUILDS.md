# Building the anchor commits

Every commit this series anchors on, built with the current build system overlaid onto the
old tree. All 31 produce a running executable. Verified 2026-08-16 against `13dcbe3`.

## The recipe

```powershell
git worktree add --detach ../rt-<sha> <sha>
git -C ../rt-<sha> checkout 13dcbe3 -- CMakeLists.txt CMakePresets.json cmake build.ps1
cd ../rt-<sha>
cmake --preset vs2022 <extra flag from the table>
cmake --build build/vs2022 --config Release --parallel
& ./build/vs2022/Release/WindowsRayTracer.exe
```

Run from the worktree root: models and shaders are opened relative to the working
directory, and the `.hdr` is written there when the render finishes.

## Per post

`M` = on master, `G` = on OpenGL. The narrative crossing is post 15.

| Post | Commit | Date | Br | Src | Entry | Extra configure flag |
|---|---|---|---|---|---|---|
| **1-4** | `24e60c1` | 2018-05-13 | MG | 2 | `WinMain` | - |
| **5** | `0114729` | 2018-05-13 | MG | 2 | `WinMain` | - |
|  | `7d1cdb1` | 2018-06-01 | MG | 2 | `WinMain` | - |
| **6** | `55d3021` | 2019-02-25 | M | 12 | `WinMain` | `-DRT_EXCLUDE_SOURCES="RayTracer/Vector3.cpp"` |
|  | `c36fae0` | 2019-04-14 | G | 15 | `main` | `-DRT_EXCLUDE_SOURCES="RayTracer/FlatColor.cpp;RayTracer/Vector3.cpp"` |
|  | `a911dbe` | 2019-12-29 | G | 15 | `main` | `-DRT_EXCLUDE_SOURCES="RayTracer/FlatColor.cpp;RayTracer/Vector3.cpp"` |
| **7** | `06912d4` | 2018-08-26 | MG | 2 | `WinMain` | - |
| **8** | `ef07d36` | 2018-09-03 | MG | 7 | `WinMain` | - |
|  | `befe602` | 2018-09-22 | MG | 7 | `WinMain` | - |
|  | `01bee25` | 2019-05-01 | M | 14 | `WinMain` | `-DRT_EXCLUDE_SOURCES="RayTracer/Vector3.cpp"` |
| **9** | `8b3ab6a` | 2018-11-01 | MG | 9 | `WinMain` | - |
| **10** | `589f360` | 2018-12-20 | M | 9 | `WinMain` | `-DRT_EXCLUDE_SOURCES="RayTracer/Vector3.cpp"` |
|  | `2aadee0` | 2018-12-24 | M | 10 | `WinMain` | `-DRT_EXCLUDE_SOURCES="RayTracer/Vector3.cpp"` |
|  | `8f14d49` | 2018-12-31 | M | 10 | `WinMain` | `-DRT_EXCLUDE_SOURCES="RayTracer/Vector3.cpp"` |
| **11** | `dd2400c` | 2019-05-06 | M | 14 | `WinMain` | `-DRT_EXCLUDE_SOURCES="RayTracer/Vector3.cpp"` |
|  | `a83c30b` | 2019-05-12 | M | 14 | `WinMain` | `-DRT_EXCLUDE_SOURCES="RayTracer/Vector3.cpp"` |
|  | `f4678f7` | 2019-05-12 | M | 14 | `WinMain` | `-DRT_EXCLUDE_SOURCES="RayTracer/Vector3.cpp"` |
| **12** | `da1081d` | 2018-12-08 | M | 9 | `WinMain` | `-DRT_EXCLUDE_SOURCES="RayTracer/Vector3.cpp"` |
|  | `5770d79` | 2019-04-05 | M | 14 | `WinMain` | `-DRT_EXCLUDE_SOURCES="RayTracer/Vector3.cpp"` |
| **13** | `c5e1a44` | 2019-03-04 | M | 13 | `WinMain` | `-DRT_EXCLUDE_SOURCES="RayTracer/Vector3.cpp"` |
|  | `d783830` | 2019-03-04 | M | 13 | `WinMain` | `-DRT_EXCLUDE_SOURCES="RayTracer/Vector3.cpp"` |
|  | `cbb7202` | 2019-04-04 | M | 14 | `WinMain` | `-DRT_EXCLUDE_SOURCES="RayTracer/Vector3.cpp"` |
| **14** | `849e03f` | 2019-02-24 | M | 12 | `WinMain` | `-DRT_EXCLUDE_SOURCES="RayTracer/Vector3.cpp"` |
| **15** | `6064703` | 2018-11-10 | M | 10 | `main` | `-DRT_EXCLUDE_SOURCES="RayTracer/Vector3.cpp;WindowsRayTracer.cpp"` |
|  | `d6488bb` | 2018-11-11 | G | 10 | `main` | `-DRT_EXCLUDE_SOURCES="RayTracer/Vector3.cpp;WindowsRayTracer.cpp"` |
| **16** | `ffc606d` | 2020-01-16 | M | 14 | `WinMain` | `-DRT_EXCLUDE_SOURCES="RayTracer/FlatColor.cpp;RayTracer/Vector3.cpp"` |
|  | `f8aea40` | 2020-01-15 | G | 16 | `main` | `-DRT_EXCLUDE_SOURCES="RayTracer/FlatColor.cpp;RayTracer/Vector3.cpp"` |
|  | `93d09c4` | 2020-04-26 | G | 17 | `main` | `-DRT_EXCLUDE_SOURCES="RayTracer/FlatColor.cpp;RayTracer/Vector3.cpp"` |
| **17** | `44dd135` | 2020-04-11 | G | 17 | `main` | `-DRT_EXCLUDE_SOURCES="RayTracer/FlatColor.cpp;RayTracer/Vector3.cpp"` |
|  | `7e8263a` | 2020-04-26 | G | 17 | `main` | `-DRT_EXCLUDE_SOURCES="RayTracer/FlatColor.cpp;RayTracer/Vector3.cpp"` |
|  | `77bad97` | 2020-05-04 | G | 18 | `main` | `-DRT_EXCLUDE_SOURCES="RayTracer/FlatColor.cpp;RayTracer/Vector3.cpp"` |

## Notes

**The flags come from each commit's own `.vcxproj`.** Anything in the globbed directories
that the project file of the day did not list is passed to `RT_EXCLUDE_SOURCES`, so the
build matches what the commit actually compiled.

**Not every flag is load-bearing.** `Vector3.cpp` and `FlatColor.cpp` are mostly dead files
that compile harmlessly -- `24e60c1` and `77bad97` were both verified to build without any
exclusion. The two that genuinely need it are `6064703` and `d6488bb`, where the old GDI
`WindowsRayTracer.cpp` duplicates the new `Main/Main.cpp` entry point and the link fails
with LNK2005 on `Trace`, `SaveImage` and `TraceColor`.

**Scene, sample count and resolution are compile-time values** in the application source,
so a capture generally means editing the commit before building it.

**The Unity meshes are still here.** `barb1.fbx` and `car.fbx` were removed from the branch
tips for licensing reasons but remain in history, so every anchor above loads its scenes
as written.
