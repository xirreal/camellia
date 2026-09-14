#ifndef BVH_WIDE_INCLUDE_GUARD
#define BVH_WIDE_INCLUDE_GUARD

#ifndef BVH4_NODE_BUFFER_QUALIFIERS
#define BVH4_NODE_BUFFER_QUALIFIERS restrict readonly
#endif
// The leaf AABB stream is dead after H-PLOC. Reuse its allocation for BVH4.
layout(std430, binding = 2) BVH4_NODE_BUFFER_QUALIFIERS buffer BVH4NodeBuffer {
   BVH4Node bvh4Nodes[];
};

#if MAX_QUAD_COUNT == 33554432
// Keep each allocation below Iris's signed 32-bit buffer-size limit.
layout(std430, binding = 12) BVH4_NODE_BUFFER_QUALIFIERS buffer BVH4OverflowBuffer {
   BVH4Node bvh4Overflow[];
};
#endif

#ifdef BVH4_WRITE
void storeBVH4(uint id, BVH4Node node) {
#if MAX_QUAD_COUNT == 33554432
   if (id >= MAX_QUAD_COUNT / 2u) {
      bvh4Overflow[id - MAX_QUAD_COUNT / 2u] = node;
      return;
   }
#endif
   bvh4Nodes[id] = node;
}
#else
BVH4Node loadBVH4(uint id) {
#if MAX_QUAD_COUNT == 33554432
   if (id >= MAX_QUAD_COUNT / 2u) return bvh4Overflow[id - MAX_QUAD_COUNT / 2u];
#endif
   return bvh4Nodes[id];
}
#endif

#endif
