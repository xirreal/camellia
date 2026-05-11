#version 460

#include "/lib/core/settings.glsl"
#include "/lib/core/storage.glsl"
#include "/lib/buffers/control.glsl"
#include "/lib/scene/scene-read.glsl"
#include "/lib/buffers/morton.glsl"
#define CLUSTER_INDEX_BUFFER_QUALIFIERS restrict readonly
#include "/lib/buffers/cluster-index.glsl"
#include "/lib/buffers/quad-pos-read.glsl"
#include "/lib/bvh/hploc.glsl"

layout(local_size_x = 256) in;

void main() {
   uint gID = gl_GlobalInvocationID.x;
   uint N = control.sortTotal;
   if (control.sceneFrozen == 1u) return;

   if (gID >= N) return;

   if (gID < N - 1u) {
      if (mortonCodes[gID] > mortonCodes[gID + 1u]) {
         atomicAdd(control.sortErrors, 1u);
      }
   }

   uint ci = clusterIndices[gID];
   uint quadID = getClusterPrimID(ci);

   if (quadID < N) {
      QuadPositions qp = quadPositions[quadID];
      vec3 p0, p1, p2, p3;
      unpackQuadPositions(qp, p0, p1, p2, p3);
      vec3 quadCenter = (p0 + p1 + p2 + p3) * 0.25;

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
