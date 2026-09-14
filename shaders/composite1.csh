#version 460

#include "/lib/core/storage.glsl"
#include "/lib/buffers/control.glsl"
#include "/lib/scene/scene-read.glsl"
#define AABB_BUFFER_QUALIFIERS restrict readonly
#include "/lib/buffers/aabb.glsl"
#define MORTON_CODE_BUFFER_QUALIFIERS restrict writeonly
#include "/lib/buffers/morton.glsl"
#define CLUSTER_INDEX_BUFFER_QUALIFIERS restrict writeonly
#include "/lib/buffers/cluster-index.glsl"
#define SORT_SCRATCH_BUFFER_QUALIFIERS restrict writeonly
#include "/lib/buffers/sort-scratch.glsl"
#include "/lib/bvh/hploc.glsl"

layout(local_size_x = 256) in;

void main() {
   uint gID = gl_GlobalInvocationID.x;

   uint numQuads = 0u;
   vec3 sceneMin = vec3(0.0);
   vec3 invSceneRange = vec3(0.0);
   if (subgroupElect()) {
      numQuads = control.sortTotal;
      sceneMin = getSceneMin();
      vec3 sceneMax = getSceneMax();
      invSceneRange = 1.0 / max(sceneMax - sceneMin, vec3(1e-9));
   }
   numQuads = subgroupBroadcastFirst(numQuads);
   sceneMin = subgroupBroadcastFirst(sceneMin);
   invSceneRange = subgroupBroadcastFirst(invSceneRange);

   if (gID < SORT_GLOBAL_HIST_SIZE) {
      sortScratch[SORT_SCRATCH_GLOBAL_HIST + gID] = 0u;
   }

   if (gID < numQuads) {
      AABB box = aabbs[gID];
      vec3 quadCenter = (aabbMin(box) + aabbMax(box)) * 0.5;

      vec3 normCentroid = (quadCenter - sceneMin) * invSceneRange;
      uint morton = encodeMorton3D(normCentroid);

      mortonCodes[gID] = morton;
      clusterIndices[gID] = makeLeafID(gID);
   }
}
