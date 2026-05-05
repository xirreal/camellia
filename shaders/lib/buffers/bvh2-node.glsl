#ifndef BVH2_NODE_BUFFER_INCLUDE_GUARD
#define BVH2_NODE_BUFFER_INCLUDE_GUARD

#ifndef BVH2_NODE_BUFFER_QUALIFIERS
#define BVH2_NODE_BUFFER_QUALIFIERS restrict readonly
#endif

layout(std430, binding = 6) BVH2_NODE_BUFFER_QUALIFIERS buffer BVH2NodeBuffer {
   BVH2Node bvh2Nodes[];
};

#endif
