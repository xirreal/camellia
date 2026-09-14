#version 460

/*
   H-PLOC: Hierarchical Parallel Locally-Ordered Clustering
   for Bounding Volume Hierarchy Construction

   GLSL port based on Slang implementation by natevm
   https://gist.github.com/natevm/6618402427ad6466bf555d67602adfa8
*/

#include "/lib/core/storage.glsl"
#include "/lib/buffers/control.glsl"
#include "/lib/buffers/cluster-index.glsl"
#include "/lib/buffers/parent-id.glsl"
#define BVH2_NODE_BUFFER_QUALIFIERS restrict coherent
#include "/lib/buffers/bvh2-node.glsl"
#include "/lib/bvh/hploc-build.glsl"

layout(local_size_x = HPLOC_WG_SIZE) in;

// Select the rank-th live lane without shared-memory scatter/gather.
uint hplocSelectBit(uint mask, uint rank) {
   uint bit = 0u;
   uint count = bitCount(mask & 0xffffu);
   if (rank >= count) { rank -= count; mask >>= 16u; bit += 16u; }
   count = bitCount(mask & 0xffu);
   if (rank >= count) { rank -= count; mask >>= 8u; bit += 8u; }
   count = bitCount(mask & 0xfu);
   if (rank >= count) { rank -= count; mask >>= 4u; bit += 4u; }
   count = bitCount(mask & 0x3u);
   if (rank >= count) { rank -= count; mask >>= 2u; bit += 2u; }
   return bit + uint(rank >= (mask & 1u));
}

uint hplocSubgroupSize() {
   return min(gl_SubgroupSize, uint(HPLOC_WG_SIZE));
}

uint hplocFirstBallotBit(uvec4 mask) {
#ifdef MC_GL_VENDOR_AMD
   if (mask.x != 0u) return uint(findLSB(mask.x));
   if (mask.y != 0u) return 32u + uint(findLSB(mask.y));
   return 0u;
#else
   return uint(findLSB(mask.x));
#endif
}

uint findNearestNeighbor(uint numPrims, vec3 boundsMin, vec3 boundsMax) {
   uint localID = gl_SubgroupInvocationID;
   const uint encode_mask = ~(((1u << (SEARCH_RADIUS_SHIFT + 1u)) - 1u));
   uint nearest = INVALID_ID;

   for (uint r = 1u; r <= SEARCH_RADIUS; r++) {
      vec3 nbMin = subgroupShuffleDown(boundsMin, r);
      vec3 nbMax = subgroupShuffleDown(boundsMax, r);

      uint pairArea = INVALID_ID;
      if ((localID + r) < numPrims) {
         float newArea = computeMergedSurfaceArea(boundsMin, boundsMax, nbMin, nbMax);
         pairArea = (floatBitsToUint(newArea) << 1u) & encode_mask;
         uint encode0 = encodeRelativeOffset(localID, localID + r);
         nearest = min(nearest, pairArea | encode0 | (localID & 1u));
      }

      uint leftArea = subgroupShuffleUp(pairArea, r);
      if (localID >= r && localID < numPrims) {
         uint encode0 = encodeRelativeOffset(localID - r, localID);
         nearest = min(nearest, leftArea | encode0 | ((localID & 1u) ^ 1u));
      }
   }

   return nearest;
}

uint mergeClustersCreateBVH2Node(
   uint numPrims, uint NN,
   inout uint CI, inout vec3 boundsMin, inout vec3 boundsMax
) {
   uint localID = gl_SubgroupInvocationID;
   uint subgroupSize = hplocSubgroupSize();
   bool laneHasCluster = localID < numPrims;

   const uint decode_mask = ((1u << (SEARCH_RADIUS_SHIFT + 1u)) - 1u);

   uint safeNN = laneHasCluster ? NN : 0u;
   uint n_i_raw = laneHasCluster
      ? uint(decodeRelativeOffset(int(localID), safeNN & decode_mask, localID)) : localID;
   uint n_i = clamp(n_i_raw, 0u, subgroupSize - 1u);

   uint neighborNN = subgroupShuffle(safeNN, n_i);
   uint n_i_n_i_raw = laneHasCluster
      ? uint(decodeRelativeOffset(int(n_i), neighborNN & decode_mask, n_i)) : localID;
   uint n_i_n_i = clamp(n_i_n_i_raw, 0u, subgroupSize - 1u);

   bool symmetricMatch = laneHasCluster && (localID == n_i_n_i);
   bool laneIsLeft = localID < n_i;
   bool laneIsCreatingNode = laneHasCluster && symmetricMatch && laneIsLeft;

   uint leftCI = CI;
   uint rightCI = subgroupShuffle(CI, n_i);
   vec3 leftMin = boundsMin;
   vec3 leftMax = boundsMax;
   vec3 rightMin = subgroupShuffle(boundsMin, n_i);
   vec3 rightMax = subgroupShuffle(boundsMax, n_i);

   uvec4 createMask = subgroupBallot(laneIsCreatingNode);
   uint numNewNodes = subgroupBallotBitCount(createMask);

   uint baseNodeOffset = 0u;
   if (subgroupElect()) {
      baseNodeOffset = atomicAdd(control.numBVH2Nodes, numNewNodes);
   }
   baseNodeOffset = subgroupBroadcastFirst(baseNodeOffset);

   uint bvh2IndexPrefix = subgroupBallotExclusiveBitCount(createMask);
   uint bvh2Index = baseNodeOffset + bvh2IndexPrefix;

   uint newCI = CI;
   if (laneHasCluster) {
      if (symmetricMatch) {
         if (laneIsLeft) {
            vec3 newMin = min(leftMin, rightMin);
            vec3 newMax = max(leftMax, rightMax);

#if BVH_WIDTH == 2
            bvh2Nodes[bvh2Index] = BVH2Node(leftMin, leftCI, leftMax, rightCI, rightMin, 0u, rightMax, 0u);
#else
            bvh2Nodes[bvh2Index] = BVH2Node(newMin, leftCI, newMax, rightCI);
#endif
            boundsMin = newMin;
            boundsMax = newMax;
            newCI = makeInternalID(bvh2Index);
         } else {
            newCI = INVALID_ID;
         }
      }
   }

   bool keepLane = laneHasCluster && (newCI != INVALID_ID);
   uvec4 keepMask = subgroupBallot(keepLane);
   uint totalRemaining = subgroupBallotBitCount(keepMask);

   uint lowerCount = bitCount(keepMask.x);
   uint rank = min(localID, totalRemaining - 1u);
   uint source = rank < lowerCount ? hplocSelectBit(keepMask.x, rank)
      : 32u + hplocSelectBit(keepMask.y, rank - lowerCount);
   uint nextCI = subgroupShuffle(newCI, source);
   vec3 nextMin = subgroupShuffle(boundsMin, source);
   vec3 nextMax = subgroupShuffle(boundsMax, source);

   if (localID < totalRemaining) {
      CI = nextCI;
      boundsMin = nextMin;
      boundsMax = nextMax;
   } else {
      CI = INVALID_ID;
      boundsMin = vec3(1e38);
      boundsMax = vec3(-1e38);
   }

   return totalRemaining;
}

uint loadIndicesFromBuffer(uint start, uint end, inout uint CI, uint offset) {
   uint localID = gl_SubgroupInvocationID;
   uint numIndices = min(end - start, hplocSubgroupSize() / 2u);
   int indexID = int(localID) - int(offset);
   bool laneActive = (localID >= offset) && (uint(indexID) < numIndices);
   if (laneActive) {
      CI = clusterIndices[start + uint(indexID)];
   }
   uvec4 validMask = subgroupBallot(laneActive && CI != INVALID_ID);
   uint numValid = subgroupBallotBitCount(validMask);
   return min(numIndices, numValid);
}

void storeIndicesToBuffer(uint origNumPrims, uint CI, uint LStart) {
   uint localID = gl_SubgroupInvocationID;
   if (localID < origNumPrims) {
      clusterIndices[LStart + localID] = CI;
   }
}

void plocMerge(uint selectedLaneID, uint L, uint R, uint S, bool isFinal) {
   uint localID = gl_SubgroupInvocationID;

   uint LStart = subgroupShuffle(L, selectedLaneID);
   uint REnd = subgroupShuffle(R, selectedLaneID) + 1u;
   uint LEnd = subgroupShuffle(S, selectedLaneID);
   uint RStart = LEnd;

   uint CI = INVALID_ID;
   uint numLeft = loadIndicesFromBuffer(LStart, LEnd, CI, 0u);
   uint numRight = loadIndicesFromBuffer(RStart, REnd, CI, numLeft);
   uint numPrims = numLeft + numRight;

   vec3 boundsMin = vec3(1e38);
   vec3 boundsMax = vec3(-1e38);
   if (localID < numPrims && CI != INVALID_ID) {
      loadClusterAABB(CI, boundsMin, boundsMax);
   }

   bool finalBroadcast = subgroupShuffle(isFinal, selectedLaneID);
   uint threshold = finalBroadcast ? 1u : hplocSubgroupSize() / 2u;

   while (numPrims > threshold) {
      uint NN = findNearestNeighbor(numPrims, boundsMin, boundsMax);
      numPrims = mergeClustersCreateBVH2Node(numPrims, NN, CI, boundsMin, boundsMax);
   }

   storeIndicesToBuffer(numLeft + numRight, CI, LStart);

   // If this was the final merge, store the root cluster ID
   if (finalBroadcast && numPrims == 1u) {
      uvec4 rootMask = subgroupBallot(CI != INVALID_ID);
      uint rootCI = subgroupShuffle(CI, hplocFirstBallotBit(rootMask));
      if (subgroupElect()) control.rootClusterID = rootCI;
   }
}

void main() {
   uint i = gl_GlobalInvocationID.x;
   uint N = control.sortTotal;

   if (N == 0u || control.sceneFrozen != 0u) return;
   if (N == 1u) {
      if (i == 0u) control.rootClusterID = clusterIndices[0];
      return;
   }

   uint L = i;
   uint R = i;
   bool laneActive = i < N;

   while (subgroupAny(laneActive)) {
      uint split = INVALID_ID;

      if (laneActive) {
         uint previousID = INVALID_ID;
         uint parentTarget = findParentID(int(L), int(R), N);

         if (parentTarget == R) {
            previousID = atomicExchange(parentIDs[R], L);
            if (previousID != INVALID_ID) {
               split = R + 1u;
               R = previousID;
            }
         } else {
            previousID = atomicExchange(parentIDs[L - 1u], R);
            if (previousID != INVALID_ID) {
               split = L;
               L = previousID;
            }
         }

         if (previousID == INVALID_ID) {
            laneActive = false;
         }
      }

      uint size = R - L + 1u;
      bool isFinal = laneActive && (size == N);
      uvec4 mergeMask = subgroupBallot(laneActive && ((size > hplocSubgroupSize() / 2u) || isFinal));
      bool merging = any(notEqual(mergeMask, uvec4(0u)));
      if (merging) memoryBarrierBuffer();

#ifdef MC_GL_VENDOR_AMD
      uint waveMask = mergeMask.x;

      while (waveMask != 0u) {
         uint laneID = uint(findLSB(waveMask));
         plocMerge(laneID, L, R, split, isFinal);
         waveMask &= (waveMask - 1u);
      }

      waveMask = mergeMask.y;

      while (waveMask != 0u) {
         uint laneID = 32u + uint(findLSB(waveMask));
         plocMerge(laneID, L, R, split, isFinal);
         waveMask &= (waveMask - 1u);
      }
#else
      uint waveMask = mergeMask.x;

      while (waveMask != 0u) {
         uint laneID = findLSB(waveMask);
         plocMerge(laneID, L, R, split, isFinal);
         waveMask &= (waveMask - 1u);
      }
#endif
      if (merging) {
         // All lanes publish the list before its owner announces parent arrival.
         memoryBarrierBuffer();
         subgroupBarrier();
      }
   }
}
