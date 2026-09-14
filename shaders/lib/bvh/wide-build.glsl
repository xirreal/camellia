#ifndef BVH_WIDE_BUILD_INCLUDE_GUARD
#define BVH_WIDE_BUILD_INCLUDE_GUARD

// H-PLOC largest-area opening with independent output at each binary address.
#include "/lib/bvh/hploc.glsl"
#include "/lib/bvh/wide.glsl"
#include "/lib/buffers/control.glsl"
#include "/lib/buffers/bvh2-node.glsl"
#include "/lib/buffers/quad-geometry.glsl"

void wideBounds(uint id, out vec3 lo, out vec3 hi) {
   if (isInternalNode(id)) {
      BVH2Node node = bvh2Nodes[getClusterPrimID(id)];
      lo = node.boundsMin;
      hi = node.boundsMax;
   } else {
      vec3 p0, p1, p2, p3;
      unpackQuadGeometryPositions(quadGeometry[id], p0, p1, p2, p3);
      lo = min(min(p0, p1), min(p2, p3));
      hi = max(max(p0, p1), max(p2, p3));
   }
}

void wideSetChild(inout BVH4Node node, uint c, uint id) {
   vec3 lo, hi;
   wideBounds(id, lo, hi);
   node.children[c] = id;
   node.minX[c] = lo.x; node.minY[c] = lo.y; node.minZ[c] = lo.z;
   node.maxX[c] = hi.x; node.maxY[c] = hi.y; node.maxZ[c] = hi.z;
}

bool wideOpenLargest(inout BVH4Node node, uint count) {
   vec4 dx = node.maxX - node.minX;
   vec4 dy = node.maxY - node.minY;
   vec4 dz = node.maxZ - node.minZ;
   // Keep tie-breaking reproducible across compiler FMA contraction choices.
   precise vec4 area = dx * dy + dx * dz + dy * dz;
   bvec4 internal = notEqual(node.children & uvec4(CLUSTER_INTERNAL_BIT), uvec4(0u));
   area = mix(vec4(-1.0), area, internal);
   area = mix(area, vec4(-1.0), equal(node.children, uvec4(INVALID_ID)));
   uint a = area.x >= area.y ? 0u : 1u;
   uint b = area.z >= area.w ? 2u : 3u;
   uint largest = area[a] >= area[b] ? a : b;
   if (area[largest] < 0.0) return false;
   BVH2Node opened = bvh2Nodes[getClusterPrimID(node.children[largest])];
   wideSetChild(node, largest, opened.leftChild);
   wideSetChild(node, count, opened.rightChild);
   return true;
}

// Every binary node independently exposes its four-child frontier. Child IDs
// retain binary addresses; unreachable candidates cost bandwidth but no queue,
// polling, global allocation, or cross-workgroup producer/consumer scheduling.
void bvhWideBuild() {
   uint id = gl_GlobalInvocationID.x;
   if (control.sceneFrozen != 0u || id >= control.numBVH2Nodes) return;
   BVH2Node root = bvh2Nodes[id];
   BVH4Node node;
   node.minX = node.minY = node.minZ = vec4(3.402823466e+38);
   node.maxX = node.maxY = node.maxZ = vec4(-3.402823466e+38);
   node.children = uvec4(INVALID_ID);
   wideSetChild(node, 0u, root.leftChild);
   wideSetChild(node, 1u, root.rightChild);
   if (wideOpenLargest(node, 2u)) wideOpenLargest(node, 3u);
   storeBVH4(id, node);
   if (id == 0u) control.wideNodeCount = control.numBVH2Nodes;
}

#endif
