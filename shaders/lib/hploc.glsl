#ifndef HPLOC_INCLUDE_GUARD
#define HPLOC_INCLUDE_GUARD

/*

https://gpuopen.com/download/HPLOC.pdf

H-PLOC
Hierarchical Parallel Locally-Ordered Clustering for
Bounding Volume Hierarchy Construction

GLSL port of the Slang implementation by natevm (https://gist.github.com/natevm/6618402427ad6466bf555d67602adfa8)

*/

const uint INVALID_ID = 0xFFFFFFFFu;

struct BVH2Node {
   vec3 minBounds;
   uint leftChild;
   vec3 maxBounds;
   uint rightChild;
}; // 32 bytes -> BVH2Node fits nicely into a QuadLeaf -> we can reuse the same storage buffer

struct BVH8Node {
   // [32b origin x] [32b origin y]
   uint originX;
   uint originY;
   uint originZ;

   // [8b extent x] [8b extent y] [8b extent z] [8b inner node mask]
   uint extentAndInnerNodeMask;

   // [32b child node base index] [32b triangle base index]
   uint childNodeBaseIndex;
   uint quadBaseIndex;

   // [8b child 0] ... [8b child 7]
   uint meta1;
   uint meta2

   // Quantized bounds
   uint qMinX;
   uint qMinY;
   uint qMinZ;
   uint qMaxX;
   uint qMaxY;
   uint qMaxZ;
};

struct BVH8Leaf {
   float v[9];
   uint clusterID;
};

struct AABB {
   vec3 minBounds;
   vec3 maxBounds;
};

layout(std430, binding = 2) buffer BVH2NodeBuffer {
   BVH2Node bvh2Nodes[];
};

layout(std430, binding = 3) buffer BVH8Buffer {
   BVH8Node bvh8Nodes[]; // ceil((N * 2 - 1) / 8) nodes
};

layout(std430, binding = 4) buffer BVH8LeafBuffer {
   BVH8Leaf bvh8Leaves[]; // N leaves
};

layout(std430, binding = 4) buffer AtomicCounterBuffer {
   uint ac[]; // 6 counters
};

layout(std430, binding = 5) buffer IndexBuffer { // params.I
   uint indices[]; // N indices
};

layout(std430, binding = 6) buffer MortonCodeBuffer { // params.C
   uint curveCodes[]; // N codes, 32bit in our implementation
};

layout(std430, binding = 7) buffer ParentIDBuffer { // params.pID
   uint parentIDs[]; // N, initialized to -1
};

layout(std430, binding = 8) buffer IndexPairsBuffer { // params.indexPairs
   uvec2 indexPairs[]; // N pairs (BVH2 to BVH8)
};

layout(std430, binding = 9) buffer AABBsBuffer {
   AABB aabbs[]; // N AABBs
}

#endif
