#ifndef SORT_INCLUDE_GUARD
#define SORT_INCLUDE_GUARD

// SORT_PASS must be defined before including (0-7)
// SORT_PHASE must be defined before including (0=upsweep, 1=scan, 2=downsweep)

uint sortGetN() {
   return control.data[CTRL_SORT_TOTAL];
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

// ============================================================
// PHASE 0: UPSWEEP (Histogram)
// ============================================================
// Each workgroup builds a local histogram of the current 4-bit digit
// and writes it to the per-workgroup pass histogram in global memory.

#if SORT_PHASE == 0

shared uint localHist[RADIX];

void sortUpsweep() {
   uint gID = gl_GlobalInvocationID.x;
   uint lID = gl_LocalInvocationID.x;
   uint wgID = gl_WorkGroupID.x;
   uint N = sortGetN();
   uint numWG = (N + SORT_WG_SIZE - 1u) / SORT_WG_SIZE;

   if (wgID >= numWG) return;

   if (lID < RADIX) localHist[lID] = 0u;
   barrier();

   if (gID < N) {
      uint key = sortReadKey(gID);
      uint digit = sortExtractDigit(key);
      atomicAdd(localHist[digit], 1u);
   }
   barrier();

   if (lID < RADIX) {
      sortScratch[SORT_SCRATCH_PASS_HIST + lID * SORT_MAX_WORKGROUPS + wgID] = localHist[lID];
   }
}

#endif

// ============================================================
// PHASE 1: SCAN
// ============================================================
// Dispatch RADIX workgroups. Each workgroup computes the exclusive
// prefix sum of its digit bucket across all pass-histogram entries,
// then stores the digit total for use by the downsweep.

#if SORT_PHASE == 1

shared uint scanTemp[SORT_WG_SIZE];

void sortScan() {
   uint lID = gl_LocalInvocationID.x;
   uint digitBucket = gl_WorkGroupID.x;

   if (digitBucket >= RADIX) return;

   uint N = sortGetN();
   uint numWG = (N + SORT_WG_SIZE - 1u) / SORT_WG_SIZE;
   uint baseOffset = SORT_SCRATCH_PASS_HIST + digitBucket * SORT_MAX_WORKGROUPS;

   uint runningSum = 0u;

   for (uint chunkStart = 0u; chunkStart < numWG; chunkStart += SORT_WG_SIZE) {
      uint idx = chunkStart + lID;
      uint val = (idx < numWG) ? sortScratch[baseOffset + idx] : 0u;

      scanTemp[lID] = val;
      barrier();

      for (uint stride = 1u; stride < SORT_WG_SIZE; stride <<= 1u) {
         uint temp = (lID >= stride) ? scanTemp[lID - stride] : 0u;
         barrier();
         scanTemp[lID] += temp;
         barrier();
      }

      uint inclusive = scanTemp[lID];
      uint exclusive = inclusive - val;

      if (idx < numWG) {
         sortScratch[baseOffset + idx] = exclusive + runningSum;
      }

      barrier();
      runningSum += scanTemp[SORT_WG_SIZE - 1u];
      barrier();
   }

   if (lID == 0u) {
      sortScratch[SORT_SCRATCH_DIGIT_TOTALS + digitBucket] = runningSum;
   }
}

#endif

// ============================================================
// PHASE 2: DOWNSWEEP (Scatter)
// ============================================================
// Each workgroup loads its items, ranks them locally per digit,
// then scatters to the destination buffer using:
//   globalPrefix[digit] + passPrefix[digit][wgID] + localRank

#if SORT_PHASE == 2

shared uint localDigits[SORT_WG_SIZE];
shared uint globalPrefix[RADIX];

void sortDownsweep() {
   uint gID = gl_GlobalInvocationID.x;
   uint lID = gl_LocalInvocationID.x;
   uint wgID = gl_WorkGroupID.x;
   uint N = sortGetN();
   uint numWG = (N + SORT_WG_SIZE - 1u) / SORT_WG_SIZE;

   if (wgID >= numWG) return;

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
   localDigits[lID] = digit;
   barrier();

   if (valid) {
      uint rank = 0u;
      for (uint j = 0u; j < lID; j++) {
         if (localDigits[j] == digit) rank++;
      }

      uint passPrefix = sortScratch[SORT_SCRATCH_PASS_HIST + digit * SORT_MAX_WORKGROUPS + wgID];
      uint outputIndex = globalPrefix[digit] + passPrefix + rank;
      sortWriteKey(outputIndex, key);
      sortWriteVal(outputIndex, val);
   }
}

#endif

#endif
