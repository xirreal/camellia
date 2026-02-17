#version 460 compatibility

layout(triangles) in;
layout(points, max_vertices = 0) out;

#define AS_VERTEX
#include "/lib/storage.glsl"
#include "/lib/encoding.glsl"

in vec3 vPlayerPos[];
in vec3 vNormal[];
in vec2 vCoord[];
in float vEmission[];

void main() {
   if (gl_PrimitiveIDIn % 2 != 0) return;

   vec3 pos3 = vPlayerPos[0] + vPlayerPos[2] - vPlayerPos[1];
   vec2 uv3 = vCoord[0] + vCoord[2] - vCoord[1];

   uvec4 ballot = subgroupBallot(true);
   uint ballotCount = subgroupBallotBitCount(ballot);

   uint baseId = INVALID_ID;
   if (subgroupElect()) {
      baseId = atomicAdd(count, ballotCount * 4u);
   }
   baseId = subgroupBroadcastFirst(baseId);

   if (baseId + 3u >= MAX_VERTEX_COUNT) return;

   uint lane = subgroupBallotExclusiveBitCount(ballot);

   baseId += lane * 4u;

   uint n0 = encodeNormal(vNormal[0]);
   uint n1 = encodeNormal(vNormal[1]);
   uint n2 = encodeNormal(vNormal[2]);
   uint n3 = n0;

   vertices[baseId + 0u] = Vertex(vPlayerPos[0], n0, vCoord[0], vEmission[0], 0.0);
   vertices[baseId + 1u] = Vertex(vPlayerPos[1], n1, vCoord[1], vEmission[1], 0.0);
   vertices[baseId + 2u] = Vertex(vPlayerPos[2], n2, vCoord[2], vEmission[2], 0.0);
   vertices[baseId + 3u] = Vertex(pos3, n3, uv3, vEmission[0], 0.0);

   vec3 localMin = min(min(vPlayerPos[0], vPlayerPos[1]), min(vPlayerPos[2], pos3));
   vec3 localMax = max(max(vPlayerPos[0], vPlayerPos[1]), max(vPlayerPos[2], pos3));

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
