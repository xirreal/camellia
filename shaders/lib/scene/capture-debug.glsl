#ifndef CAPTURE_DEBUG_INCLUDE_GUARD
#define CAPTURE_DEBUG_INCLUDE_GUARD

uint captureBitCount(uvec4 mask) {
   ivec4 counts = bitCount(mask);
   return uint(counts.x + counts.y + counts.z + counts.w);
}

uint captureFirstLane(uvec4 mask) {
   if (mask.x != 0u) return uint(findLSB(mask.x));
   if (mask.y != 0u) return 32u + uint(findLSB(mask.y));
   if (mask.z != 0u) return 64u + uint(findLSB(mask.z));
   return 96u + uint(findLSB(mask.w));
}

uint captureQuadMask(uvec4 mask, uint first) {
   return (mask[first >> 5u] >> (first & 31u)) & 15u;
}

uint captureSafeShuffle(uint value, uint source, uvec4 live) {
   uint bounded = min(source, gl_SubgroupSize - 1u);
   bool available = source < gl_SubgroupSize && subgroupBallotBitExtract(live, bounded);
   return subgroupShuffle(value, available ? source : gl_SubgroupInvocationID);
}

uvec4 capturePeers(uint value, uint first, uvec4 live) {
   return uvec4(captureSafeShuffle(value, first, live), captureSafeShuffle(value, first + 1u, live),
      captureSafeShuffle(value, first + 2u, live), captureSafeShuffle(value, first + 3u, live));
}

bool captureAllocationOps(uvec4 live, uvec4 enabled, uint count, uint rank, uint base, bool elected) {
   uvec4 leaders = subgroupBallot(elected);
   uint first = captureFirstLane(live);
   uint firstBase = subgroupShuffle(base, first);
   bool valid = captureBitCount(leaders) == 1u && subgroupBallotBitExtract(leaders, first) &&
      count == captureBitCount(enabled) && rank == captureBitCount(enabled & gl_SubgroupLtMask) && base == firstBase;
   bool failed = subgroupAny(!valid);
   if (subgroupElect()) {
      atomicAdd(control.captureSubgroups[CAPTURE_DEBUG_PATH].groups, 1u);
      atomicOr(control.captureSubgroups[CAPTURE_DEBUG_PATH].sizeMask, 1u << uint(findMSB(gl_SubgroupSize)));
      atomicAdd(control.captureSubgroups[CAPTURE_DEBUG_PATH].operations, uint(failed));
   }
   return !failed;
}

void captureExample(uint flags, uint first, uvec4 live, uvec4 enabled,
   uvec4 vertices, uvec4 ids, uvec4 slots, uvec4 instances, uvec4 context) {
   if (flags == 0u || atomicCompSwap(control.captureSubgroups[CAPTURE_DEBUG_PATH].firstFailure, 0u, flags) != 0u) return;
   control.captureSubgroups[CAPTURE_DEBUG_PATH].exampleInfo = uvec4(gl_SubgroupSize, gl_SubgroupInvocationID, first, flags);
   control.captureSubgroups[CAPTURE_DEBUG_PATH].exampleLive = live;
   control.captureSubgroups[CAPTURE_DEBUG_PATH].exampleEnabled = enabled;
   control.captureSubgroups[CAPTURE_DEBUG_PATH].exampleVertices = vertices;
   control.captureSubgroups[CAPTURE_DEBUG_PATH].exampleQuadIDs = ids;
   control.captureSubgroups[CAPTURE_DEBUG_PATH].exampleSlots = slots;
   control.captureSubgroups[CAPTURE_DEBUG_PATH].exampleInstances = instances;
   control.captureSubgroups[CAPTURE_DEBUG_PATH].exampleContext = context;
}

bool captureFinite(vec3 value) {
   return !any(isnan(value)) && !any(isinf(value));
}

bool captureHalfFits(vec3 value) {
   return captureFinite(value) && all(lessThanEqual(abs(value), vec3(65504.0)));
}

#ifndef QUAD_WRITE_RECORDS_ONLY
void validateQuadAllocation(uvec4 enabledMask, uint count, uint rank, uint base, bool elected, uint quadID, uint slot) {
   uvec4 live = subgroupBallot(true);
   uint first = gl_SubgroupInvocationID & ~3u;
   uint present = captureQuadMask(live, first);
   uint selected = captureQuadMask(enabledMask, first);
   bool leader = gl_SubgroupInvocationID == first + uint(findLSB(present));
   bool requested = selected != 0u;
   bool full = gl_SubgroupSize >= 4u && present == 15u;
   bool selection = selected == 0u || selected == present;
   uvec4 vertices = capturePeers(uint(gl_VertexID), first, live);
   uvec4 instances = capturePeers(uint(gl_InstanceID), first, live);
   uvec4 ids = capturePeers(quadID, first, live);
   uvec4 slots = capturePeers(slot, first, live);
   uvec4 bases = capturePeers(uint(gl_BaseVertex), first, live);
   uvec4 draws = capturePeers(uint(gl_DrawID), first, live);
   bool ordered = full && all(equal(vertices, uvec4(vertices.x) + uvec4(0u, 1u, 2u, 3u))) &&
      all(equal(instances, uvec4(instances.x))) && all(equal(bases, uvec4(bases.x))) && all(equal(draws, uvec4(draws.x)));
   bool aligned = full && ((vertices.x - bases.x) & 3u) == 0u;
   bool capacity = base < uint(MAX_QUAD_COUNT) && (rank >> 2u) < uint(MAX_QUAD_COUNT) - base;
   uvec4 overflowMask = subgroupBallot(subgroupBallotBitExtract(enabledMask, gl_SubgroupInvocationID) && !capacity);
   bool allocated = full && selected == 15u && ids.x < uint(MAX_QUAD_COUNT) && all(equal(ids, uvec4(ids.x)));
   bool slotsMatch = full && selected == 15u && all(equal(slots, uvec4(0u, 1u, 2u, 3u)));
   bool ops = captureAllocationOps(live, enabledMask, count, rank, base, elected);
   uvec4 totals = subgroupAdd(uvec4(leader, leader && full, leader && selection, leader && ordered));
   uvec4 results = subgroupAdd(uvec4(leader && aligned, leader && requested && allocated,
      leader && requested && slotsMatch, leader && requested));
   uint overflow = captureBitCount(overflowMask);
   if (subgroupElect()) {
      atomicAdd(control.captureSubgroups[CAPTURE_DEBUG_PATH].tests, totals.x);
      atomicAdd(control.captureSubgroups[CAPTURE_DEBUG_PATH].full, totals.y);
      atomicAdd(control.captureSubgroups[CAPTURE_DEBUG_PATH].selected, totals.z);
      atomicAdd(control.captureSubgroups[CAPTURE_DEBUG_PATH].ordered, totals.w);
      atomicAdd(control.captureSubgroups[CAPTURE_DEBUG_PATH].aligned, results.x);
      atomicAdd(control.captureSubgroups[CAPTURE_DEBUG_PATH].allocated, results.y);
      atomicAdd(control.captureSubgroups[CAPTURE_DEBUG_PATH].slots, results.z);
      atomicAdd(control.captureSubgroups[CAPTURE_DEBUG_PATH].enabled, results.w);
      atomicAdd(control.captureSubgroups[CAPTURE_DEBUG_PATH].capacity, overflow);
      atomicAdd(control.quadSubgroupTests, totals.x);
      atomicAdd(control.quadSubgroupFull, totals.y);
      atomicAdd(control.quadSubgroupConsecutive, totals.w);
      atomicAdd(control.quadSubgroupAllocator, results.y);
      atomicAdd(control.quadSubgroupSlots, results.z);
   }
   uint flags = (gl_SubgroupSize < 4u ? 1u : 0u) | (!full ? 2u : 0u) | (!selection ? 4u : 0u) |
      (!ordered ? 8u : 0u) | (!aligned ? 16u : 0u) | (requested && !allocated ? 32u : 0u) |
      (requested && !slotsMatch ? 64u : 0u) | (captureQuadMask(overflowMask, first) != 0u ? 128u : 0u) | (!ops ? 256u : 0u);
   if (leader) captureExample(flags, first, live, enabledMask, vertices, ids, slots, instances,
      uvec4(base, count, uint(gl_BaseVertex), uint(gl_DrawID)));
}

void validateQuadWrite(uint quadID, uint slot, vec3 pos, vec3 delta, vec2 uv, vec3 tint, float emission) {
   uvec4 live = subgroupBallot(true);
   uvec4 writing = subgroupBallot(quadID < uint(MAX_QUAD_COUNT));
   uint first = gl_SubgroupInvocationID - slot;
   uvec4 ids = capturePeers(quadID, first, live);
   uvec4 slots = capturePeers(slot, first, live);
   uvec4 vertices = capturePeers(uint(gl_VertexID), first, live);
   uvec4 instances = capturePeers(uint(gl_InstanceID), first, live);
   bool sources = slot < 4u && first < gl_SubgroupSize && first + 3u < gl_SubgroupSize;
   for (uint i = 0u; i < 4u; ++i) {
      uint source = min(first + i, gl_SubgroupSize - 1u);
      sources = sources && subgroupBallotBitExtract(writing, source);
   }
   sources = sources && all(equal(ids, uvec4(quadID))) && all(equal(slots, uvec4(0u, 1u, 2u, 3u)));
   bool data = captureFinite(pos) && captureHalfFits(delta) && captureHalfFits(vec3(uv, 0.0)) &&
      captureFinite(tint) && !isnan(emission) && !isinf(emission);
   bool writes = quadID < uint(MAX_QUAD_COUNT);
   uvec3 totals = subgroupAdd(uvec3(writes, writes && sources, writes && data));
   if (subgroupElect()) {
      atomicAdd(control.captureSubgroups[CAPTURE_DEBUG_PATH].writeTests, totals.x);
      atomicAdd(control.captureSubgroups[CAPTURE_DEBUG_PATH].writeSources, totals.y);
      atomicAdd(control.captureSubgroups[CAPTURE_DEBUG_PATH].writeData, totals.z);
   }
   uint flags = (sources ? 0u : 512u) | (data ? 0u : 1024u);
   if (writes) captureExample(flags, first, live, writing, vertices, ids, slots, instances,
      uvec4(quadID, slot, uint(gl_BaseVertex), uint(gl_DrawID)));
}
#else
void validateTriangleAllocation(uvec4 live, uint count, uint rank, uint base, bool elected) {
   bool ops = captureAllocationOps(live, live, count, rank, base, elected);
   bool capacity = base < uint(MAX_QUAD_COUNT) && count <= uint(MAX_QUAD_COUNT) - base;
   if (subgroupElect()) {
      atomicAdd(control.captureSubgroups[CAPTURE_DEBUG_PATH].enabled, count);
      atomicAdd(control.captureSubgroups[CAPTURE_DEBUG_PATH].allocated, capacity ? count : 0u);
      atomicAdd(control.captureSubgroups[CAPTURE_DEBUG_PATH].capacity, capacity ? 0u : count);
   }
   captureExample((capacity ? 0u : 128u) | (ops ? 0u : 256u), gl_SubgroupInvocationID, live, live,
      uvec4(uint(gl_PrimitiveIDIn)), uvec4(base + rank), uvec4(rank), uvec4(uint(gl_InvocationID)), uvec4(base, count, 0u, 0u));
}

void validateTriangleWrite(uint quadID, vec3 p0, vec3 p1, vec3 p2, vec3 p3,
   vec2 uv0, vec2 uv1, vec2 uv2, vec3 tint, float emission) {
   bool data = captureFinite(p0) && captureHalfFits(p1 - p0) && captureHalfFits(p2 - p0) && captureHalfFits(p3 - p0) &&
      captureHalfFits(vec3(uv0, 0.0)) && captureHalfFits(vec3(uv1, 0.0)) && captureHalfFits(vec3(uv2, 0.0)) &&
      captureFinite(tint) && !isnan(emission) && !isinf(emission);
   uvec4 live = subgroupBallot(true);
   uint count = captureBitCount(live);
   uint passed = subgroupAdd(uint(data));
   if (subgroupElect()) {
      atomicAdd(control.captureSubgroups[CAPTURE_DEBUG_PATH].writeTests, count);
      atomicAdd(control.captureSubgroups[CAPTURE_DEBUG_PATH].writeData, passed);
   }
   captureExample(data ? 0u : 1024u, gl_SubgroupInvocationID, live, live,
      uvec4(uint(gl_PrimitiveIDIn)), uvec4(quadID), uvec4(0u), uvec4(uint(gl_InvocationID)), uvec4(0u));
}
#endif

#endif
