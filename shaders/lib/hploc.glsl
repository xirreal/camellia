#ifndef HPLOC_INCLUDE_GUARD
#define HPLOC_INCLUDE_GUARD

/*
   H-PLOC: Hierarchical Parallel Locally-Ordered Clustering
   for Bounding Volume Hierarchy Construction

   https://gpuopen.com/download/HPLOC.pdf
   GLSL port based on Slang implementation by natevm
   https://gist.github.com/natevm/6618402427ad6466bf555d67602adfa8
*/

// Cluster ID layout: bit 31 = internal (BVH2 node) flag, bits 0-30 = primID
// INVALID_ID (0xFFFFFFFF) must be checked before decoding.
#define CLUSTER_INTERNAL_BIT 0x80000000u
#define CLUSTER_PRIM_MASK    0x7FFFFFFFu

#define WAVE_SIZE WG_SIZE
#define SEARCH_RADIUS_SHIFT 3
#define SEARCH_RADIUS (1u << SEARCH_RADIUS_SHIFT)

#define ERROR_OUT_OF_BOUNDS 1u
#define ERROR_TIMEOUT 2u

struct AABB {
   vec3 minBounds;
   float _pad0;
   vec3 maxBounds;
   float _pad1;
}; // 32 bytes (i dont like the padding though grr)

struct BVH2Node {
   vec3 aabbMin;
   uint leftChild;
   vec3 aabbMax;
   uint rightChild;
}; // 32 bytes

layout(std430, binding = 2) restrict buffer AABBBuffer {
   AABB aabbs[];
};

layout(std430, binding = 3) restrict buffer MortonCodeBuffer {
   uint mortonCodes[];
};

layout(std430, binding = 4) coherent buffer ClusterIndexBuffer {
   uint clusterIndices[];
};

layout(std430, binding = 5) restrict buffer ParentIDBuffer {
   uint parentIDs[];
};

layout(std430, binding = 6) restrict buffer BVH2NodeBuffer {
   BVH2Node bvh2Nodes[];
};

layout(std430, binding = 7) restrict buffer SortScratchBuffer {
   uint sortScratch[];
};

uint makeLeafID(uint primID) {
   return primID & CLUSTER_PRIM_MASK;
}

uint makeInternalID(uint primID) {
   return CLUSTER_INTERNAL_BIT | (primID & CLUSTER_PRIM_MASK);
}

uint getClusterPrimID(uint clusterID) {
   return clusterID & CLUSTER_PRIM_MASK;
}

bool isInternalNode(uint clusterID) {
   return (clusterID & CLUSTER_INTERNAL_BIT) != 0u;
}

bool loadClusterAABB(uint clusterID, out vec3 bMin, out vec3 bMax) {
   uint primID = getClusterPrimID(clusterID);

   if (isInternalNode(clusterID)) {
      BVH2Node node = bvh2Nodes[primID];
      bMin = node.aabbMin;
      bMax = node.aabbMax;
      return true;
   } else {
      bMin = aabbs[primID].minBounds;
      bMax = aabbs[primID].maxBounds;
      return true;
   }
}

float computeSurfaceArea(vec3 bMin, vec3 bMax) {
   vec3 d = bMax - bMin;
   return max(2.0 * (d.x * d.y + d.x * d.z + d.y * d.z), 0.0);
}

float computeMergedSurfaceArea(vec3 aMin, vec3 aMax, vec3 bMin, vec3 bMax) {
   vec3 d = max(aMax, bMax) - min(aMin, bMin);
   return max(2.0 * (d.x * d.y + d.x * d.z + d.y * d.z), 0.0);
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

uint encodeRelativeOffset(uint ID, uint neighbor) {
   uint uOffset = neighbor - ID - 1u;
   return uOffset << 1u;
}

int decodeRelativeOffset(int localID, uint offset, uint ID) {
   uint off = (offset >> 1u) + 1u;
   return localID + (((offset ^ ID) % 2u == 0u) ? int(off) : -int(off));
}

#endif
