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

const float MAX_FLOAT = float(0xFFFFFFFFu);

const uint GEOM_ID_BVH2 = 255u;
const uint INVALID_ID = 0xFFFFFFFFu;
const uint WAVE_SIZE = 32u;
const uint SEARCH_RADIUS_SHIFT = 3u;
const uint SEARCH_RADIUS = 1u << SEARCH_RADIUS_SHIFT;

const uint RADIX_BITS = 4u;
const uint RADIX = 1u << RADIX_BITS;
const uint SORT_WG_SIZE = 256u;
const uint SORT_MAX_WORKGROUPS = (MAX_QUAD_COUNT + SORT_WG_SIZE - 1u) / SORT_WG_SIZE;

const uint SORT_SCRATCH_KEYS = 0u;
const uint SORT_SCRATCH_VALS = MAX_QUAD_COUNT;
const uint SORT_SCRATCH_PASS_HIST = MAX_QUAD_COUNT * 2u;
const uint SORT_SCRATCH_DIGIT_TOTALS = SORT_SCRATCH_PASS_HIST + RADIX * SORT_MAX_WORKGROUPS;

#ifdef AS_VERTEX

layout(std430, binding = 0) buffer VertexBuffer {
   uint count;
   Vertex vertices[];
};

uint getVertexWriteIndex() {
   uvec4 activeMask = subgroupBallot(true);
   uint activeThreads = subgroupBallotBitCount(activeMask);

   uint vertexId = 0u;

   if (subgroupElect()) {
      vertexId = atomicAdd(count, activeThreads);
   }

   vertexId = subgroupBroadcastFirst(vertexId);
   vertexId += subgroupBallotExclusiveBitCount(activeMask);

   return vertexId;
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

layout(std430, binding = 1) buffer ControlBuffer {
   uint boundsMinX;
   uint boundsMinY;
   uint boundsMinZ;
   uint boundsMaxX;
   uint boundsMaxY;
   uint boundsMaxZ;
   uint bvh2NodeCount;
   uint sortTotal;
   uint sortErrors;
   uint pairErrors;
   uint prepareDispatchX;
   uint prepareDispatchY;
   uint prepareDispatchZ;
   uint sortDispatchX;
   uint sortDispatchY;
   uint sortDispatchZ;
   uint sortScatterX;
   uint sortScatterY;
   uint sortScatterZ;
   uint hplocDispatchX;
   uint hplocDispatchY;
   uint hplocDispatchZ;
} control;

uvec3 encodeBound(vec3 pos) {
   vec3 normalized = clamp((pos + far) / (2.0 * far), 0.0, 1.0);
   return uvec3(normalized * MAX_FLOAT);
}

float decodeBound(uint encodedVal) {
   float normalized = float(encodedVal) / MAX_FLOAT;
   return normalized * (2.0 * far) - far;
}

vec3 getSceneMax() {
   return vec3(
      decodeBound(control.boundsMaxX),
      decodeBound(control.boundsMaxY),
      decodeBound(control.boundsMaxZ)
   );
}

vec3 getSceneMin() {
   return vec3(
      decodeBound(control.boundsMinX),
      decodeBound(control.boundsMinY),
      decodeBound(control.boundsMinZ)
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
