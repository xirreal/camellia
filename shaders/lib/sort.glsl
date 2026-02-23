#ifndef SORT_INCLUDE_GUARD
#define SORT_INCLUDE_GUARD

// Max possible subgroups in a sort workgroup (handles subgroup sizes down to 8)
#define SORT_MAX_SUBGROUPS (SORT_WG_SIZE / 8u)

uint sortGetN() {
   return control.sortTotal;
}

uint sortExtractDigit(uint key) {
   return (key >> (SORT_PASS * RADIX_BITS)) & (RADIX - 1u);
}

bool sortIsPassEven() {
   return (SORT_PASS & 1u) == 0u;
}

uint sortReadKey(uint index) {
   if (sortIsPassEven()) return mortonCodes[index];
   else return sortScratch[SORT_SCRATCH_KEYS + index];
}

uint sortReadVal(uint index) {
   if (sortIsPassEven()) return clusterIndices[index];
   else return sortScratch[SORT_SCRATCH_VALS + index];
}

void sortWriteKey(uint index, uint key) {
   if (sortIsPassEven()) sortScratch[SORT_SCRATCH_KEYS + index] = key;
   else mortonCodes[index] = key;
}

void sortWriteVal(uint index, uint val) {
   if (sortIsPassEven()) sortScratch[SORT_SCRATCH_VALS + index] = val;
   else clusterIndices[index] = val;
}

// upsweep (histogram build) - subgroup ballot based, no shared atomics

#if SORT_PHASE == 0

shared uint subgroupHist[SORT_MAX_SUBGROUPS * RADIX];

void sortUpsweep() {
   uint gID = gl_GlobalInvocationID.x;
   uint lID = gl_LocalInvocationID.x;
   uint wgID = gl_WorkGroupID.x;
   uint N = sortGetN();
   uint numWG = (N + SORT_WG_SIZE - 1u) / SORT_WG_SIZE;

   if (wgID >= numWG) return;

   uint subgroupID = lID / gl_SubgroupSize;
   uint numSubgroups = SORT_WG_SIZE / gl_SubgroupSize;

   // Clear per-subgroup histograms
   for (uint i = lID; i < numSubgroups * RADIX; i += SORT_WG_SIZE) {
      subgroupHist[i] = 0u;
   }
   barrier();

   uint digit = RADIX;
   if (gID < N) {
      digit = sortExtractDigit(sortReadKey(gID));
   }

   // Per-subgroup histogram via ballot
   for (uint d = 0u; d < RADIX; d++) {
      uvec4 mask = subgroupBallot(digit == d);
      if (subgroupElect()) {
         subgroupHist[subgroupID * RADIX + d] = subgroupBallotBitCount(mask);
      }
   }
   barrier();

   // Merge subgroup histograms
   if (lID < RADIX) {
      uint sum = 0u;
      for (uint s = 0u; s < numSubgroups; s++) {
         sum += subgroupHist[s * RADIX + lID];
      }
      sortScratch[SORT_SCRATCH_PASS_HIST + lID * SORT_MAX_WORKGROUPS + wgID] = sum;
   }
}

#endif

// radix scan (exclusive prefix sum of histograms) - subgroup accelerated

#if SORT_PHASE == 1

shared uint subgroupTotals[SORT_MAX_SUBGROUPS];
shared uint chunkTotal;

void sortScan() {
   uint lID = gl_LocalInvocationID.x;
   uint digitBucket = gl_WorkGroupID.x;

   if (digitBucket >= RADIX) return;

   uint N = sortGetN();
   uint numWG = (N + SORT_WG_SIZE - 1u) / SORT_WG_SIZE;
   uint baseOffset = SORT_SCRATCH_PASS_HIST + digitBucket * SORT_MAX_WORKGROUPS;
   uint subgroupID = lID / gl_SubgroupSize;
   uint numSubgroups = SORT_WG_SIZE / gl_SubgroupSize;

   uint runningSum = 0u;

   for (uint chunkStart = 0u; chunkStart < numWG; chunkStart += SORT_WG_SIZE) {
      uint idx = chunkStart + lID;
      uint val = (idx < numWG) ? sortScratch[baseOffset + idx] : 0u;

      // Subgroup-level exclusive prefix sum
      uint subExcl = subgroupExclusiveAdd(val);
      uint subTotal = subgroupAdd(val);

      if (subgroupElect()) {
         subgroupTotals[subgroupID] = subTotal;
      }
      barrier();

      // Serial exclusive scan of subgroup totals
      if (lID == 0u) {
         uint sum = 0u;
         for (uint s = 0u; s < numSubgroups; s++) {
            uint t = subgroupTotals[s];
            subgroupTotals[s] = sum;
            sum += t;
         }
         chunkTotal = sum;
      }
      barrier();

      // Final exclusive prefix = running + cross-subgroup offset + intra-subgroup prefix
      uint exclusive = runningSum + subgroupTotals[subgroupID] + subExcl;

      if (idx < numWG) {
         sortScratch[baseOffset + idx] = exclusive;
      }

      runningSum += chunkTotal;
      barrier();
   }

   if (lID == 0u) {
      sortScratch[SORT_SCRATCH_DIGIT_TOTALS + digitBucket] = runningSum;
   }
}

#endif

// downsweep (scatter to output) - subgroup ballot ranking

#if SORT_PHASE == 2

shared uint globalPrefix[RADIX];
shared uint subgroupDigitCount[SORT_MAX_SUBGROUPS * RADIX];

void sortDownsweep() {
   uint gID = gl_GlobalInvocationID.x;
   uint lID = gl_LocalInvocationID.x;
   uint wgID = gl_WorkGroupID.x;
   uint N = sortGetN();
   uint numWG = (N + SORT_WG_SIZE - 1u) / SORT_WG_SIZE;

   if (wgID >= numWG) return;

   uint subgroupID = lID / gl_SubgroupSize;

   // Compute global digit prefix (exclusive scan of digit totals)
   if (lID < RADIX) {
      uint sum = 0u;
      for (uint d = 0u; d < lID; d++) {
         sum += sortScratch[SORT_SCRATCH_DIGIT_TOTALS + d];
      }
      globalPrefix[lID] = sum;
   }
   barrier();

   uint key = 0xFFFFFFFFu;
   uint val = 0u;
   bool valid = gID < N;
   if (valid) {
      key = sortReadKey(gID);
      val = sortReadVal(gID);
   }

   uint digit = valid ? sortExtractDigit(key) : RADIX;

   // Compute rank within subgroup and per-subgroup digit counts via ballot
   uint rankInSubgroup = 0u;
   for (uint d = 0u; d < RADIX; d++) {
      uvec4 mask = subgroupBallot(digit == d);
      if (subgroupElect()) {
         subgroupDigitCount[subgroupID * RADIX + d] = subgroupBallotBitCount(mask);
      }
      if (digit == d) {
         rankInSubgroup = subgroupBallotExclusiveBitCount(mask);
      }
   }
   barrier();

   // Scatter elements to sorted positions
   if (valid) {
      // Sum digit counts from all prior subgroups
      uint priorCount = 0u;
      for (uint s = 0u; s < subgroupID; s++) {
         priorCount += subgroupDigitCount[s * RADIX + digit];
      }

      uint localRank = priorCount + rankInSubgroup;
      uint passPrefix = sortScratch[SORT_SCRATCH_PASS_HIST + digit * SORT_MAX_WORKGROUPS + wgID];
      uint outputIndex = globalPrefix[digit] + passPrefix + localRank;
      sortWriteKey(outputIndex, key);
      sortWriteVal(outputIndex, val);
   }
}

#endif

#endif
