#version 460 compatibility

layout(triangles) in;
layout(points, max_vertices = 0) out;

#define QUAD_WRITE
#include "/lib/core/storage.glsl"
#include "/lib/scene/quad-write.glsl"

flat in vec3 vPlayerPos[];
flat in vec2 vCoord[];
flat in float vEmission[];
flat in vec3 vColor[];
flat in uint vBlockId[];

void main() {
   if (control.sceneFrozen != 0u) return;

   int i0 = 0;
   int i1 = 1;
   int i2 = 2;

   if ((gl_PrimitiveIDIn & 1) != 0) {
      i0 = 1;
      i1 = 0;
   }

   vec3 pos3 = vPlayerPos[i2];
   vec2 uv3 = vCoord[i2];

   uvec4 ballot = subgroupBallot(true);
   uint ballotCount = subgroupBallotBitCount(ballot);

   uint baseQuad = INVALID_ID;
   if (subgroupElect()) {
      baseQuad = atomicAdd(quadCount, ballotCount);
   }
   baseQuad = subgroupBroadcastFirst(baseQuad);

   if (baseQuad + ballotCount > MAX_QUAD_COUNT) return;

   uint lane = subgroupBallotExclusiveBitCount(ballot);
   uint quadID = baseQuad + lane;

   writeQuadRecords(
      quadID, vPlayerPos[i0], vPlayerPos[i1], vPlayerPos[i2], pos3,
      vCoord[i0], vCoord[i1], vCoord[i2], vColor[i0],
      vBlockId[i0], 0u, vEmission[i0], false, false, false
   );

}
