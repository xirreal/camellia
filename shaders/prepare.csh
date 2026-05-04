#version 460

#include "/lib/storage.glsl"
#include "/lib/hploc.glsl"

layout(local_size_x = 256) in;

void main() {
   uint gID = gl_GlobalInvocationID.x;

   uint numQuads = 0;
   vec3 sceneMin;
   vec3 sceneMax;
   if (subgroupElect()) {
      numQuads = min(quadCount, uint(MAX_QUAD_COUNT));
      sceneMax = getSceneMax();
      sceneMin = getSceneMin();
   }
   numQuads = subgroupBroadcastFirst(numQuads);
   sceneMin = subgroupBroadcastFirst(sceneMin);
   sceneMax = subgroupBroadcastFirst(sceneMax);

   if (gID < numQuads) {
      QuadPositions qp = quadPositions[gID];
      vec3 p1 = vec3(qp.p[0], qp.p[1], qp.p[2]);
      vec3 p2 = vec3(qp.p[3], qp.p[4], qp.p[5]);
      vec3 p3 = vec3(qp.p[6], qp.p[7], qp.p[8]);
      vec3 p4 = vec3(qp.p[9], qp.p[10], qp.p[11]);

      vec3 quadCenter = (p1 + p2 + p3 + p4) * 0.25;

      vec3 range = max(sceneMax - sceneMin, vec3(1e-9));

      vec3 normCentroid = (quadCenter - sceneMin) / range;
      uint morton = encodeMorton3D(normCentroid);

      mortonCodes[gID] = morton;
      clusterIndices[gID] = makeLeafID(gID);
      parentIDs[gID] = INVALID_ID;
   }

   if (gID == 0u) {
      uint sortWorkgroups = (numQuads + SORT_WG_SIZE - 1u) / SORT_WG_SIZE;

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
}
