# Camellia — GPU-Driven BVH Path Tracer for Minecraft (Iris shader pack)

## Build / Test / Debug
- This is an Iris shaderpack; it has no standalone build step.
- Do not use external GLSL validators such as `glslangValidator`. Iris is the authoritative compiler and runtime.
- Use the installed Viewfinder MCP server for shader diagnostics, GPU resources, timings, programs, passes, captures, and controlled singleplayer scenes.
- Use `run_actions` for dependent operations that must not interleave with other MCP requests; independent operations can use singular tools.
- Inspect diagnostics returned by reload tools. Request `get_diagnostics` only when a broader or newer runtime snapshot is needed.
- Use exact Iris program and texture names over GL ids, and always pass an explicit SSBO binding index.
- The NVIDIA binary dumps contain pseudo-assembly in plaintext, with useful information about register and shared memory usage.
- If rendering stops after a shader change, inspect available diagnostics and job status; zero FPS alone does not establish a driver fault. If the change appears to hang the GPU, undo only the implicated edits from the current task, preserving existing work, before retrying. A stalled renderer cannot satisfy a frame-based wait.
- Wait at least 10 rendered frames after a shader reload or scene change before capturing timings or render-state evidence. Put the action-only `wait_frames` in the same `run_actions` job when the workflow must remain non-interleavable.
- Validate affected shader behavior in Iris; reserve profiling for performance questions or suspected regressions. Documentation-only edits do not need a reload, and successful checks need repeating only when new evidence warrants it.

## Style & Conventions
- The primary target is NVIDIA on GLSL 460. AMD and Intel are secondary untested targets, but should still be supported on a best-effort basis.
- GLSL `#version 460` (or `460 compatibility` for raster). Iris features: `COMPUTE_SHADERS SSBO REVERSED_CULLING`. Required: `GL_KHR_shader_subgroup_*`. Wave size assumed 32.
- Includes use shaderpack-absolute paths: `#include "/lib/storage.glsl"`. Include guards: `#ifndef X_INCLUDE_GUARD / #define X_INCLUDE_GUARD`. Never put `#extension` in individual files — they live in `storage.glsl`.
- SSBO declarations are opt-in. Include only the `buffers/*.glsl` files a pass needs, and define qualifier macros before including them when narrower access is valid (for example `CONTROL_BUFFER_QUALIFIERS restrict readonly`, `AABB_BUFFER_QUALIFIERS restrict writeonly`). Do not redeclare the same binding in a pass with different qualifiers.
- Feature toggles via `#define`/`#ifdef` (`ALPHA_TEST`, `ENTITY_TEXTURES`, `ENTITY_PBR`, `ENABLE_DEBUG_OVERLAY`, `ENABLE_QUAD_VALIDATION`, `QUAD_WRITE`); user toggles wired through `shaders.properties` `screen` lines.
- Prefer subgroup ops (`subgroupBallot`, `subgroupBroadcastFirst`, `subgroupElect`, `subgroupExclusiveAdd`, `subgroupShuffle`, `subgroupMin/Max`) over shared memory / atomics. Replacements should have a correctness or measured performance basis.
- File extensions: `.csh` compute, `.vsh` vertex, `.gsh` geometry, `.fsh` fragment, `.glsl` library. Sort/H-PLOC use indirect dispatch via `control.{sortDispatch*,hplocDispatch*}` referenced from `indirect.prepareN`.
- Avoid reserved words (`packed`, `buffer`, `sample`). Append new `ControlBuffer` fields at the end and update `bufferObject.1` size in `shaders.properties`; `MAX_QUAD_COUNT` and SSBO sizes must match between GLSL and `shaders.properties`. Adding/removing sort passes requires updating both `.csh` files and `indirect.prepareN`. Prefer unsized arrays in SSBO or declarations, as big const array or trivially computable array loop bounds cause the NVIDIA GLSL compiler to unroll the entire loop, crashing or slowing down compilation.
- The formats for colortex and clear are intentionally defined in comments, as the RGBA32F/RGBA16F is parsed as text by Iris and is not a GLSL constant. Do not put the directive in a single line comment, or have any other text in the line of the directive, as this may cause it to not be detected properly.
