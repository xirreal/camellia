#version 460

#include "/lib/core/storage.glsl"
#include "/lib/buffers/control.glsl"
#define QUAD_DATA_BUFFER_QUALIFIERS restrict readonly
#include "/lib/buffers/quad-data.glsl"

const ivec3 workGroups = ivec3(1, 1, 1);

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

void main() {
   if (control.sceneFrozen == 1u) return;

   uint numQuads = min(quadCount, uint(MAX_QUAD_COUNT));

   control.prepareDispatchX = numQuads == 0u ? 0u : sortPrepareWorkgroupsForQuadEnd(numQuads);
   control.prepareDispatchY = 1u;
   control.prepareDispatchZ = 1u;

   uint sortWorkgroups = (numQuads + SORT_PART_SIZE - 1u) / SORT_PART_SIZE;
   control.sortDispatchX = sortWorkgroups;
   control.sortDispatchY = 1u;
   control.sortDispatchZ = 1u;

   control.sortTotal = numQuads;

   uint hplocWGs = (numQuads + uint(WAVE_SIZE) - 1u) / uint(WAVE_SIZE);
   control.hplocDispatchX = hplocWGs;
   control.hplocDispatchY = 1u;
   control.hplocDispatchZ = 1u;

   control.numBVH2Nodes = 0u;
}
