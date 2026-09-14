#ifndef HPLOC_BUILD_INCLUDE_GUARD
#define HPLOC_BUILD_INCLUDE_GUARD

#include "/lib/bvh/hploc.glsl"
#include "/lib/buffers/aabb.glsl"
#include "/lib/buffers/morton.glsl"
#include "/lib/buffers/bvh2-node.glsl"

bool loadClusterAABB(uint clusterID, out vec3 bMin, out vec3 bMax) {
   uint primID = getClusterPrimID(clusterID);

   if (isInternalNode(clusterID)) {
      BVH2Node node = bvh2Nodes[primID];
#if BVH_WIDTH == 2
      bMin = min(node.leftMin, node.rightMin);
      bMax = max(node.leftMax, node.rightMax);
#else
      bMin = node.boundsMin;
      bMax = node.boundsMax;
#endif
      return true;
   } else {
      AABB leaf = aabbs[primID];
      bMin = aabbMin(leaf);
      bMax = aabbMax(leaf);
      return true;
   }
}

uvec2 delta32(int a, int b, uint N) {
   if (a < 0 || b >= int(N)) return uvec2(0xFFFFFFFFu);
   uint ca = mortonCodes[a];
   uint cb = mortonCodes[b];
   uint x = ca ^ cb;
   return uvec2(x, uint(a) ^ uint(b));
}

uint findParentID(int L, int R, uint N) {
   uvec2 right = delta32(R, R + 1, N);
   uvec2 left = delta32(L - 1, L, N);
   if (L == 0 || (right.x < left.x || (right.x == left.x && right.y < left.y)))
      return uint(R);
   else
      return uint(L - 1);
}

#endif
