## Debug overlay

| Overlay / decoder field | Meaning and label |
| --- | --- |
| Full / `full` | All four physical lanes exist. Means that a quad is fully loaded into the "workgroup". label: `tests`. |
| Order / `ordered` | Four consecutive vertex IDs, with the same instance, base vertex and draw ID. label: `tests`; incomplete quads WILL fail. |
| Align / `aligned` | `(firstVertexID - baseVertex) % 4 == 0`. This checks Minecraft's expected quad boundary separately from consecutiveness. label: `tests`. |
| Select / `selected` | All lanes of a potential quad are selected correctly. Quads should be fully rejected or accepted with gbuffers capture, never something in between. label: `tests`. |
| Allocator / `allocated` | A selected quad has four equal, **valid**, in-range quad IDs. label: `enabled` quartets. |
| Slots / `slots` | Those four selected lanes receive slots 0, 1, 2, 3 in physical order, preserving winding order. label: `enabled`. |
| Ops / `operations` | Checks the actual allocator election, ballot count, exclusive rank, and broadcast base against bit counts and a shuffle from the first live lane. `operations` counts failing **subgroups**, out of `groups` |
| Write src / `writeSources` | At write, all four source lanes should participate, target the same quad ID, and write to slots 0–3. This checks `lane - slot`. label: `writeTests` vertex invocations. |
| Write data / `writeData` | Sanity check that quad data isnt corrutped. label: `writeTests`. |
| Dropped / `capacity` | Overflowed capacity. Zero is expected, unless at 32RD or dropping VRAM/quad buffer size |

The path table shows a gray row if the corresponding path was no called, otherwise 0 if the shader ran but no geometry was written.

| ID | Path | Useful scene |
| --- | --- | --- |
| 0 | Shadow solid | Opaque terrain |
| 1 | Shadow cutout | Leaves, grass |
| 2 | Shadow water/translucent | Water and glass |
| 3 | Shadow entities | Player and entity |
| 4 | Shadow block entities | Chests, signs, banners |
| 5 | G-buffer solid | Opaque terrain in frustum `SHADOW_CAPTURE_DISTANCE` with `ENABLE_GBUFFER_CAPTURE` on |
| 6 | G-buffer cutout | See above |
| 7 | G-buffer water | See above |
| 8 | G-buffer layers | Banner/sign layers (block entity IDs 3/4) |
| 9 | Fallback shadow triangles | Draws using `shadow.gsh`, which ideally should never happen. This is like the slowest path and i think only leashes use this. Maybe mods too! idk |

## Dump guide

1. Enable debug overlay and subgroup validation. Use reference PT and Chunks set to 2.

2. Position yourself in the scene and press F1 to freeze geometry. Then run

   ```text
   /viewfinder ssbo dump 0
   /viewfinder ssbo dump 1
   /viewfinder ssbo dump 10
   /viewfinder ssbo dump 11
   ```

   The dump will be put into `<game directory>/ssbo_dumps/ssbo_X.bin`. Game may freeze for a second, or two, or 10.

3. Send me the stuff
