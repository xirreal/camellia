#version 460 compatibility

layout(triangles) in;
layout(points, max_vertices = 0) out;

#define AS_VERTEX
#include "/lib/storage.glsl"

in vec3 vPlayerPos[];
in vec2 vCoord[];
in float vEmission[];
in vec3 vColor[];
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

   writeQuadMaterial(quadID, vBlockId[i0], 0u, vEmission[i0], false, false, false);

   writeQuadVertex(quadID, 0u, vPlayerPos[i0], vCoord[i0], vColor[i0]);
   writeQuadVertex(quadID, 1u, vPlayerPos[i1], vCoord[i1], vColor[i1]);
   writeQuadVertex(quadID, 2u, vPlayerPos[i2], vCoord[i2], vColor[i2]);
   writeQuadVertex(quadID, 3u, pos3, uv3, vColor[i2]);

   vec3 localMin = min(min(vPlayerPos[i0], vPlayerPos[i1]), min(vPlayerPos[i2], pos3));
   vec3 localMax = max(max(vPlayerPos[i0], vPlayerPos[i1]), max(vPlayerPos[i2], pos3));

   vec3 sMin = subgroupMin(localMin);
   vec3 sMax = subgroupMax(localMax);

   if (subgroupElect()) {
      uvec3 uMin = encodeBound(sMin);
      uvec3 uMax = encodeBound(sMax);

      atomicMin(control.boundsMinX, uMin.x);
      atomicMin(control.boundsMinY, uMin.y);
      atomicMin(control.boundsMinZ, uMin.z);

      atomicMax(control.boundsMaxX, uMax.x);
      atomicMax(control.boundsMaxY, uMax.y);
      atomicMax(control.boundsMaxZ, uMax.z);
   }
}
