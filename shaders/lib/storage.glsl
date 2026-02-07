#ifndef STORAGE_INCLUDE_GUARD
#define STORAGE_INCLUDE_GUARD

uniform float far;

#extension GL_KHR_shader_subgroup_arithmetic : require
#extension GL_KHR_shader_subgroup_ballot : require
#extension GL_KHR_shader_subgroup_clustered : require
#extension GL_KHR_shader_subgroup_vote : enable
#extension GL_KHR_shader_subgroup_shuffle : enable

struct Vertex {
   vec3 position;
   uint encodedNormal;
   vec2 uv;
   float emission;
}; // 28 bytes

const uint MAX_VERTEX_COUNT = 33554432;
const uint MAX_QUAD_COUNT = MAX_VERTEX_COUNT / 4;

const float MAX_FLOAT = float(0xFFFFFFFFu);

// quad/vertex buffer:
// sizeof(Vertex) * MAX_VERTEX_COUNT + 4 = 939524096 bytes = 940MB
//
// for the quad leaves we need 1/4 of the amount of the vertex buffer, however entries are 32 bytes instead of 24 bytes:
// sizeof(QuadLeaf) * (MAX_VERTEX_COUNT / 4) = 26,843,536 bytes = 26MB

#ifdef AS_VERTEX

layout(std430, binding = 0) buffer VertexBuffer {
   uint count;
   Vertex vertices[];
};

uint getVertexWriteIndex() {
   // eval true in every thread in warp -> mask of threads in warp
   uvec4 activeMask = subgroupBallot(true);
   // count bits = n of active threads
   uint activeThreads = subgroupBallotBitCount(activeMask);

   uint vertexId = 0;

   // guaranteed to run only once per warp
   if (subgroupElect()) {
      // do the atomic, this returns the prev value
      vertexId = atomicAdd(count, activeThreads);
   }

   // broadcast previous value to other threads
   vertexId = subgroupBroadcastFirst(vertexId);
   // adds the n of bits lower than gl_SubgroupInvocationID
   vertexId += subgroupBallotExclusiveBitCount(activeMask);

   // every thread gets vertexIdPrev + thread id in warp
   return vertexId;
}

#else

struct Quad {
   Vertex v1;
   Vertex v2;
   Vertex v3;
   Vertex v4;
}; // sizeof(Vertex) * 4 = 28 * 4 = 112 bytes

layout(std430, binding = 0) readonly buffer QuadBuffer {
   uint count;
   Quad quads[];
};

#endif

layout(std430, binding = 1) buffer SceneBounds {
   uint minX, minY, minZ;
   uint maxX, maxY, maxZ;
} bounds;

uvec3 encodeBound(vec3 pos) {
   vec3 normalized = clamp((pos + far) / (2.0 * far), 0.0, 1.0);
   return uvec3(normalized * MAX_FLOAT);
}

float decodeBound(uint encodedVal) {
   float normalized = float(encodedVal) / MAX_FLOAT;
   return normalized * (2.0 * far) - far;
}

vec3 getSceneMax() {
   return vec3(decodeBound(bounds.maxX), decodeBound(bounds.maxY), decodeBound(bounds.maxZ));
}

vec3 getSceneMin() {
   return vec3(decodeBound(bounds.minX), decodeBound(bounds.minY), decodeBound(bounds.minZ));
}

void updateSceneBounds(vec3 pos) {
   vec3 sMin = subgroupMin(pos);
   vec3 sMax = subgroupMax(pos);

   if (subgroupElect()) {
      uvec3 uMin = encodeBound(sMin);
      uvec3 uMax = encodeBound(sMax);

      atomicMin(bounds.minX, uMin.x);
      atomicMin(bounds.minY, uMin.y);
      atomicMin(bounds.minZ, uMin.z);

      atomicMax(bounds.maxX, uMax.x);
      atomicMax(bounds.maxY, uMax.y);
      atomicMax(bounds.maxZ, uMax.z);
   }
}

#endif
