#version 460

#include "/lib/core/storage.glsl"
#include "/lib/buffers/control.glsl"
#define QUAD_COUNT_BUFFER_QUALIFIERS restrict readonly
#include "/lib/buffers/quad-count.glsl"
#include "/lib/buffers/quad-geometry.glsl"
#define AABB_BUFFER_QUALIFIERS restrict writeonly
#include "/lib/buffers/aabb.glsl"

const ivec3 workGroups = ivec3(256, 1, 1);

layout(local_size_x = 256) in;

void main() {
   if (control.sceneFrozen == 1u) return;

   uint numQuads = min(quadCount, uint(MAX_QUAD_COUNT));

   vec3 lo = vec3(3.402823466e+38);
   vec3 hi = vec3(-3.402823466e+38);
   for (uint id = gl_GlobalInvocationID.x; id < numQuads; id += 65536u) {
      vec3 p0, p1, p2, p3;
      unpackQuadGeometryPositions(quadGeometry[id], p0, p1, p2, p3);
      vec3 qMin = min(min(p0, p1), min(p2, p3));
      vec3 qMax = max(max(p0, p1), max(p2, p3));
      aabbs[id] = makeAABB(qMin, qMax);
      lo = min(lo, qMin);
      hi = max(hi, qMax);
   }
   uvec3 encodedMin = encodeBound(subgroupMin(lo));
   uvec3 encodedMax = encodeBound(subgroupMax(hi));
   if (subgroupElect()) {
      atomicMin(control.boundsMinX, encodedMin.x);
      atomicMin(control.boundsMinY, encodedMin.y);
      atomicMin(control.boundsMinZ, encodedMin.z);
      atomicMax(control.boundsMaxX, encodedMax.x);
      atomicMax(control.boundsMaxY, encodedMax.y);
      atomicMax(control.boundsMaxZ, encodedMax.z);
   }
   if (gl_GlobalInvocationID.x != 0u) return;

   control.prepareDispatchX = numQuads == 0u ? 0u : sortPrepareWorkgroupsForQuadEnd(numQuads);
   control.prepareDispatchY = 1u;
   control.prepareDispatchZ = 1u;

   uint sortWorkgroups = (numQuads + SORT_PART_SIZE - 1u) / SORT_PART_SIZE;
   control.sortDispatchX = sortWorkgroups;
   control.sortDispatchY = 1u;
   control.sortDispatchZ = 1u;

   control.sortTotal = numQuads;

   uint hplocWGs = (numQuads + uint(HPLOC_WG_SIZE) - 1u) / uint(HPLOC_WG_SIZE);
   control.hplocDispatchX = hplocWGs;
   control.hplocDispatchY = 1u;
   control.hplocDispatchZ = 1u;

   control.numBVH2Nodes = 0u;
   control.wideDispatchX = (numQuads + 127u) / 128u;
   control.wideDispatchY = 1u;
   control.wideDispatchZ = 1u;
   control.wideWorkgroups = 0u;
   control.wideTaskCount = numQuads > 1u ? 1u : 0u;
   control.wideNodeCount = numQuads > 1u ? 1u : 0u;
}
