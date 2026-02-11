#ifndef HPLOC_INCLUDE_GUARD
#define HPLOC_INCLUDE_GUARD

#define SEARCH_RADIUS_SHIFT 3
#define SEARCH_RADIUS (1u << SEARCH_RADIUS_SHIFT)
#define BVH2_INTERNAL_FLAG 0x80000000u

#define ERROR_OUT_OF_BOUNDS -1
#define ERROR_TIMEOUT -2

#define INVALID_ID 0xFFFFFFFFu

struct AABB {
   vec3 minBounds;
   float _pad0;
   vec3 maxBounds;
   float _pad1;
}; // 32 bytes

struct BVH2Node {
   vec3 aabbMin;
   uint leftChild;
   vec3 aabbMax;
   uint rightChild;
}; // 32 bytes

layout(std430, binding = 2) buffer AABBBuffer {
   AABB aabbs[];
};

layout(std430, binding = 3) buffer MortonCodeBuffer {
   uint mortonCodes[];
};

layout(std430, binding = 4) buffer ClusterIndexBuffer {
   uint clusterIndices[];
};

layout(std430, binding = 5) buffer ParentIDBuffer {
   uint parentIDs[];
};

layout(std430, binding = 6) buffer BVH2NodeBuffer {
   BVH2Node bvh2Nodes[];
};

layout(std430, binding = 7) buffer SortScratchBuffer {
   uint sortScratch[];
};

uint makeClusterID(uint primID, uint flags) {
   return primID | flags;
}

uint getClusterPrimID(uint clusterID) {
   return clusterID & 0x7FFFFFFFu;
}

bool isClusterInternal(uint clusterID) {
   return (clusterID & BVH2_INTERNAL_FLAG) != 0u;
}

float getSurfaceArea(vec3 bMin, vec3 bMax) {
   vec3 d = bMax - bMin;
   return max(2.0 * (d.x * d.y + d.x * d.z + d.y * d.z), 0.0);
}

float distanceFct(vec3 aMin, vec3 aMax, vec3 bMin, vec3 bMax) {
   vec3 mMin = min(aMin, bMin);
   vec3 mMax = max(aMax, bMax);
   vec3 d = mMax - mMin;
   return max(2.0 * (d.x * d.y + d.x * d.z + d.y * d.z), 0.0);
}

uint countTrailingZero(uint x) {
   if (x == 0) {
      return 32;
   }
   return uint(findLSB(x));
}

uint __fns(uvec4 ballot, uint n) {
   uint cumulativeCount = 0u;
   uint indexOffset = 0u;

   for (uint i = 0u; i < 4u; i++) {
      uint currentChunkCount = bitCount(ballot[i]);
      if (n <= cumulativeCount + currentChunkCount) {
         return indexOffset + findNthBitIn32(ballot[i], n - cumulativeCount);
      }
      cumulativeCount += currentChunkCount;
      indexOffset += 32u;
   }
   return INVALID_ID;
}

uint findNthBitIn32(uint mask, uint n) {
   uint i = 0u;
   uint c = bitCount(mask & 0x0000FFFFu);
   if (n > c) {
      i += 16u;
      n -= c;
      mask >>= 16u;
   }
   c = bitCount(mask & 0x000000FFu);
   if (n > c) {
      i += 8u;
      n -= c;
      mask >>= 8u;
   }
   c = bitCount(mask & 0x0000000Fu);
   if (n > c) {
      i += 4u;
      n -= c;
      mask >>= 4u;
   }
   c = bitCount(mask & 0x00000003u);
   if (n > c) {
      i += 2u;
      n -= c;
      mask >>= 2u;
   }
   c = bitCount(mask & 0x00000001u);
   if (n > c) {
      i += 1u;
   }
   return i;
}

uint delta(int a, int b, uint N) {
   if (a < 0 || b >= int(N)) return -1;
   uint ca = mortonCodes[a];
   uint cb = mortonCodes[b];
   uint x = ca ^ cb;
   if (x != 0u) return uint(a) ^ uint(a + 1u);
   return x;
}

uint findParentID(int a, int b, uint N)
{
   return (a == 0 || (b != N && (delta(b, b + 1, N) < delta(a - 1, a, N)))) ? b : a - 1;
}

uint encodeRelativeOffset(uint ID, uint neighbor) {
   uint uOffset = neighbor - ID - 1u;
   return uOffset << 1u;
}

int decodeRelativeOffset(int localID, uint offset, uint ID) {
   int off = int((offset >> 1u) + 1u);
   return localID + (((offset ^ ID) % 2u == 0u) ? off : -off);
}

uint floatToExponent(float num) {
   uint bits = floatBitsToUint(num);
   uint exponentBits = (bits >> 23) & 0xFF;
   return uint(max(min(exponentBits + 1, 254u), 2u));
}

float exponentToFloat(uint exponent) {
   uint bits = exponent << 23;
   return uintBitsToFloat(bits);
}

uint getIMask(uint assignedChildren[8], uint numLeaves) {
   uint iMask = 0;
   for (int i = 0; i < 8; ++i) {
      if (assignedChildren[i] != INVALID_ID) {
         uint relativeIndex = assignedChildren[i];
         if (relativeIndex >= numLeaves) iMask |= (1 << i);
      }
   }
   return iMask;
}

void LoadAABB(uint clusterID, out vec3 bMin, out vec3 bMax) {
   if (isClusterInternal(clusterID)) {
      uint nodeIdx = getClusterPrimID(clusterID);
      bMin = bvh2Nodes[nodeIdx].aabbMin;
      bMax = bvh2Nodes[nodeIdx].aabbMax;
   } else {
      uint quadIdx = clusterID;
      bMin = aabbs[quadIdx].minBounds;
      bMax = aabbs[quadIdx].maxBounds;
   }
}

#endif
