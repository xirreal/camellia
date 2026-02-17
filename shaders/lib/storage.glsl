#ifndef STORAGE_INCLUDE_GUARD
#define STORAGE_INCLUDE_GUARD

uniform float far;

#extension GL_KHR_shader_subgroup_arithmetic : require
#extension GL_KHR_shader_subgroup_ballot : require
#extension GL_KHR_shader_subgroup_clustered : require
#extension GL_KHR_shader_subgroup_vote : enable
#extension GL_KHR_shader_subgroup_shuffle : enable
#extension GL_KHR_shader_subgroup_shuffle_relative : enable

uint expandBits(uint v) {
   v &= 0x000003ffu;
   v = (v ^ (v << 16)) & 0xff0000ffu;
   v = (v ^ (v << 8)) & 0x0300f00fu;
   v = (v ^ (v << 4)) & 0x030c30c3u;
   v = (v ^ (v << 2)) & 0x09249249u;
   return v;
}

uint encodeMorton3D(vec3 normalizedPos) {
   uvec3 i = uvec3(clamp(normalizedPos, 0.0, 1.0) * vec3(2047.0, 1023.0, 2047.0));

   uint x_m = expandBits(i.x);
   uint z_m = expandBits(i.z);
   uint y_m = expandBits(i.y);

   uint x_top = (i.x & 0x0400u) << 20;
   uint z_top = (i.z & 0x0400u) << 20;

   uint x_final = x_m | x_top;
   uint z_final = z_m | z_top;
   uint y_final = y_m;

   return (y_final << 2) | (z_final << 1) | x_final;
}

struct Vertex {
   vec3 position;
   uint encodedNormal;
   vec2 uv;
   float emission;
   float _pad;
}; // 32 bytes (explicit padding for std430 array stride)

const uint MAX_VERTEX_COUNT = 33554432u;
const uint MAX_QUAD_COUNT = MAX_VERTEX_COUNT / 4u;

const uint INVALID_ID = 0xFFFFFFFFu;

const uint RADIX_BITS = 4u;
const uint RADIX = 1u << RADIX_BITS;
#define WG_SIZE 32 // [32 64 128]
const uint SORT_WG_SIZE = 256u;
const uint SORT_MAX_WORKGROUPS = (MAX_QUAD_COUNT + SORT_WG_SIZE - 1u) / SORT_WG_SIZE;

const uint SORT_SCRATCH_KEYS = 0u;
const uint SORT_SCRATCH_VALS = MAX_QUAD_COUNT;
const uint SORT_SCRATCH_PASS_HIST = MAX_QUAD_COUNT * 2u;
const uint SORT_SCRATCH_DIGIT_TOTALS = SORT_SCRATCH_PASS_HIST + RADIX * SORT_MAX_WORKGROUPS;

layout(std430, binding = 1) buffer ControlBuffer {
   uint boundsMinX; // 0
   uint boundsMinY; // 4
   uint boundsMinZ; // 8
   uint boundsMaxX; // 12
   uint boundsMaxY; // 16
   uint boundsMaxZ; // 20
   uint numBVH2Nodes; // 24
   uint sortTotal; // 28
   uint sortErrors; // 32
   uint pairErrors; // 36
   uint sortDispatchX; // 40
   uint sortDispatchY; // 44
   uint sortDispatchZ; // 48
   uint hplocDispatchX; // 52
   uint hplocDispatchY; // 56
   uint hplocDispatchZ; // 60
   uint buildError; // 64
   uint rootClusterID; // 68
   uint quadErrNanInf; // 72
   uint quadErrExtent; // 76
   uint quadErrCoplanar; // 80
   uint quadErrDegenerate; // 84
   uint quadErrCollapsed; // 88
   uint realCount1; // 92
   uint realCount2; // 96
} control;

#ifdef AS_VERTEX

layout(std430, binding = 0) buffer VertexBuffer {
   uint count;
   Vertex vertices[];
};

uint getVertexWriteIndex() {
   uvec4 activeMask = subgroupBallot(true);
   uint activeThreads = subgroupBallotBitCount(activeMask);
   uint allocatedCount = (activeThreads + 3u) & ~3u; // this will be unnecessary eventually

   uint baseVertexId = INVALID_ID;
   if (subgroupElect()) {
      baseVertexId = atomicAdd(count, allocatedCount);
   }
   baseVertexId = subgroupBroadcastFirst(baseVertexId);

   uint lane = subgroupBallotExclusiveBitCount(activeMask);

   if (baseVertexId + activeThreads > MAX_VERTEX_COUNT) return INVALID_ID;
   return baseVertexId + lane;
}

#else

struct Quad {
   Vertex v1;
   Vertex v2;
   Vertex v3;
   Vertex v4;
}; // 128 bytes

layout(std430, binding = 0) readonly buffer QuadBuffer {
   uint count;
   Quad quads[];
};

#endif

uint floatToOrderedUint(float v) {
   uint u = floatBitsToUint(v);
   uint mask = (u & 0x80000000u) != 0u ? 0xFFFFFFFFu : 0x80000000u;
   return u ^ mask;
}

float orderedUintToFloat(uint o) {
   uint mask = (o & 0x80000000u) != 0u ? 0x80000000u : 0xFFFFFFFFu;
   return uintBitsToFloat(o ^ mask);
}

uvec3 encodeBound(vec3 pos) {
   return uvec3(
      floatToOrderedUint(pos.x),
      floatToOrderedUint(pos.y),
      floatToOrderedUint(pos.z)
   );
}

vec3 getSceneMax() {
   return vec3(
      orderedUintToFloat(control.boundsMaxX),
      orderedUintToFloat(control.boundsMaxY),
      orderedUintToFloat(control.boundsMaxZ)
   );
}

vec3 getSceneMin() {
   return vec3(
      orderedUintToFloat(control.boundsMinX),
      orderedUintToFloat(control.boundsMinY),
      orderedUintToFloat(control.boundsMinZ)
   );
}

void updateSceneBounds(vec3 pos) {
   vec3 sMin = subgroupMin(pos);
   vec3 sMax = subgroupMax(pos);

   if (subgroupElect()) {
      uvec3 uMin = encodeBound(sMin);
      uvec3 uMax = encodeBound(sMax);

      atomicMin(control.boundsMinX, uMin.x);
      atomicMin(control.boundsMinY, uMin.y);
      atomicMin(control.boundsMinZ, uMin.z);

      atomicMax(control.boundsMaxX, uMax.x);
      atomicMax(control.boundsMaxY, uMax.y);
      atomicMax(control.boundsMaxZ, uMax.z);
   }
}

#endif
