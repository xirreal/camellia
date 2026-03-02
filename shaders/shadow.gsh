#version 460 compatibility

layout(triangles) in;
layout(points, max_vertices = 0) out;

#define AS_VERTEX
#include "/lib/storage.glsl"
#include "/lib/encoding.glsl"

in vec3 vPlayerPos[];
in vec2 vCoord[];
in float vEmission[];
in vec3 vColor[];
flat in uint vBlockId[];

void main() {
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

   uint baseId = INVALID_ID;
   if (subgroupElect()) {
      baseId = atomicAdd(count, ballotCount * 4u);
   }
   baseId = subgroupBroadcastFirst(baseId);

   if (baseId + 3u >= MAX_VERTEX_COUNT) return;

   uint lane = subgroupBallotExclusiveBitCount(ballot);

   baseId += lane * 4u;

   uint encoded0 = encodeVertexData(vColor[i0], vEmission[i0], false);
   uint encoded1 = encodeVertexData(vColor[i1], vEmission[i1], false);
   uint encoded2 = encodeVertexData(vColor[i2], vEmission[i2], false);
   uint encoded3 = encodeVertexData(vColor[i2], vEmission[i2], false);

   uint blockId = vBlockId[i0];
   uint textureId = 0u;

   vertices[baseId + 0u] = Vertex(vPlayerPos[i0], encoded0, vCoord[i0], blockId, textureId);
   vertices[baseId + 1u] = Vertex(vPlayerPos[i1], encoded1, vCoord[i1], blockId, textureId);
   vertices[baseId + 2u] = Vertex(vPlayerPos[i2], encoded2, vCoord[i2], blockId, textureId);
   vertices[baseId + 3u] = Vertex(pos3, encoded3, uv3, blockId, textureId);

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
