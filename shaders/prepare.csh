#version 460

const ivec3 workGroups = ivec3(131072, 1, 1);

#include "/lib/storage.glsl"
#include "/lib/hploc.glsl"

layout(local_size_x = 64) in;

void main() {
   uint gID = gl_GlobalInvocationID.x;
   uint numQuads = min(count >> 2u, MAX_QUAD_COUNT);

   if (gID < numQuads) {
      Quad q = quads[gID];

      vec3 p1 = q.v1.position;
      vec3 p2 = q.v2.position;
      vec3 p3 = q.v3.position;
      vec3 p4 = q.v4.position;

      vec3 quadMin = min(min(p1, p2), min(p3, p4));
      vec3 quadMax = max(max(p1, p2), max(p3, p4));
      vec3 quadCenter = (p1 + p2 + p3 + p4) * 0.25;

      vec3 sceneMax = getSceneMax();
      vec3 sceneMin = getSceneMin();
      vec3 range = max(sceneMax - sceneMin, vec3(1e-9));

      vec3 normCentroid = (quadCenter - sceneMin) / range;
      uint morton = encodeMorton3D(normCentroid);

      aabbs[gID] = AABB(quadMin, 0.0, quadMax, 0.0);
      mortonCodes[gID] = morton;
      clusterIndices[gID] = makeClusterID(gID, 0u);
      parentIDs[gID] = INVALID_ID;
   }

   if (gID == 0u) {
      uint N = count >> 2u;
      N = min(N, MAX_QUAD_COUNT);

      uint sortWorkgroups = (N + SORT_WG_SIZE - 1u) / SORT_WG_SIZE;

      control.sortDispatchX = sortWorkgroups;
      control.sortDispatchY = 1u;
      control.sortDispatchZ = 1u;

      control.sortScatterX = sortWorkgroups;
      control.sortScatterY = 1u;
      control.sortScatterZ = 1u;

      uint hplocWorkgroups = (N + WAVE_SIZE - 1u) / WAVE_SIZE;
      control.hplocDispatchX = hplocWorkgroups;
      control.hplocDispatchY = 1u;
      control.hplocDispatchZ = 1u;

      control.sortTotal = N;
   }
}
