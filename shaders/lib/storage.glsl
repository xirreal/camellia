#ifndef STORAGE_INCLUDE_GUARD
#define STORAGE_INCLUDE_GUARD

uniform float far;

#extension GL_KHR_shader_subgroup_basic : require
#extension GL_KHR_shader_subgroup_arithmetic : require
#extension GL_KHR_shader_subgroup_ballot : require
#extension GL_KHR_shader_subgroup_clustered : require
#extension GL_KHR_shader_subgroup_vote : enable
#extension GL_KHR_shader_subgroup_shuffle : enable
#extension GL_KHR_shader_subgroup_shuffle_relative : enable

uvec3 expandBits3D(uvec3 v) {
   v &= 0x000003ffu;
   v = (v ^ (v << 16u)) & 0xff0000ffu;
   v = (v ^ (v << 8u)) & 0x0300f00fu;
   v = (v ^ (v << 4u)) & 0x030c30c3u;
   v = (v ^ (v << 2u)) & 0x09249249u;
   return v;
}

uint encodeMorton3D(vec3 normalizedPos) {
   uvec3 i = uvec3(clamp(normalizedPos, 0.0, 1.0) * vec3(2047.0, 1023.0, 2047.0));

   uvec3 expanded = expandBits3D(i);

   uint x_top = (i.x & 0x0400u) << 20u;
   uint z_top = (i.z & 0x0400u) << 20u;

   uint morton = (expanded.y << 2u) | (expanded.z << 1u) | expanded.x;

   return morton | x_top | z_top;
}

struct Vertex {
   vec3 position;
   uint encodedVertex;
   vec2 uv;
   uint blockID;
   uint textureID;
}; // pad to 32 bytes, should make loads better than 28

const uint MAX_VERTEX_COUNT = 33554432u;
const uint MAX_QUAD_COUNT = MAX_VERTEX_COUNT / 4u;

const uint INVALID_ID = 0xFFFFFFFFu;

const uint RADIX_BITS = 4u;
const uint RADIX = 1u << RADIX_BITS;
const uint WAVE_SIZE = 32u;
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
   uint textureEntries; // 100
   int lastTextureReloadCount; // 104
   uint textureReloadDelay; // 108
   uint sceneFrozen; // 112
   mat4 frozenProjInv; // 116
   mat4 frozenModelViewInv; // 180
   vec4 frozenLightPos; // 244
   uint frozenFirstPerson; // 260
   float autofocusDist; // 264
   vec4 frozenCameraPos; // 268
   } control;

const uint MAX_TEXTURES = 65536u;
const uint MAX_TEXTURE_DATA = 268435456u; // 1GiB of total data

struct TextureInfo {
   uint key;
   uint baseOffset;
   uint sizeX;
   uint sizeY;
};

#ifdef AS_VERTEX

layout(std430, binding = 0) restrict buffer VertexBuffer {
   uint count;
   Vertex vertices[];
};

uint getVertexWriteIndex() {
   uvec4 activeMask = subgroupBallot(true);
   uint activeThreads = subgroupBallotBitCount(activeMask);
   uint allocatedCount = (activeThreads + 3u) & ~0x3u; // round up to nearest multiple of 4, for triangle strips

   uint baseVertexId = INVALID_ID;
   if (subgroupElect()) {
      baseVertexId = atomicAdd(count, allocatedCount);
   }
   baseVertexId = subgroupBroadcastFirst(baseVertexId);

   uint lane = subgroupBallotExclusiveBitCount(activeMask);

   if (baseVertexId + allocatedCount > MAX_VERTEX_COUNT) return INVALID_ID;

   return baseVertexId + lane;
}

layout(std430, binding = 8) restrict buffer TextureInfosBuffer {
   uint textureDataOffset;
   TextureInfo textureMap[];
};

layout(std430, binding = 9) restrict buffer TextureDataBuffer {
   uint textureData[];
};

#else

struct Quad {
   Vertex v1;
   Vertex v2;
   Vertex v3;
   Vertex v4;
}; // 128 bytes

layout(std430, binding = 0) restrict readonly buffer QuadBuffer {
   uint count;
   Quad quads[];
};

layout(std430, binding = 8) restrict readonly buffer TextureInfosBuffer {
   uint textureDataOffset;
   TextureInfo textureMap[];
};

layout(std430, binding = 9) restrict readonly buffer TextureDataBuffer {
   uint textureData[];
};

#endif

uint floatToOrderedUint(float v) {
   int i = floatBitsToInt(v);
   // If positive: i >> 31 is 0x00000000. Mask becomes 0x80000000u.
   // If negative: i >> 31 is 0xFFFFFFFF. Mask becomes 0xFFFFFFFFu.
   uint mask = uint(i >> 31) | 0x80000000u;
   return uint(i) ^ mask;
}

float orderedUintToFloat(uint o) {
   // If o has MSB 1 (originally positive float): int(o) >> 31 is 0xFFFFFFFF. Bitwise NOT makes it 0. Mask becomes 0x80000000u.
   // If o has MSB 0 (originally negative float): int(o) >> 31 is 0x00000000. Bitwise NOT makes it 0xFFFFFFFF. Mask becomes 0xFFFFFFFFu.
   uint mask = (~uint(int(o) >> 31)) | 0x80000000u;
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
   uvec3 rawMax = uvec3(
         control.boundsMaxX,
         control.boundsMaxY,
         control.boundsMaxZ
      );

   return vec3(
      orderedUintToFloat(rawMax.x),
      orderedUintToFloat(rawMax.y),
      orderedUintToFloat(rawMax.z)
   );
}

vec3 getSceneMin() {
   uvec3 rawMin = uvec3(
         control.boundsMinX,
         control.boundsMinY,
         control.boundsMinZ
      );

   return vec3(
      orderedUintToFloat(rawMin.x),
      orderedUintToFloat(rawMin.y),
      orderedUintToFloat(rawMin.z)
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
