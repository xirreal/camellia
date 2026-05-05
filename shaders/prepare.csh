#version 460

#include "/lib/storage.glsl"
#include "/lib/buffers/control.glsl"
#include "/lib/scene-bounds.glsl"
#include "/lib/buffers/quad-data.glsl"
#include "/lib/buffers/quad-pos-read.glsl"
#define AABB_BUFFER_QUALIFIERS restrict writeonly
#include "/lib/buffers/aabb.glsl"
#define MORTON_CODE_BUFFER_QUALIFIERS restrict writeonly
#include "/lib/buffers/morton.glsl"
#define CLUSTER_INDEX_BUFFER_QUALIFIERS restrict writeonly
#include "/lib/buffers/cluster-index.glsl"
#define SORT_SCRATCH_BUFFER_QUALIFIERS restrict writeonly
#include "/lib/buffers/sort-scratch.glsl"
#include "/lib/hploc.glsl"

layout(local_size_x = 256) in;

shared uint sharedNumQuads;
shared vec3 sharedSceneMin;
shared vec3 sharedInvSceneRange;

void main() {
   uint gID = gl_GlobalInvocationID.x;

   if (gl_LocalInvocationID.x == 0u) {
      sharedNumQuads = min(quadCount, uint(MAX_QUAD_COUNT));
      sharedSceneMin = getSceneMin();
      vec3 sceneMax = getSceneMax();
      sharedInvSceneRange = 1.0 / max(sceneMax - sharedSceneMin, vec3(1e-9));
   }
   barrier();

   uint numQuads = sharedNumQuads;
   vec3 sceneMin = sharedSceneMin;
   vec3 invSceneRange = sharedInvSceneRange;

   if (gID < SORT_GLOBAL_HIST_SIZE) {
      sortScratch[SORT_SCRATCH_GLOBAL_HIST + gID] = 0u;
   }

   if (gID < numQuads) {
      QuadPositions qp = quadPositions[gID];
      vec3 p1, p2, p3, p4;
      unpackQuadPositions(qp, p1, p2, p3, p4);

      vec3 quadMin = min(min(p1, p2), min(p3, p4));
      vec3 quadMax = max(max(p1, p2), max(p3, p4));
      vec3 quadCenter = (p1 + p2 + p3 + p4) * 0.25;

      vec3 normCentroid = (quadCenter - sceneMin) * invSceneRange;
      uint morton = encodeMorton3D(normCentroid);

      aabbs[gID] = makeAABB(quadMin, quadMax);
      mortonCodes[gID] = morton;
      clusterIndices[gID] = makeLeafID(gID);
   }

   if (gID == 0u) {
      uint sortWorkgroups = (numQuads + SORT_PART_SIZE - 1u) / SORT_PART_SIZE;

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
