#ifndef SORT_INCLUDE_GUARD
#define SORT_INCLUDE_GUARD

/*
   Device-level 8-bit LSD radix sort, adapted from:
   https://github.com/b0nes164/GPUSorting
   SPDX-License-Identifier: MIT
*/

uint sortGetN() {
   return control.sortTotal;
}

uint sortGetThreadBlocks() {
   uint N = sortGetN();
   return (N + SORT_PART_SIZE - 1u) / SORT_PART_SIZE;
}

uint sortExtractDigit(uint key) {
   return (key >> (SORT_PASS * RADIX_BITS)) & SORT_RADIX_MASK;
}

uint sortExtractDigitAtShift(uint key, uint shift) {
   return (key >> shift) & SORT_RADIX_MASK;
}

uint sortExtractPackedIndex(uint key) {
   return (key >> (SORT_PASS * RADIX_BITS + 1u)) & SORT_HALF_RADIX_MASK;
}

uint sortExtractPackedShift(uint key) {
   return ((key >> (SORT_PASS * RADIX_BITS)) & 1u) != 0u ? 16u : 0u;
}

uint sortExtractPackedValue(uint packedValue, uint key) {
   return (packedValue >> sortExtractPackedShift(key)) & 0xffffu;
}

uint sortGlobalHistBase() {
   return SORT_SCRATCH_GLOBAL_HIST + SORT_PASS * RADIX;
}

bool sortIsPassEven() {
   return (SORT_PASS & 1u) == 0u;
}

uint sortReadKey(uint index) {
   if (sortIsPassEven()) return mortonCodes[index];
   return sortScratch[SORT_SCRATCH_KEYS + index];
}

uint sortReadVal(uint index) {
   if (sortIsPassEven()) return clusterIndices[index];
   return sortScratch[SORT_SCRATCH_VALS + index];
}

void sortWriteKey(uint index, uint key) {
   if (sortIsPassEven()) sortScratch[SORT_SCRATCH_KEYS + index] = key;
   else mortonCodes[index] = key;
}

void sortWriteVal(uint index, uint val) {
   if (sortIsPassEven()) sortScratch[SORT_SCRATCH_VALS + index] = val;
   else clusterIndices[index] = val;
}

uint sortWaveIndex(uint localID) {
   return localID / gl_SubgroupSize;
}

uint sortWaveLane() {
   return gl_SubgroupInvocationID;
}

uint sortWavePrefixSum(uint value) {
   return subgroupExclusiveAdd(value);
}

uint sortWaveReadLaneAt(uint value, uint lane) {
   return subgroupShuffle(value, lane);
}

uint sortFindLowestSetBit(uint bits) {
   int bitIndex = findLSB(bits);
   return bitIndex < 0 ? 0xffffffffu : uint(bitIndex);
}

struct SortKeyStruct {
   uint k[SORT_KEYS_PER_THREAD];
};

struct SortOffsetStruct {
   uint o[SORT_KEYS_PER_THREAD];
};

struct SortDigitStruct {
   uint d[SORT_KEYS_PER_THREAD];
};

// upsweep: reduce partition digit counts and build per-pass global digit offsets

#if SORT_PHASE == 0

shared uint sortUpsweepShared[RADIX * 2u];

void sortHistogramDigitCounts(uint localID, uint groupID) {
   uint histOffset = (localID / 64u) * RADIX;
   uint partitionEnd = min(sortGetN(), (groupID + 1u) * SORT_PART_SIZE);
   for (uint i = localID + groupID * SORT_PART_SIZE; i < partitionEnd; i += SORT_UPSWEEP_WG_SIZE) {
      atomicAdd(sortUpsweepShared[sortExtractDigit(sortReadKey(i)) + histOffset], 1u);
   }
}

void sortReduceWriteDigitCounts(uint localID, uint groupID, uint threadBlocks) {
   for (uint i = localID; i < RADIX; i += SORT_UPSWEEP_WG_SIZE) {
      uint count = sortUpsweepShared[i] + sortUpsweepShared[i + RADIX];
      sortScratch[SORT_SCRATCH_PASS_HIST + i * threadBlocks + groupID] = count;
      sortUpsweepShared[i] = count + sortWavePrefixSum(count);
   }
}

void sortGlobalHistExclusiveScanWGE16(uint localID) {
   barrier();

   if (localID < (RADIX / gl_SubgroupSize)) {
      uint index = (localID + 1u) * gl_SubgroupSize - 1u;
      sortUpsweepShared[index] += sortWavePrefixSum(sortUpsweepShared[index]);
   }
   barrier();

   uint laneMask = gl_SubgroupSize - 1u;
   uint circularLaneShift = (sortWaveLane() + 1u) & laneMask;
   uint globalBase = sortGlobalHistBase();

   for (uint i = localID; i < RADIX; i += SORT_UPSWEEP_WG_SIZE) {
      uint index = circularLaneShift + (i & ~laneMask);
      uint priorWave = 0u;
      if (i >= gl_SubgroupSize) {
         priorWave = sortWaveReadLaneAt(sortUpsweepShared[i - 1u], 0u);
      }
      uint exclusive = (sortWaveLane() != laneMask ? sortUpsweepShared[i] : 0u) + priorWave;
      atomicAdd(sortScratch[globalBase + index], exclusive);
   }
}

void sortGlobalHistExclusiveScanFallback(uint localID, uint groupID, uint threadBlocks) {
   barrier();

   if (localID == 0u) {
      uint sum = 0u;
      uint globalBase = sortGlobalHistBase();
      for (uint d = 0u; d < RADIX; d++) {
         uint count = sortScratch[SORT_SCRATCH_PASS_HIST + d * threadBlocks + groupID];
         atomicAdd(sortScratch[globalBase + d], sum);
         sum += count;
      }
   }
}

void sortUpsweep() {
   uint localID = gl_LocalInvocationID.x;
   uint groupID = gl_WorkGroupID.x;
   uint threadBlocks = sortGetThreadBlocks();

   if (groupID >= threadBlocks) return;

   for (uint i = localID; i < RADIX * 2u; i += SORT_UPSWEEP_WG_SIZE) {
      sortUpsweepShared[i] = 0u;
   }
   barrier();

   sortHistogramDigitCounts(localID, groupID);
   barrier();

   sortReduceWriteDigitCounts(localID, groupID, threadBlocks);

   if (gl_SubgroupSize >= 16u) {
      sortGlobalHistExclusiveScanWGE16(localID);
   } else {
      sortGlobalHistExclusiveScanFallback(localID, groupID, threadBlocks);
   }
}

#endif

// scan: exclusive scan of partition reductions for each digit

#if SORT_PHASE == 1

shared uint sortScanShared[SORT_SCAN_WG_SIZE];

void sortExclusiveThreadBlockScanFullWGE16(
   uint localID,
   uint laneMask,
   uint circularLaneShift,
   uint partitionsEnd,
   uint deviceOffset,
   inout uint reduction
) {
   for (uint i = localID; i < partitionsEnd; i += SORT_SCAN_WG_SIZE) {
      uint value = sortScratch[SORT_SCRATCH_PASS_HIST + deviceOffset + i];
      sortScanShared[localID] = value + sortWavePrefixSum(value);
      barrier();

      if (localID < SORT_SCAN_WG_SIZE / gl_SubgroupSize) {
         uint index = (localID + 1u) * gl_SubgroupSize - 1u;
         sortScanShared[index] += sortWavePrefixSum(sortScanShared[index]);
      }
      barrier();

      uint priorWave = 0u;
      if (localID >= gl_SubgroupSize) {
         priorWave = sortScanShared[(localID & ~laneMask) - 1u];
      }
      sortScratch[SORT_SCRATCH_PASS_HIST + deviceOffset + circularLaneShift + (i & ~laneMask)] =
         (sortWaveLane() != laneMask ? sortScanShared[localID] : 0u) + priorWave + reduction;

      reduction += sortScanShared[SORT_SCAN_WG_SIZE - 1u];
      barrier();
   }
}

void sortExclusiveThreadBlockScanPartialWGE16(
   uint localID,
   uint laneMask,
   uint circularLaneShift,
   uint partitionsEnd,
   uint deviceOffset,
   uint reduction,
   uint threadBlocks
) {
   uint i = localID + partitionsEnd;
   uint value = (i < threadBlocks) ? sortScratch[SORT_SCRATCH_PASS_HIST + deviceOffset + i] : 0u;
   sortScanShared[localID] = value + sortWavePrefixSum(value);
   barrier();

   if (localID < SORT_SCAN_WG_SIZE / gl_SubgroupSize) {
      uint index = (localID + 1u) * gl_SubgroupSize - 1u;
      sortScanShared[index] += sortWavePrefixSum(sortScanShared[index]);
   }
   barrier();

   uint index = circularLaneShift + (i & ~laneMask);
   if (index < threadBlocks) {
      uint priorWave = 0u;
      if (localID >= gl_SubgroupSize) {
         priorWave = sortScanShared[(localID & ~laneMask) - 1u];
      }
      sortScratch[SORT_SCRATCH_PASS_HIST + deviceOffset + index] =
         (sortWaveLane() != laneMask ? sortScanShared[localID] : 0u) + priorWave + reduction;
   }
}

void sortExclusiveThreadBlockScanWGE16(uint localID, uint digitBucket, uint threadBlocks) {
   uint reduction = 0u;
   uint laneMask = gl_SubgroupSize - 1u;
   uint circularLaneShift = (sortWaveLane() + 1u) & laneMask;
   uint partitionsEnd = (threadBlocks / SORT_SCAN_WG_SIZE) * SORT_SCAN_WG_SIZE;
   uint deviceOffset = digitBucket * threadBlocks;

   sortExclusiveThreadBlockScanFullWGE16(localID, laneMask, circularLaneShift, partitionsEnd, deviceOffset, reduction);
   sortExclusiveThreadBlockScanPartialWGE16(localID, laneMask, circularLaneShift, partitionsEnd, deviceOffset, reduction, threadBlocks);
}

void sortExclusiveThreadBlockScanFallback(uint localID, uint digitBucket, uint threadBlocks) {
   if (localID == 0u) {
      uint deviceOffset = digitBucket * threadBlocks;
      uint sum = 0u;
      for (uint i = 0u; i < threadBlocks; i++) {
         uint count = sortScratch[SORT_SCRATCH_PASS_HIST + deviceOffset + i];
         sortScratch[SORT_SCRATCH_PASS_HIST + deviceOffset + i] = sum;
         sum += count;
      }
   }
}

void sortScan() {
   uint localID = gl_LocalInvocationID.x;
   uint digitBucket = gl_WorkGroupID.x;
   uint threadBlocks = sortGetThreadBlocks();

   if (digitBucket >= RADIX || threadBlocks == 0u) return;

   if (gl_SubgroupSize >= 16u) {
      sortExclusiveThreadBlockScanWGE16(localID, digitBucket, threadBlocks);
   } else {
      sortExclusiveThreadBlockScanFallback(localID, digitBucket, threadBlocks);
   }
}

#endif

// downsweep: rank keys in each partition, scatter keys and payloads

#if SORT_PHASE == 2

shared uint sortDownShared[SORT_DOWNSWEEP_SMEM];

uint sortSubPartSizeWGE16() {
   return SORT_KEYS_PER_THREAD * gl_SubgroupSize;
}

uint sortSharedOffsetWGE16(uint localID) {
   return sortWaveLane() + sortWaveIndex(localID) * sortSubPartSizeWGE16();
}

uint sortDeviceOffsetWGE16(uint localID, uint partIndex) {
   return sortSharedOffsetWGE16(localID) + partIndex * SORT_PART_SIZE;
}

uint sortSerialIterations() {
   return (SORT_DOWNSWEEP_WG_SIZE / gl_SubgroupSize + 31u) >> 5u;
}

uint sortSubPartSizeWLT16(uint serialIterations) {
   return SORT_KEYS_PER_THREAD * gl_SubgroupSize * serialIterations;
}

uint sortSharedOffsetWLT16(uint localID, uint serialIterations) {
   uint waveIndex = sortWaveIndex(localID);
   return sortWaveLane() +
      (waveIndex / serialIterations * sortSubPartSizeWLT16(serialIterations)) +
      (waveIndex % serialIterations * gl_SubgroupSize);
}

uint sortDeviceOffsetWLT16(uint localID, uint partIndex, uint serialIterations) {
   return sortSharedOffsetWLT16(localID, serialIterations) + partIndex * SORT_PART_SIZE;
}

uint sortWaveHistsSizeWGE16() {
   return SORT_DOWNSWEEP_WG_SIZE / gl_SubgroupSize * RADIX;
}

uint sortWaveHistsSizeWLT16() {
   return SORT_DOWNSWEEP_SMEM;
}

void sortClearWaveHists(uint localID) {
   uint histsEnd = gl_SubgroupSize >= 16u ? sortWaveHistsSizeWGE16() : sortWaveHistsSizeWLT16();
   for (uint i = localID; i < histsEnd; i += SORT_DOWNSWEEP_WG_SIZE) {
      sortDownShared[i] = 0u;
   }
}

void sortLoadKey(out uint key, uint index) {
   key = sortReadKey(index);
}

void sortLoadDummyKey(out uint key) {
   key = 0xffffffffu;
}

SortKeyStruct sortLoadKeysWGE16(uint localID, uint partIndex) {
   SortKeyStruct keys;
   uint t = sortDeviceOffsetWGE16(localID, partIndex);
   for (uint i = 0u; i < SORT_KEYS_PER_THREAD; i++, t += gl_SubgroupSize) {
      sortLoadKey(keys.k[i], t);
   }
   return keys;
}

SortKeyStruct sortLoadKeysWLT16(uint localID, uint partIndex, uint serialIterations) {
   SortKeyStruct keys;
   uint t = sortDeviceOffsetWLT16(localID, partIndex, serialIterations);
   uint step = gl_SubgroupSize * serialIterations;
   for (uint i = 0u; i < SORT_KEYS_PER_THREAD; i++, t += step) {
      sortLoadKey(keys.k[i], t);
   }
   return keys;
}

SortKeyStruct sortLoadKeysPartialWGE16(uint localID, uint partIndex) {
   SortKeyStruct keys;
   uint t = sortDeviceOffsetWGE16(localID, partIndex);
   uint N = sortGetN();
   for (uint i = 0u; i < SORT_KEYS_PER_THREAD; i++, t += gl_SubgroupSize) {
      if (t < N) sortLoadKey(keys.k[i], t);
      else sortLoadDummyKey(keys.k[i]);
   }
   return keys;
}

SortKeyStruct sortLoadKeysPartialWLT16(uint localID, uint partIndex, uint serialIterations) {
   SortKeyStruct keys;
   uint t = sortDeviceOffsetWLT16(localID, partIndex, serialIterations);
   uint step = gl_SubgroupSize * serialIterations;
   uint N = sortGetN();
   for (uint i = 0u; i < SORT_KEYS_PER_THREAD; i++, t += step) {
      if (t < N) sortLoadKey(keys.k[i], t);
      else sortLoadDummyKey(keys.k[i]);
   }
   return keys;
}

uvec4 sortWaveFlagsWGE16() {
   uint validMask = (gl_SubgroupSize & 31u) != 0u ? ((1u << gl_SubgroupSize) - 1u) : 0xffffffffu;
   return uvec4(validMask);
}

uint sortWaveFlagsWLT16() {
   return (1u << gl_SubgroupSize) - 1u;
}

void sortWarpLevelMultiSplitWGE16(uint key, uint waveParts, inout uvec4 waveFlags) {
   for (uint k = 0u; k < RADIX_BITS; k++) {
      bool bitSet = ((key >> (k + SORT_PASS * RADIX_BITS)) & 1u) != 0u;
      uvec4 ballotValue = subgroupBallot(bitSet);
      for (uint wavePart = 0u; wavePart < waveParts; wavePart++) {
         waveFlags[wavePart] &= (bitSet ? 0u : 0xffffffffu) ^ ballotValue[wavePart];
      }
   }
}

void sortWarpLevelMultiSplitWLT16(uint key, inout uint waveFlags) {
   for (uint k = 0u; k < RADIX_BITS; k++) {
      bool bitSet = ((key >> (k + SORT_PASS * RADIX_BITS)) & 1u) != 0u;
      uint ballotValue = subgroupBallot(bitSet).x;
      waveFlags &= (bitSet ? 0u : 0xffffffffu) ^ ballotValue;
   }
}

void sortCountPeerBits(inout uint peerBits, inout uint totalBits, uvec4 waveFlags, uint waveParts) {
   uint lane = sortWaveLane();
   for (uint wavePart = 0u; wavePart < waveParts; wavePart++) {
      if (lane >= wavePart * 32u) {
         uint ltMask = lane >= (wavePart + 1u) * 32u ? 0xffffffffu : ((1u << (lane & 31u)) - 1u);
         peerBits += bitCount(waveFlags[wavePart] & ltMask);
      }
      totalBits += bitCount(waveFlags[wavePart]);
   }
}

uint sortCountPeerBitsWLT16(uint waveFlags, uint ltMask) {
   return bitCount(waveFlags & ltMask);
}

uint sortFindLowestRankPeer(uvec4 waveFlags, uint waveParts) {
   uint lowestRankPeer = 0u;
   for (uint wavePart = 0u; wavePart < waveParts; wavePart++) {
      uint firstBit = sortFindLowestSetBit(waveFlags[wavePart]);
      if (firstBit == 0xffffffffu) {
         lowestRankPeer += 32u;
      } else {
         return lowestRankPeer + firstBit;
      }
   }
   return 0u;
}

SortOffsetStruct sortRankKeysWGE16(uint localID, SortKeyStruct keys) {
   SortOffsetStruct offsets;
   uint waveParts = (gl_SubgroupSize + 31u) / 32u;
   for (uint i = 0u; i < SORT_KEYS_PER_THREAD; i++) {
      uvec4 waveFlags = sortWaveFlagsWGE16();
      sortWarpLevelMultiSplitWGE16(keys.k[i], waveParts, waveFlags);

      uint index = sortExtractDigit(keys.k[i]) + sortWaveIndex(localID) * RADIX;
      uint lowestRankPeer = sortFindLowestRankPeer(waveFlags, waveParts);

      uint peerBits = 0u;
      uint totalBits = 0u;
      sortCountPeerBits(peerBits, totalBits, waveFlags, waveParts);

      uint preIncrementValue = 0u;
      if (peerBits == 0u) {
         preIncrementValue = atomicAdd(sortDownShared[index], totalBits);
      }
      offsets.o[i] = sortWaveReadLaneAt(preIncrementValue, lowestRankPeer) + peerBits;
   }

   return offsets;
}

SortOffsetStruct sortRankKeysWLT16(uint localID, SortKeyStruct keys, uint serialIterations) {
   SortOffsetStruct offsets;
   uint lane = sortWaveLane();
   uint ltMask = (1u << lane) - 1u;
   uint waveIndex = sortWaveIndex(localID);

   for (uint i = 0u; i < SORT_KEYS_PER_THREAD; i++) {
      uint waveFlags = sortWaveFlagsWLT16();
      sortWarpLevelMultiSplitWLT16(keys.k[i], waveFlags);

      uint index = sortExtractPackedIndex(keys.k[i]) +
         (waveIndex / serialIterations * HALF_RADIX);

      uint peerBits = sortCountPeerBitsWLT16(waveFlags, ltMask);
      for (uint k = 0u; k < serialIterations; k++) {
         if (waveIndex % serialIterations == k) {
            offsets.o[i] = sortExtractPackedValue(sortDownShared[index], keys.k[i]) + peerBits;
         }

         barrier();
         if (waveIndex % serialIterations == k && peerBits == 0u) {
            atomicAdd(sortDownShared[index], bitCount(waveFlags) << sortExtractPackedShift(keys.k[i]));
         }
         barrier();
      }
   }

   return offsets;
}

uint sortWaveHistInclusiveScanCircularShiftWGE16(uint localID) {
   uint histReduction = sortDownShared[localID];
   for (uint i = localID + RADIX; i < sortWaveHistsSizeWGE16(); i += RADIX) {
      histReduction += sortDownShared[i];
      sortDownShared[i] = histReduction - sortDownShared[i];
   }
   return histReduction;
}

uint sortWaveHistInclusiveScanCircularShiftWLT16(uint localID) {
   uint histReduction = sortDownShared[localID];
   for (uint i = localID + HALF_RADIX; i < sortWaveHistsSizeWLT16(); i += HALF_RADIX) {
      histReduction += sortDownShared[i];
      sortDownShared[i] = histReduction - sortDownShared[i];
   }
   return histReduction;
}

void sortWaveHistReductionExclusiveScanWGE16(uint localID, uint histReduction) {
   if (localID < RADIX) {
      uint laneMask = gl_SubgroupSize - 1u;
      sortDownShared[((sortWaveLane() + 1u) & laneMask) + (localID & ~laneMask)] = histReduction;
   }
   barrier();

   if (localID < RADIX / gl_SubgroupSize) {
      uint index = localID * gl_SubgroupSize;
      sortDownShared[index] = sortWavePrefixSum(sortDownShared[index]);
   }
   barrier();

   if (localID < RADIX && sortWaveLane() != 0u) {
      sortDownShared[localID] += sortWaveReadLaneAt(sortDownShared[localID - 1u], 1u);
   }
}

void sortWaveHistReductionExclusiveScanWLT16(uint localID) {
   uint shift = 1u;
   for (uint j = RADIX >> 2u; j > 0u; j >>= 1u) {
      barrier();
      if (localID < j) {
         uint left = ((((localID << 1u) + 1u) << shift) - 1u) >> 1u;
         uint right = ((((localID << 1u) + 2u) << shift) - 1u) >> 1u;
         sortDownShared[right] += sortDownShared[left] & 0xffff0000u;
      }
      shift++;
   }

   barrier();
   if (localID == 0u) {
      sortDownShared[HALF_RADIX - 1u] &= 0xffffu;
   }

   for (uint j = 1u; j < RADIX >> 1u; j <<= 1u) {
      --shift;
      barrier();
      if (localID < j) {
         uint left = ((((localID << 1u) + 1u) << shift) - 1u) >> 1u;
         uint right = ((((localID << 1u) + 2u) << shift) - 1u) >> 1u;
         uint t = sortDownShared[left];
         sortDownShared[left] = (t & 0xffffu) | (sortDownShared[right] & 0xffff0000u);
         sortDownShared[right] += t & 0xffff0000u;
      }
   }

   barrier();
   if (localID < HALF_RADIX) {
      uint t = sortDownShared[localID];
      sortDownShared[localID] = (t >> 16u) + (t << 16u) + (t & 0xffff0000u);
   }
}

void sortUpdateOffsetsWGE16(uint localID, inout SortOffsetStruct offsets, SortKeyStruct keys) {
   if (localID >= gl_SubgroupSize) {
      uint waveBase = sortWaveIndex(localID) * RADIX;
      for (uint i = 0u; i < SORT_KEYS_PER_THREAD; i++) {
         uint digit = sortExtractDigit(keys.k[i]);
         offsets.o[i] += sortDownShared[digit + waveBase] + sortDownShared[digit];
      }
   } else {
      for (uint i = 0u; i < SORT_KEYS_PER_THREAD; i++) {
         offsets.o[i] += sortDownShared[sortExtractDigit(keys.k[i])];
      }
   }
}

void sortUpdateOffsetsWLT16(uint localID, uint serialIterations, inout SortOffsetStruct offsets, SortKeyStruct keys) {
   if (localID >= gl_SubgroupSize * serialIterations) {
      uint waveBase = sortWaveIndex(localID) / serialIterations * HALF_RADIX;
      for (uint i = 0u; i < SORT_KEYS_PER_THREAD; i++) {
         uint packedIndex = sortExtractPackedIndex(keys.k[i]);
         offsets.o[i] += sortExtractPackedValue(sortDownShared[packedIndex + waveBase] + sortDownShared[packedIndex], keys.k[i]);
      }
   } else {
      for (uint i = 0u; i < SORT_KEYS_PER_THREAD; i++) {
         offsets.o[i] += sortExtractPackedValue(sortDownShared[sortExtractPackedIndex(keys.k[i])], keys.k[i]);
      }
   }
}

void sortScatterKeysShared(SortOffsetStruct offsets, SortKeyStruct keys) {
   for (uint i = 0u; i < SORT_KEYS_PER_THREAD; i++) {
      sortDownShared[offsets.o[i]] = keys.k[i];
   }
}

void sortLoadPayload(out uint payload, uint deviceIndex) {
   payload = sortReadVal(deviceIndex);
}

void sortScatterPayloadsShared(SortOffsetStruct offsets, SortKeyStruct payloads) {
   sortScatterKeysShared(offsets, payloads);
}

void sortWriteKeyFromShared(uint deviceIndex, uint sharedIndex) {
   sortWriteKey(deviceIndex, sortDownShared[sharedIndex]);
}

void sortWritePayloadFromShared(uint deviceIndex, uint sharedIndex) {
   sortWriteVal(deviceIndex, sortDownShared[sharedIndex]);
}

void sortLoadPayloadsWGE16(uint localID, uint partIndex, inout SortKeyStruct payloads) {
   uint t = sortDeviceOffsetWGE16(localID, partIndex);
   for (uint i = 0u; i < SORT_KEYS_PER_THREAD; i++, t += gl_SubgroupSize) {
      sortLoadPayload(payloads.k[i], t);
   }
}

void sortLoadPayloadsWLT16(uint localID, uint partIndex, uint serialIterations, inout SortKeyStruct payloads) {
   uint t = sortDeviceOffsetWLT16(localID, partIndex, serialIterations);
   uint step = gl_SubgroupSize * serialIterations;
   for (uint i = 0u; i < SORT_KEYS_PER_THREAD; i++, t += step) {
      sortLoadPayload(payloads.k[i], t);
   }
}

void sortLoadPayloadsPartialWGE16(uint localID, uint partIndex, inout SortKeyStruct payloads) {
   uint t = sortDeviceOffsetWGE16(localID, partIndex);
   uint N = sortGetN();
   for (uint i = 0u; i < SORT_KEYS_PER_THREAD; i++, t += gl_SubgroupSize) {
      if (t < N) sortLoadPayload(payloads.k[i], t);
      else payloads.k[i] = 0u;
   }
}

void sortLoadPayloadsPartialWLT16(uint localID, uint partIndex, uint serialIterations, inout SortKeyStruct payloads) {
   uint t = sortDeviceOffsetWLT16(localID, partIndex, serialIterations);
   uint step = gl_SubgroupSize * serialIterations;
   uint N = sortGetN();
   for (uint i = 0u; i < SORT_KEYS_PER_THREAD; i++, t += step) {
      if (t < N) sortLoadPayload(payloads.k[i], t);
      else payloads.k[i] = 0u;
   }
}

void sortScatterPairsKeyPhaseAscending(uint localID, inout SortDigitStruct digits) {
   uint t = localID;
   for (uint i = 0u; i < SORT_KEYS_PER_THREAD; i++, t += SORT_DOWNSWEEP_WG_SIZE) {
      digits.d[i] = sortExtractDigit(sortDownShared[t]);
      sortWriteKeyFromShared(sortDownShared[digits.d[i] + SORT_PART_SIZE] + t, t);
   }
}

void sortScatterPayloadsAscending(uint localID, SortDigitStruct digits) {
   uint t = localID;
   for (uint i = 0u; i < SORT_KEYS_PER_THREAD; i++, t += SORT_DOWNSWEEP_WG_SIZE) {
      sortWritePayloadFromShared(sortDownShared[digits.d[i] + SORT_PART_SIZE] + t, t);
   }
}

void sortScatterPairsDevice(uint localID, uint partIndex, SortOffsetStruct offsets) {
   SortDigitStruct digits;
   sortScatterPairsKeyPhaseAscending(localID, digits);
   barrier();

   SortKeyStruct payloads;
   if (gl_SubgroupSize >= 16u) {
      sortLoadPayloadsWGE16(localID, partIndex, payloads);
   } else {
      sortLoadPayloadsWLT16(localID, partIndex, sortSerialIterations(), payloads);
   }
   sortScatterPayloadsShared(offsets, payloads);
   barrier();

   sortScatterPayloadsAscending(localID, digits);
}

void sortScatterPairsKeyPhaseAscendingPartial(uint localID, uint finalPartSize, inout SortDigitStruct digits) {
   uint t = localID;
   for (uint i = 0u; i < SORT_KEYS_PER_THREAD; i++, t += SORT_DOWNSWEEP_WG_SIZE) {
      digits.d[i] = sortExtractDigit(sortDownShared[t]);
      if (t < finalPartSize) {
         sortWriteKeyFromShared(sortDownShared[digits.d[i] + SORT_PART_SIZE] + t, t);
      }
   }
}

void sortScatterPayloadsAscendingPartial(uint localID, uint finalPartSize, SortDigitStruct digits) {
   uint t = localID;
   for (uint i = 0u; i < SORT_KEYS_PER_THREAD; i++, t += SORT_DOWNSWEEP_WG_SIZE) {
      if (t < finalPartSize) {
         sortWritePayloadFromShared(sortDownShared[digits.d[i] + SORT_PART_SIZE] + t, t);
      }
   }
}

void sortScatterPairsDevicePartial(uint localID, uint partIndex, SortOffsetStruct offsets) {
   SortDigitStruct digits;
   uint finalPartSize = sortGetN() - partIndex * SORT_PART_SIZE;
   sortScatterPairsKeyPhaseAscendingPartial(localID, finalPartSize, digits);
   barrier();

   SortKeyStruct payloads;
   if (gl_SubgroupSize >= 16u) {
      sortLoadPayloadsPartialWGE16(localID, partIndex, payloads);
   } else {
      sortLoadPayloadsPartialWLT16(localID, partIndex, sortSerialIterations(), payloads);
   }
   sortScatterPayloadsShared(offsets, payloads);
   barrier();

   sortScatterPayloadsAscendingPartial(localID, finalPartSize, digits);
}

void sortLoadThreadBlockReductions(uint localID, uint groupID, uint exclusiveHistReduction, uint threadBlocks) {
   if (localID < RADIX) {
      sortDownShared[localID + SORT_PART_SIZE] =
         sortScratch[sortGlobalHistBase() + localID] +
         sortScratch[SORT_SCRATCH_PASS_HIST + localID * threadBlocks + groupID] -
         exclusiveHistReduction;
   }
}

void sortDownsweep() {
   uint localID = gl_LocalInvocationID.x;
   uint groupID = gl_WorkGroupID.x;
   uint threadBlocks = sortGetThreadBlocks();

   if (groupID >= threadBlocks) return;

   SortKeyStruct keys;
   SortOffsetStruct offsets;

   sortClearWaveHists(localID);

   if (groupID < threadBlocks - 1u) {
      if (gl_SubgroupSize >= 16u) {
         keys = sortLoadKeysWGE16(localID, groupID);
      } else {
         keys = sortLoadKeysWLT16(localID, groupID, sortSerialIterations());
      }
   } else {
      if (gl_SubgroupSize >= 16u) {
         keys = sortLoadKeysPartialWGE16(localID, groupID);
      } else {
         keys = sortLoadKeysPartialWLT16(localID, groupID, sortSerialIterations());
      }
   }

   uint exclusiveHistReduction = 0u;
   if (gl_SubgroupSize >= 16u) {
      barrier();

      offsets = sortRankKeysWGE16(localID, keys);
      barrier();

      uint histReduction = 0u;
      if (localID < RADIX) {
         histReduction = sortWaveHistInclusiveScanCircularShiftWGE16(localID);
         histReduction += sortWavePrefixSum(histReduction);
      }
      barrier();

      sortWaveHistReductionExclusiveScanWGE16(localID, histReduction);
      barrier();

      sortUpdateOffsetsWGE16(localID, offsets, keys);
      if (localID < RADIX) {
         exclusiveHistReduction = sortDownShared[localID];
      }
      barrier();
   } else {
      uint serialIterations = sortSerialIterations();

      offsets = sortRankKeysWLT16(localID, keys, serialIterations);

      if (localID < HALF_RADIX) {
         uint histReduction = sortWaveHistInclusiveScanCircularShiftWLT16(localID);
         sortDownShared[localID] = histReduction + (histReduction << 16u);
      }

      sortWaveHistReductionExclusiveScanWLT16(localID);
      barrier();

      sortUpdateOffsetsWLT16(localID, serialIterations, offsets, keys);
      if (localID < RADIX) {
         exclusiveHistReduction =
            (sortDownShared[localID >> 1u] >> ((localID & 1u) != 0u ? 16u : 0u)) & 0xffffu;
      }
      barrier();
   }

   sortScatterKeysShared(offsets, keys);
   sortLoadThreadBlockReductions(localID, groupID, exclusiveHistReduction, threadBlocks);
   barrier();

   if (groupID < threadBlocks - 1u) {
      sortScatterPairsDevice(localID, groupID, offsets);
   } else {
      sortScatterPairsDevicePartial(localID, groupID, offsets);
   }
}

#endif

#endif
