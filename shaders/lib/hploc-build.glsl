#ifndef HPLOC_BUILD_INCLUDE_GUARD
#define HPLOC_BUILD_INCLUDE_GUARD

#include "/lib/hploc.glsl"
#include "/lib/buffers/aabb.glsl"
#include "/lib/buffers/morton.glsl"
#include "/lib/buffers/bvh2-node.glsl"

bool loadClusterAABB(uint clusterID, out vec3 bMin, out vec3 bMax) {
   uint primID = getClusterPrimID(clusterID);

   if (isInternalNode(clusterID)) {
      BVH2Node node = bvh2Nodes[primID];
      bMin = min(node.c0Min, node.c1Min);
      bMax = max(node.c0Max, node.c1Max);
      return true;
   } else {
      AABB leaf = aabbs[primID];
      bMin = aabbMin(leaf);
      bMax = aabbMax(leaf);
      return true;
   }
}

uint delta32(int a, int b, uint N) {
   if (a < 0 || b >= int(N)) return 0xFFFFFFFFu;
   uint ca = mortonCodes[a];
   uint cb = mortonCodes[b];
   uint x = ca ^ cb;
   if (x == 0u) return uint(a) ^ uint(a + 1);
   return x;
}

uint findParentID(int L, int R, uint N) {
   if (L == 0 || (R != int(N) && delta32(R, R + 1, N) < delta32(L - 1, L, N)))
      return uint(R);
   else
      return uint(L - 1);
}

#endif
