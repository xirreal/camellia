#version 460

#include "/lib/storage.glsl"
#include "/lib/hploc.glsl"

layout(local_size_x = 256) in;

void main() {
   uint gID = gl_GlobalInvocationID.x;
   uint N = control.sortTotal;

   if (gID < N) {
      parentIDs[gID] = INVALID_ID;

      if (gID < N - 1u) {
         if (mortonCodes[gID] > mortonCodes[gID + 1u]) {
            atomicAdd(control.sortErrors, 1u);
         }
      }

      uint ci = clusterIndices[gID];
      uint quadID = getClusterPrimID(ci);

      if (quadID < N) {
         Quad q = quads[quadID];
         vec3 quadCenter = (q.v1.position + q.v2.position + q.v3.position + q.v4.position) * 0.25;

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
   }
}
