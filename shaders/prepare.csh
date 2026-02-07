#version 460

// 33554432 / 64 = 524288
const ivec3 workGroups = ivec3(524288, 1, 1);

#define AS_VERTEX
#include "/lib/storage.glsl"
#include "/lib/hploc.glsl"

// x = ---- 9--8 --7- -6-- 5--4 --3- -2-- 1--0
// y = ---9 --8- -7-- 6--5 --4- -3-- 2--1 --0-
// z = --9- -8-- 7--6 --5- -4-- 3--2 --1- -0--
// r = --99 9888 7776 6655 5444 3332 2211 1000
//
// bits from the three axis get interleaved

uint encodeMorton3D(vec3 normalizedPos) {
   uvec3 i = uvec3(clamp(normalizedPos, 0.0, 1.0) * 1023.0);

   i &= 0x000003ffu;
   i = (i ^ (i << 16)) & 0xff0000ffu;
   i = (i ^ (i << 8)) & 0x0300f00fu;
   i = (i ^ (i << 4)) & 0x030c30c3u;
   i = (i ^ (i << 2)) & 0x09249249u;

   return (i.z << 2) | (i.y << 1) | i.x;
}

layout(local_size_x = 64) in;

void main() {
   uint gID = gl_GlobalInvocationID.x;
   if (gID >= count) return;

   vec3 vPos = vertices[gID].position;
   vec3 quadMin = subgroupClusteredMin(vPos, 4);
   vec3 quadMax = subgroupClusteredMax(vPos, 4);
   vec3 quadSum = subgroupClusteredAdd(vPos, 4);

   // every 4th thread is chosen as "leader" for the quad leaf write
   if ((gl_SubgroupInvocationID & 3) == 0 && gID < count) {
      vec3 quadCenter = quadSum * 0.25;

      vec3 sceneMax = getSceneMax();
      vec3 sceneMin = getSceneMin();
      vec3 range = sceneMax - sceneMin;

      vec3 normCentroid = (quadCenter - sceneMin) / range;

      uint morton = encodeMorton3D(normCentroid);

      uint primitiveID = gID >> 2;

      aabs[primitiveID].minBounds = quadMin;
      aabs[primitiveID].maxBounds = quadMax;
      codes[primitiveID] = morton;
      indices[primitiveID] = primitiveID;
      parentIndices[primitiveID] = INVALID_ID;

      if (threadID == 0) {
         // Allocate the wide root node
         uint64_t pair = /*root bvh2 cluster ID*/ (uint64_t(GEOM_ID_BVH2 << 24) << 32ull) | (0ull);
         store < uint64_t > (params.indexPairs, threadID, pair);
         store < int > (params.AC, 3, 1); // global counter of allocated BVH8 nodes
      }
      else {
         uint64_t pair = UINT64_MAX; // invalid pair
         store < uint64_t > (params.indexPairs, threadID, pair);
      }
   }
}
