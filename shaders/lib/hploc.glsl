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

#define SEARCH_RADIUS_SHIFT 3
#define SEARCH_RADIUS (1u << SEARCH_RADIUS_SHIFT)

#define ERROR_OUT_OF_BOUNDS 1u
#define ERROR_TIMEOUT 2u

struct BVH2Node {
   vec3 c0Min;
   uint leftChild;
   vec3 c0Max;
   uint rightChild;
   vec3 c1Min;
   float _pad0;
   vec3 c1Max;
   float _pad1;
}; // 64 bytes

struct QuadPositions {
   vec4 p0p1x;    // p0.xyz, p1.x
   vec4 p1yzp2xy; // p1.yz, p2.xy
   vec4 p2zp3;    // p2.z, p3.xyz
}; // 48 bytes

void unpackQuadPositions(QuadPositions qp, out vec3 p0, out vec3 p1, out vec3 p2, out vec3 p3) {
   p0 = qp.p0p1x.xyz;
   p1 = vec3(qp.p0p1x.w, qp.p1yzp2xy.xy);
   p2 = vec3(qp.p1yzp2xy.zw, qp.p2zp3.x);
   p3 = qp.p2zp3.yzw;
}

layout(std430, binding = 3) restrict buffer MortonCodeBuffer {
   uint mortonCodes[];
};

layout(std430, binding = 4) restrict coherent buffer ClusterIndexBuffer {
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

layout(std430, binding = 10) restrict buffer QuadPosBuffer {
   QuadPositions quadPositions[];
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
