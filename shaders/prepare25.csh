#version 460

//#define ENABLE_SORT_VALIDATION

#include "/lib/storage.glsl"
#include "/lib/hploc.glsl"

layout(local_size_x = 256) in;

void main() {
   uint gID = gl_GlobalInvocationID.x;
   uint N = control.sortTotal;

   if (gID < N) {
      parentIDs[gID] = INVALID_ID;

      #ifdef ENABLE_SORT_VALIDATION
      if (gID < N - 1u) {
         if (mortonCodes[gID] > mortonCodes[gID + 1u]) {
            atomicAdd(control.sortErrors, 1u);
         }
      }

      uint ci = clusterIndices[gID];
      uint quadID = getClusterPrimID(ci);

      if (quadID < N) {
         QuadPositions qp = quadPositions[quadID];
         vec3 quadCenter = (vec3(qp.p[0], qp.p[1], qp.p[2]) + vec3(qp.p[3], qp.p[4], qp.p[5]) + vec3(qp.p[6], qp.p[7], qp.p[8]) + vec3(qp.p[9], qp.p[10], qp.p[11])) * 0.25;

         vec3 sceneMin = getSceneMin();
         vec3 sceneMax = getSceneMax();
         vec3 range = max(sceneMax - sceneMin, vec3(1e-9));
         vec3 normCentroid = (quadCenter - sceneMin) / range;

         uint expectedMorton = encodeMorton3D(normCentroid);
         if (expectedMorton != mortonCodes[gID]) {
            atomicAdd(control.pairErrors, 1u);
         }
      } else {
         atomicAdd(control.pairErrors, 1u);
      }
      #endif
   }
}
