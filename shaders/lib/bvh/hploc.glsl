#ifndef HPLOC_INCLUDE_GUARD
#define HPLOC_INCLUDE_GUARD

/*
   H-PLOC: Hierarchical Parallel Locally-Ordered Clustering
   for Bounding Volume Hierarchy Construction

   https://gpuopen.com/download/HPLOC.pdf
   GLSL port based on Slang implementation by natevm
   https://gist.github.com/natevm/6618402427ad6466bf555d67602adfa8
   Copyright (c) 2024 Nathan V. Morrical. Upstream MIT terms:
   licenses/HPLOC-MIT.txt. Embree-derived offset helpers: Apache-2.0.
   Modified GLSL adaptation; see THIRD_PARTY_NOTICES.md for full credits.
*/

// Cluster ID layout: bit 31 = internal (BVH2 node) flag, bits 0-30 = primID
// INVALID_ID (0xFFFFFFFF) must be checked before decoding.
#define CLUSTER_INTERNAL_BIT 0x80000000u
#define CLUSTER_PRIM_MASK    0x7FFFFFFFu

#if HPLOC_SEARCH_RADIUS_SHIFT < 0
#if MODE == 4
#define SEARCH_RADIUS_SHIFT 0
#else
#define SEARCH_RADIUS_SHIFT 1
#endif
#else
#define SEARCH_RADIUS_SHIFT HPLOC_SEARCH_RADIUS_SHIFT
#endif
#define SEARCH_RADIUS (1u << SEARCH_RADIUS_SHIFT)

uint makeLeafID(uint primID) {
   return primID & CLUSTER_PRIM_MASK;
}

uint makeInternalID(uint primID) {
   return CLUSTER_INTERNAL_BIT | (primID & CLUSTER_PRIM_MASK);
}

uint getClusterPrimID(uint clusterID) {
   return clusterID & CLUSTER_PRIM_MASK;
}

bool isInternalNode(uint clusterID) {
   return (clusterID & CLUSTER_INTERNAL_BIT) != 0u;
}

float computeSurfaceArea(vec3 bMin, vec3 bMax) {
   vec3 d = bMax - bMin;
   return max(2.0 * (d.x * d.y + d.x * d.z + d.y * d.z), 0.0);
}

float computeMergedSurfaceArea(vec3 aMin, vec3 aMax, vec3 bMin, vec3 bMax) {
   vec3 d = max(aMax, bMax) - min(aMin, bMin);
   return d.x * d.y + d.x * d.z + d.y * d.z;
}

uint encodeRelativeOffset(uint ID, uint neighbor) {
   uint uOffset = neighbor - ID - 1u;
   return uOffset << 1u;
}

int decodeRelativeOffset(int localID, uint offset, uint ID) {
   uint off = (offset >> 1u) + 1u;
   return localID + (((offset ^ ID) % 2u == 0u) ? int(off) : -int(off));
}

#endif
