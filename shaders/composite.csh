#version 460

/*
   H-PLOC: Hierarchical Parallel Locally-Ordered Clustering
   for Bounding Volume Hierarchy Construction
   
   GLSL port based on Slang implementation by natevm
   https://gist.github.com/natevm/6618402427ad6466bf555d67602adfa8
*/

#include "/lib/storage.glsl"
#include "/lib/hploc.glsl"

layout(local_size_x = 32) in;

shared uint cached_neighbor[WAVE_SIZE];
shared uint compactCI[WAVE_SIZE];
shared vec3 compactMin[WAVE_SIZE];
shared vec3 compactMax[WAVE_SIZE];

uint findNearestNeighbor(uint numPrims, vec3 boundsMin, vec3 boundsMax) {
   uint localID = gl_SubgroupInvocationID;
   cached_neighbor[localID] = INVALID_ID;

   barrier();

   const uint encode_mask = ~(((1u << (SEARCH_RADIUS_SHIFT + 1u)) - 1u));

   for (uint r = 1u; r <= SEARCH_RADIUS; r++) {
      vec3 nbMin = subgroupShuffleDown(boundsMin, r);
      vec3 nbMax = subgroupShuffleDown(boundsMax, r);

      if ((localID + r) < numPrims) {
         float newArea = computeMergedSurfaceArea(boundsMin, boundsMax, nbMin, nbMax);
         uint newAreaI = (floatBitsToUint(newArea) << 1u) & encode_mask;
         uint encode0 = encodeRelativeOffset(localID, localID + r);
         uint newAreaIndex0 = newAreaI | encode0 | (localID & 1u);
         uint newAreaIndex1 = newAreaI | encode0 | (((localID + r) & 1u) ^ 1u);
         atomicMin(cached_neighbor[localID], newAreaIndex0);
         atomicMin(cached_neighbor[localID + r], newAreaIndex1);
      }
   }

   barrier();
   return cached_neighbor[localID];
}

uint mergeClustersCreateBVH2Node(
   uint numPrims, uint NN,
   inout uint CI, inout vec3 boundsMin, inout vec3 boundsMax
) {
   uint localID = gl_SubgroupInvocationID;
   bool laneHasCluster = localID < numPrims;

   const uint decode_mask = ((1u << (SEARCH_RADIUS_SHIFT + 1u)) - 1u);

   uint safeNN = laneHasCluster ? NN : 0u;
   uint n_i_raw = laneHasCluster
      ? uint(decodeRelativeOffset(int(localID), safeNN & decode_mask, localID))
      : localID;
   uint n_i = clamp(n_i_raw, 0u, WAVE_SIZE - 1u);

   uint neighborNN = subgroupShuffle(safeNN, n_i);
   uint n_i_n_i_raw = laneHasCluster
      ? uint(decodeRelativeOffset(int(n_i), neighborNN & decode_mask, n_i))
      : localID;
   uint n_i_n_i = clamp(n_i_n_i_raw, 0u, WAVE_SIZE - 1u);

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
      baseNodeOffset = atomicAdd(control.data[CTRL_BVH2_NODE_COUNT], numNewNodes);
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

            bvh2Nodes[bvh2Index] = BVH2Node(newMin, leftCI, newMax, rightCI);
            boundsMin = newMin;
            boundsMax = newMax;
            newCI = makeClusterID(bvh2Index, GEOM_ID_BVH2);
         } else {
            newCI = INVALID_ID;
         }
      }
   }

   // Compact via shared memory to avoid __fns / nth-set-bit issues
   bool keepLane = laneHasCluster && (newCI != INVALID_ID);
   uvec4 keepMask = subgroupBallot(keepLane);
   uint totalRemaining = subgroupBallotBitCount(keepMask);
   uint myNewPos = subgroupBallotExclusiveBitCount(keepMask);

   compactCI[localID] = INVALID_ID;
   compactMin[localID] = vec3(1e38);
   compactMax[localID] = vec3(-1e38);
   barrier();

   if (keepLane) {
      compactCI[myNewPos] = newCI;
      compactMin[myNewPos] = boundsMin;
      compactMax[myNewPos] = boundsMax;
   }
   barrier();

   CI = compactCI[localID];
   boundsMin = compactMin[localID];
   boundsMax = compactMax[localID];
   barrier();

   return totalRemaining;
}

uint loadIndicesFromBuffer(uint start, uint end, inout uint CI, uint offset) {
   uint localID = gl_SubgroupInvocationID;
   uint numIndices = min(end - start, WAVE_SIZE / 2u);
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
   uint threshold = finalBroadcast ? 1u : WAVE_SIZE / 2u;

   while (numPrims > threshold) {
      uint NN = findNearestNeighbor(numPrims, boundsMin, boundsMax);
      numPrims = mergeClustersCreateBVH2Node(numPrims, NN, CI, boundsMin, boundsMax);
   }

   storeIndicesToBuffer(numLeft + numRight, CI, LStart);
}

void main() {
   uint i = gl_GlobalInvocationID.x;
   uint N = control.data[CTRL_SORT_TOTAL];

   if (N == 0u) return;

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
      uvec4 mergeMask = subgroupBallot(laneActive && ((size > WAVE_SIZE / 2u) || isFinal));
      uint waveMask = mergeMask.x;

      while (waveMask != 0u) {
         uint laneID = findLSB(waveMask);
         plocMerge(laneID, L, R, split, isFinal);
         waveMask &= (waveMask - 1u);
      }
   }
}
