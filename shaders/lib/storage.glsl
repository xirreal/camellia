#ifndef STORAGE_INCLUDE_GUARD
#define STORAGE_INCLUDE_GUARD

uniform float far;

#extension GL_KHR_shader_subgroup_arithmetic : require
#extension GL_KHR_shader_subgroup_ballot : require
#extension GL_KHR_shader_subgroup_clustered : require
#extension GL_KHR_shader_subgroup_vote : enable
#extension GL_KHR_shader_subgroup_shuffle : enable
#extension GL_KHR_shader_subgroup_shuffle_relative : enable

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

// Control buffer offsets (in uint indices, multiply by 4 for bytes)
const uint CTRL_BOUNDS_MIN_X = 0u;
const uint CTRL_BOUNDS_MIN_Y = 1u;
const uint CTRL_BOUNDS_MIN_Z = 2u;
const uint CTRL_BOUNDS_MAX_X = 3u;
const uint CTRL_BOUNDS_MAX_Y = 4u;
const uint CTRL_BOUNDS_MAX_Z = 5u;
const uint CTRL_BVH2_NODE_COUNT = 6u;
const uint CTRL_SORT_TOTAL = 7u;
const uint CTRL_PREPARE_DISPATCH_X = 12u;
const uint CTRL_PREPARE_DISPATCH_Y = 13u;
const uint CTRL_PREPARE_DISPATCH_Z = 14u;
const uint CTRL_SORT_DISPATCH_X = 15u;
const uint CTRL_SORT_DISPATCH_Y = 16u;
const uint CTRL_SORT_DISPATCH_Z = 17u;
const uint CTRL_SORT_SCATTER_X = 18u;
const uint CTRL_SORT_SCATTER_Y = 19u;
const uint CTRL_SORT_SCATTER_Z = 20u;
const uint CTRL_HPLOC_DISPATCH_X = 21u;
const uint CTRL_HPLOC_DISPATCH_Y = 22u;
const uint CTRL_HPLOC_DISPATCH_Z = 23u;

// Sort constants
const uint RADIX_BITS = 4u;
const uint RADIX = 1u << RADIX_BITS; // 16
const uint SORT_WG_SIZE = 256u;
// Max number of sort workgroups
const uint SORT_MAX_WORKGROUPS = (MAX_QUAD_COUNT + SORT_WG_SIZE - 1u) / SORT_WG_SIZE;

// Sort scratch buffer layout (in uint offsets within buffer 7)
// Ping-pong keys: MAX_QUAD_COUNT uints
const uint SORT_SCRATCH_KEYS = 0u;
// Ping-pong values: MAX_QUAD_COUNT uints
const uint SORT_SCRATCH_VALS = MAX_QUAD_COUNT;
// Per-workgroup pass histogram: RADIX * SORT_MAX_WORKGROUPS uints
const uint SORT_SCRATCH_PASS_HIST = MAX_QUAD_COUNT * 2u;
// Per-digit totals: RADIX uints (written by scan, read by downsweep)
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
   uint data[];
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
      decodeBound(control.data[CTRL_BOUNDS_MAX_X]),
      decodeBound(control.data[CTRL_BOUNDS_MAX_Y]),
      decodeBound(control.data[CTRL_BOUNDS_MAX_Z])
   );
}

vec3 getSceneMin() {
   return vec3(
      decodeBound(control.data[CTRL_BOUNDS_MIN_X]),
      decodeBound(control.data[CTRL_BOUNDS_MIN_Y]),
      decodeBound(control.data[CTRL_BOUNDS_MIN_Z])
   );
}

void updateSceneBounds(vec3 pos) {
   vec3 sMin = subgroupMin(pos);
   vec3 sMax = subgroupMax(pos);

   if (subgroupElect()) {
      uvec3 uMin = encodeBound(sMin);
      uvec3 uMax = encodeBound(sMax);

      atomicMin(control.data[CTRL_BOUNDS_MIN_X], uMin.x);
      atomicMin(control.data[CTRL_BOUNDS_MIN_Y], uMin.y);
      atomicMin(control.data[CTRL_BOUNDS_MIN_Z], uMin.z);

      atomicMax(control.data[CTRL_BOUNDS_MAX_X], uMax.x);
      atomicMax(control.data[CTRL_BOUNDS_MAX_Y], uMax.y);
      atomicMax(control.data[CTRL_BOUNDS_MAX_Z], uMax.z);
   }
}

#endif
