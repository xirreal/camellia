#version 460

#include "/lib/storage.glsl"
#include "/lib/hploc.glsl"

#if WG_SIZE == 32
layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;
shared uint cachedNeighbors[32];
#elif WG_SIZE == 64
layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
shared uint cachedNeighbors[64];
#elif WG_SIZE == 128
layout(local_size_x = 128, local_size_y = 1, local_size_z = 1) in;
shared uint cachedNeighbors[128];
#endif

uint findNearestNeighbor(uint numPrims, vec3 minBounds, vec3 maxBounds) {
   uint localWaveID = gl_SubgroupInvocationID;
   cachedNeighbors[localWaveID] = INVALID_ID;
   subgroupMemoryBarrierShared();
   subgroupBarrier();

   const uint encode_mask = ~((1u << uint(SEARCH_RADIUS_SHIFT + 1)) - 1u);

   uint min_area_index = 0xffffffffu;
   for (uint r = 1; r <= SEARCH_RADIUS; r++)
   {
      uint lane = localWaveID + r;
      vec3 minNeighborBounds = subgroupBroadcast(minBounds, lane);
      vec3 maxNeighborBounds = subgroupBroadcast(maxBounds, lane);

      if (lane < gl_SubgroupSize && lane < numPrims) {
         float newArea = distanceFct(minBounds, maxBounds, minNeighborBounds, maxNeighborBounds); // note, currently returns infinite "cost" for invalid bounds
         uint newAreaUint = ((floatBitsToUint(newArea) << 1) & encode_mask);
         uint encodedOffset = encodeRelativeOffset(localWaveID, lane);
         uint newArea_index0 = newAreaUint | encodedOffset | (localWaveID & 1);
         uint newArea_index1 = newAreaUint | encodedOffset | (((lane) & 1) ^ 1);
         minAreaIndex = min(minAreaIndex, newArea_index0);
         atomicMin(cachedNeighbors[lane], newArea_index1);
      }
   }
   atomicMin(cachedNeighbors[localWaveID], minAreaIndex);
   subgroupMemoryBarrierShared();
   uint neighbor = cachedNeighbors[localWaveID];
   return neighbor;
}

uint mergeClustersCreateBVH2Node(uint numPrims, uint NN, inout uint CI, inout vec3 minBounds, inout vec3 maxBounds) {
   uint localWaveID = gl_SubgroupInvocationID;

   // 1. Fix: Use Shuffle for variable indices (n_i)
   uint decode_mask = ((1u << uint(SEARCH_RADIUS_SHIFT + 1)) - 1u);
   uint n_i = decodeRelativeOffset(localWaveID, NN & decode_mask, localWaveID);

   uint n_i_neighbor_NN = subgroupShuffle(NN, n_i);
   uint n_i_n_i = decodeRelativeOffset(n_i, n_i_neighbor_NN & decode_mask, n_i);

   bool symmetricMatchFound = (localWaveID == n_i_n_i);
   bool laneIsLeftNeighbor = localWaveID < n_i;
   bool laneHasCluster = (localWaveID < numPrims);
   bool laneIsCreatingNode = (laneHasCluster && symmetricMatchFound && laneIsLeftNeighbor);

   uvec4 activeBallot = subgroupBallot(laneIsCreatingNode);
   uint numToAppend = subgroupBallotBitCount(activeBallot);
   uint bvh2IndexPrefix = subgroupBallotExclusiveBitCount(activeBallot);

   uint2 rightCluster = subgroupShuffle(CI, n_i);
   vec3 rightMinBounds = subgroupShuffle(minBounds, n_i);
   vec3 rightMaxBounds = subgroupShuffle(maxBounds, n_i);

   uint numNodesAllocated = INVALID_ID;

   if (subgroupElect()) numNodesAllocated = atomicAdd(numBVHNodes, numToAppend);
   numNodesAllocated = subgroupBroadcastFirst(numNodesAllocated);

   int baseNodeOffset = ((((count << 2) - 1) - numToAppend) - numNodesAllocated);

   if (numNodesAllocated >= (count << 2) - 1) {
      control.buildError = ERROR_OUT_OF_BOUNDS;
      return 0;
   }

   uint bvh2Index = baseNodeOffset + bvh2IndexPrefix;
   uint newCI = INVALID_ID;

   if (laneHasCluster) {
      newCI = CI;
      if (symmetricMatchFound) {
         if (laneIsLeftNeighbor) {
            nodes[bvh2Index] = BVH2Node(min(minBounds, rightMinBounds), CI, max(maxBounds, rightMaxBounds), rightCluster);
            minBounds = min(minBounds, rightMinBounds);
            maxBounds = max(maxBounds, rightMaxBounds);
            newCI = bvh2Index;
         } else {
            newCI = INVALID_ID;
         }
      }
   }

   uvec4 surviveBallot = subgroupBallot(newCI != INVALID_ID);
   uint total_reduction = subgroupBallotBitCount(surviveBallot);

   uint compactionSrcLane = __fns(surviveBallot, localWaveID + 1);

   CI = subgroupShuffle(newCI, compactionSrcLane);
   minBounds = subgroupShuffle(minBounds, compactionSrcLane);
   maxBounds = subgroupShuffle(maxBounds, compactionSrcLane);

   return total_reduction;
}

uint loadIndices(uint start, uint end, Buffer I, inout uint CI, uint offset)
{
   uint localWaveID = gl_SubgroupInvocationID;
   uint laneCount = gl_SubgroupSize;
   uint numIndices = min(end - start, uint(laneCount / 2));
   uint indexID = localWaveID - offset;
   bool laneActive = (indexID >= 0 && indexID < numIndices);
   if (laneActive)
      CI = clusterIndices[start + indexID];
   uint numValid = subgroupBallotBitCount(subgroupBallot(laneActive && CI.x != INVALID_ID));
   numIndices = min(numIndices, numValid);
   return numIndices;
}

void storeIndices(int origNumPrims, uint CI, Buffer I, uint LStart) {
   uint localWaveID = gl_SubgroupInvocationID;
   if (localWaveID < origNumPrims) {
      clusterIndices[LStart + localWaveID] = CI;
   }
}

void plocMerge(uint selectedLaneID, uint L, uint R, uint S, bool isFinal) {
   uint localWaveID = gl_SubgroupInvocationID;
   uint laneCount = gl_SubgroupSize;

   uint LStart = subgroupBroadcast(L, selectedLaneID);
   uint REnd = subgroupBroadcast(R, selectedLaneID) + 1u;
   uint LEnd = subgroupBroadcast(S, selectedLaneID);
   uint RStart = LEnd;

   uint CI = INVALID_ID;

   uint numLeft = loadIndices(LStart, LEnd, params.I, CI, 0u);
   uint numRight = loadIndices(RStart, REnd, params.I, CI, numLeft);
   uint numPrims = numLeft + numRight;

   vec3 minBounds = vec3(0.0);
   vec3 maxBounds = vec3(0.0);
   bool validBounds = LoadAABB(params, CI, minBounds, maxBounds);

   bool finalBroadcast = subgroupBroadcast(isFinal, selectedLaneID);
   uint THRESHOLD = finalBroadcast ? 1u : (laneCount / 2u);

   while (numPrims > THRESHOLD) {
      uint NN = findNearestNeighbor(numPrims, minBounds, maxBounds);
      numPrims = mergeClustersCreateBVH2Node(numPrims, NN, CI, minBounds, maxBounds);
   }

   storeIndices(numLeft + numRight, CI, params.I, LStart);
}

void main() {
   uint i = gl_GlobalInvocationID.x;
   uint N = count << 2;

   uint L = i;
   uint R = i;

   bool laneActive = i < N;

   while (subgroupAny(laneActive)) {
      uint split = INVALID_ID;

      if (laneActive) {
         uint previousID = INVALID_ID;

         if (findParentID(L, R, N) == R) {
            previousID = atomicExchange(pID[R], L);

            if (previousID != INVALID_ID) {
               split = R + 1;
               R = previousID;
            }
         }
         else {
            previousID = atomicExchange(pID[L - 1], R);

            if (previousID != INVALID_ID) {
               split = L;
               L = previousID;
            }
         }

         if (previousID == INVALID_ID) {
            laneActive = false;
         }
      }

      uint size = R - L + 1;
      bool finalVal = laneActive && (size == N);

      uvec4 ballot = subgroupBallot((laneActive && (size > WAVE_SIZE / 2)) || finalVal);

      #if WG_SIZE >= 32
      if (true) {
         uint waveMask = ballot[0];
         while (waveMask != 0) {
            uint localLaneID = findLSB(waveMask);
            uint absoluteLaneID = localLaneID + (0 * 32);
            plocMerge(absoluteLaneID, L, R, split, finalVal);
            waveMask &= (waveMask - 1);
         }
      }
      #endif

      #if WG_SIZE >= 64
      if (true) {
         uint waveMask = ballot[1];
         while (waveMask != 0) {
            uint localLaneID = findLSB(waveMask);
            uint absoluteLaneID = localLaneID + (1 * 32);
            plocMerge(absoluteLaneID, L, R, split, finalVal);
            waveMask &= (waveMask - 1);
         }
      }
      #endif

      #if WG_SIZE >= 96
      if (true) {
         uint waveMask = ballot[2];
         while (waveMask != 0) {
            uint localLaneID = findLSB(waveMask);
            uint absoluteLaneID = localLaneID + (2 * 32);
            plocMerge(absoluteLaneID, L, R, split, finalVal);
            waveMask &= (waveMask - 1);
         }
      }
      #endif

      #if WG_SIZE >= 128
      if (true) {
         uint waveMask = ballot[3];
         while (waveMask != 0) {
            uint localLaneID = findLSB(waveMask);
            uint absoluteLaneID = localLaneID + (3 * 32);
            plocMerge(absoluteLaneID, L, R, split, finalVal);
            waveMask &= (waveMask - 1);
         }
      }
      #endif
   }
}
