# Camellia — GPU-Driven BVH Path Tracer for Minecraft (Iris shader pack)

## Build / Test / Debug
- No build step — it's a shader pack loaded by Iris. There is no test framework; "running a single test" is not applicable.
- Live debug API on `http://localhost:7150`: `GET /`, `GET /status`, `POST /reload`, `GET /errors`, `POST /screenshot?frames=N` + `GET /screenshot/result`, `GET /metrics`, `GET /list-ssbo`, `POST /ssbo?index=N&format=uint|float|int`, `GET /patched_shaders`, `GET /list-textures`, `POST /texture?name=colortex0` (or `id=`, `raw=true`).
- After editing a shader, `POST /reload` then `GET /errors`. Use `POST /screenshot` + `GET /screenshot/result` to verify visuals.
- If required, `POST /ssbo?index=N&format=uint` to dump SSBOs for debugging

## Architecture
Pipeline order: `setup.csh` (once) → shadow pass (`shadow_{solid,block,entities,cutout,water}.{vsh,fsh}` capture geometry into SSBOs; `shadow.{vsh,gsh,fsh}` is fallback) → `begin.csh` (per-frame reset; freezes when `hideGUI`) → `prepare.csh`+`prepare2..13.csh` + `prepare99.csh` (Morton codes + 8.5-pass radix sort, indirectly dispatched) → `composite.csh` (H-PLOC BVH2 build) → `composite1.csh` (optional quad validation) → `composite10.csh` (main path tracer, accumulate radiance) → `composite99.csh` (AgX tonemap + debug HUD).
Libs in `shaders/lib/`: `storage.glsl` (extensions, shared structs/constants, pure helpers), `buffers/*.glsl` (one SSBO declaration per binding with overridable qualifier macros), `quad-read.glsl`/`quad-write.glsl`, `scene-read.glsl`/`scene-bounds.glsl`, `hploc.glsl` (buffer-independent H-PLOC IDs/math), `hploc-build.glsl` (buffer-dependent BVH build helpers), `sort.glsl` (parameterized by `SORT_PASS`/`SORT_PHASE`), `raytrace.glsl`, `encoding.glsl`, `textures.glsl`, `text-rendering.glsl`, `agx.glsl`. SSBO bindings 0–10: QuadData, Control, AABB, Morton, ClusterIndex, ParentID, BVH2Node, SortScratch, TextureInfos, TextureData, QuadPos. All geometry is in **player space**.

## Style & Conventions
- GLSL `#version 460` (or `460 compatibility` for raster). Iris features: `COMPUTE_SHADERS SSBO REVERSED_CULLING`. Required: `GL_KHR_shader_subgroup_*`. Wave size assumed 32.
- Includes use shaderpack-absolute paths: `#include "/lib/storage.glsl"`. Include guards: `#ifndef X_INCLUDE_GUARD / #define X_INCLUDE_GUARD`. Never put `#extension` in individual files — they live in `storage.glsl`.
- SSBO declarations are opt-in. Include only the `buffers/*.glsl` files a pass needs, and define qualifier macros before including them when narrower access is valid (for example `CONTROL_BUFFER_QUALIFIERS restrict readonly`, `AABB_BUFFER_QUALIFIERS restrict writeonly`). Do not redeclare the same binding in a pass with different qualifiers.
- Feature toggles via `#define`/`#ifdef` (`ALPHA_TEST`, `ENTITY_TEXTURES`, `ENTITY_PBR`, `ENABLE_DEBUG_OVERLAY`, `ENABLE_QUAD_VALIDATION`, `QUAD_WRITE`); user toggles wired through `shaders.properties` `screen` lines.
- Prefer subgroup ops (`subgroupBallot`, `subgroupBroadcastFirst`, `subgroupElect`, `subgroupExclusiveAdd`, `subgroupShuffle`, `subgroupMin/Max`) over shared memory / atomics — do **not** rewrite them without a correctness reason.
- File extensions: `.csh` compute, `.vsh` vertex, `.gsh` geometry, `.fsh` fragment, `.glsl` library. Sort/H-PLOC use indirect dispatch via `control.{sortDispatch*,hplocDispatch*}` referenced from `indirect.prepareN`.
- Avoid reserved words (`packed`, `buffer`, `sample`). Append new `ControlBuffer` fields at the end and update `bufferObject.1` size in `shaders.properties`; `MAX_QUAD_COUNT` and SSBO sizes must match between GLSL and `shaders.properties`. Adding/removing sort passes requires updating both `.csh` files and `indirect.prepareN`. NVIDIA is the primary target; AMD/Intel must still work on GL 4.6.
- Do not manually check compilation with glslangValidator, use the debug API. If the API is not available, assume it compiles correctly.
