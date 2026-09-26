#ifndef PRIMITIVE_CAPTURE_INCLUDE_GUARD
#define PRIMITIVE_CAPTURE_INCLUDE_GUARD

#define QUAD_WRITE
#define QUAD_WRITE_RECORDS_ONLY
// All assembled-triangle paths share the existing triangle diagnostics row.
#define CAPTURE_DEBUG_PATH 9
#include "/lib/core/storage.glsl"
#include "/lib/scene/quad-write.glsl"

uint getTriangleWriteID() {
   uvec4 live = subgroupBallot(true);
   uint count = subgroupBallotBitCount(live);
   uint rank = subgroupBallotExclusiveBitCount(live);
   uint base = INVALID_ID;
   bool elected = subgroupElect();
   if (elected) base = atomicAdd(quadCount, count);
   base = subgroupBroadcastFirst(base);
   #ifdef ENABLE_SUBGROUP_VALIDATION
   validateTriangleAllocation(live, count, rank, base, elected);
   #endif
   return base + count <= uint(MAX_QUAD_COUNT) ? base + rank : INVALID_ID;
}

#endif
