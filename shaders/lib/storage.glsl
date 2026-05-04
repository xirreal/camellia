#ifndef STORAGE_INCLUDE_GUARD
#define STORAGE_INCLUDE_GUARD

uniform float far;

#ifdef MC_GL_VENDOR_NVIDIA
#extension GL_NV_gpu_shader5 : require
#endif
#extension GL_KHR_shader_subgroup_basic : require
#extension GL_KHR_shader_subgroup_arithmetic : require
#extension GL_KHR_shader_subgroup_ballot : require
#extension GL_KHR_shader_subgroup_clustered : require
#extension GL_KHR_shader_subgroup_vote : require
#extension GL_KHR_shader_subgroup_shuffle : require
#extension GL_KHR_shader_subgroup_shuffle_relative : require

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
   uint z_top = (i.z & 0x0400u) << 21u;

   uint morton = (expanded.y << 2u) | (expanded.z << 1u) | expanded.x;

   return morton | x_top | z_top;
}

uint packRGB565(vec3 c) {
   uvec3 u = uvec3(round(clamp(c, 0.0, 1.0) * vec3(31.0, 63.0, 31.0)));
   return u.r | (u.g << 5u) | (u.b << 11u);
}

vec3 unpackRGB565(uint p) {
   return vec3(
      float(p & 31u) / 31.0,
      float((p >> 5u) & 63u) / 63.0,
      float((p >> 11u) & 31u) / 31.0
   );
}

struct QuadData {
   uint encodedMaterial; // bits 0-23: blockID, bits 24-27: emission, bit 28: alphaTested, bit 29: translucent, bit 30: player
   uint textureID; // 32 bit but only 24 bits used, index into texture map buffer
   uint tint01; // low 16 = v0 RGB565, high 16 = v1 RGB565
   uint tint23; // low 16 = v2 RGB565, high 16 = v3 RGB565
   uint uv0; // packHalf2x16(v0.uv)
   uint uv1; // packHalf2x16(v1.uv)
   uint uv2; // packHalf2x16(v2.uv)
   uint uv3; // packHalf2x16(v3.uv)
}; // 32 bytes

#define MAX_QUAD_COUNT 8388608 //[1048576 2097152 4194304 8388608 16777216 33554432]

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

layout(std430, binding = 1) coherent buffer ControlBuffer {
   uint sortDispatchX; // 0
   uint sortDispatchY; // 4
   uint sortDispatchZ; // 8
   uint hplocDispatchX; // 12
   uint hplocDispatchY; // 16
   uint hplocDispatchZ; // 20
   uint prepareDispatchX; // 24
   uint prepareDispatchY; // 28
   uint prepareDispatchZ; // 32

   uint boundsMinX;
   uint boundsMinY;
   uint boundsMinZ;
   uint boundsMaxX;
   uint boundsMaxY;
   uint boundsMaxZ;
   uint numBVH2Nodes;
   uint sortTotal;
   uint sortErrors;
   uint pairErrors;
   uint buildError;
   uint rootClusterID;
   uint quadErrNanInf;
   uint quadErrExtent;
   uint quadErrCoplanar;
   uint quadErrDegenerate;
   uint quadErrCollapsed;
   uint realCount1;
   uint realCount2;
   uint textureEntries;
   int lastTextureReloadCount;
   uint textureReloadDelay;
   uint sceneFrozen;
   uint frozenFirstPerson;
   float autofocusDist;

   mat4 frozenProjInv;
   mat4 frozenModelViewInv;
   vec4 frozenLightPos;
   vec4 frozenCameraPos;
   vec4 frozenSunPos;
} control;

const uint MAX_TEXTURES = 65536u;
const uint MAX_TEXTURE_DATA = 268435456u; // 1GiB of total data

struct TextureInfo {
   uint key;
   uint baseOffset;
   uint sizeX;
   uint sizeY;
};

#ifdef QUAD_WRITE

layout(std430, binding = 0) restrict buffer QuadDataBuffer {
   uint quadCount;
   QuadData quadData[];
};

layout(std430, binding = 10) restrict writeonly buffer QuadPosBuffer {
   float quadPosData[];
};

void getQuadWriteSlot(out uint quadID, out uint slot) {
   uvec4 activeMask = subgroupBallot(true);
   uint activeThreads = subgroupBallotBitCount(activeMask);
   uint quadAlloc = (activeThreads + 3u) >> 2u;

   uint baseQuad = INVALID_ID;
   if (subgroupElect()) {
      baseQuad = atomicAdd(quadCount, quadAlloc);
   }
   baseQuad = subgroupBroadcastFirst(baseQuad);

   uint lane = subgroupBallotExclusiveBitCount(activeMask);
   quadID = baseQuad + (lane >> 2u);
   slot = lane & 3u;

   if (quadID >= MAX_QUAD_COUNT) quadID = INVALID_ID;
}

void writeQuadVertex(uint quadID, uint slot, vec3 pos, vec2 uv, vec3 tintColor) {
   uint base = quadID * 12u + slot * 3u;
   quadPosData[base + 0u] = pos.x;
   quadPosData[base + 1u] = pos.y;
   quadPosData[base + 2u] = pos.z;

   uint packedUV = packHalf2x16(uv);
   if (slot == 0u) quadData[quadID].uv0 = packedUV;
   else if (slot == 1u) quadData[quadID].uv1 = packedUV;
   else if (slot == 2u) quadData[quadID].uv2 = packedUV;
   else quadData[quadID].uv3 = packedUV;

   uint rgb565 = packRGB565(tintColor);
   if (slot < 2u) {
      uint shift = slot * 16u;
      atomicOr(quadData[quadID].tint01, rgb565 << shift);
   } else {
      uint shift = (slot - 2u) * 16u;
      atomicOr(quadData[quadID].tint23, rgb565 << shift);
   }
}

void writeQuadMaterial(uint quadID, uint blockID, uint textureID, float emission, bool alphaTested, bool translucent, bool isPlayer) {
   uint mat = (uint(clamp(emission, 0.0, 15.0))) |
         (alphaTested ? 0x10u : 0u) |
         (translucent ? 0x20u : 0u) |
         (isPlayer ? 0x40u : 0u);
   quadData[quadID].encodedMaterial = (blockID & 0x00FFFFFFu) | (mat << 24u);
   quadData[quadID].textureID = textureID;
   quadData[quadID].tint01 = 0u;
   quadData[quadID].tint23 = 0u;
}

layout(std430, binding = 8) restrict buffer TextureInfosBuffer {
   uint textureDataOffset;
   TextureInfo textureMap[];
};

layout(std430, binding = 9) restrict buffer TextureDataBuffer {
   uint textureData[];
};

#else

layout(std430, binding = 0) restrict readonly buffer QuadDataBuffer {
   uint quadCount;
   QuadData quadData[];
};

layout(std430, binding = 8) restrict readonly buffer TextureInfosBuffer {
   uint textureDataOffset;
   TextureInfo textureMap[];
};

layout(std430, binding = 9) restrict readonly buffer TextureDataBuffer {
   uint textureData[];
};

#endif

uint quadBlockID(uint q) {
   return quadData[q].encodedMaterial & 0x00FFFFFFu;
}
uint quadMaterial(uint q) {
   return quadData[q].encodedMaterial >> 24u;
}
float quadEmission(uint q) {
   return float(quadMaterial(q) & 0x0Fu);
}
bool quadAlphaTested(uint q) {
   return (quadMaterial(q) & 0x10u) != 0u;
}
bool quadTranslucent(uint q) {
   return (quadMaterial(q) & 0x20u) != 0u;
}
bool quadPlayerModel(uint q) {
   return (quadMaterial(q) & 0x40u) != 0u;
}
uint quadTextureID(uint q) {
   return quadData[q].textureID;
}

vec2 quadUV(uint q, uint i) {
   uint p = (i == 0u) ? quadData[q].uv0 :
      (i == 1u) ? quadData[q].uv1 :
      (i == 2u) ? quadData[q].uv2 : quadData[q].uv3;
   return unpackHalf2x16(p);
}

vec3 quadTint(uint q, uint i) {
   uint w = (i < 2u) ? quadData[q].tint01 : quadData[q].tint23;
   uint s = (i & 1u) * 16u;
   return unpackRGB565((w >> s) & 0xFFFFu);
}

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
