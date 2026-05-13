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

struct AABB {
   float minX;
   float minY;
   float minZ;
   float maxX;
   float maxY;
   float maxZ;
}; // 24 bytes

struct BVH2Node {
   vec3 c0Min;
   uint leftChild;
   vec3 c0Max;
   uint rightChild;
   vec3 c1Min;
   float _pad0;
   vec3 c1Max;
   float _pad1;
}; // 64 bytes

struct QuadPositions {
   vec4 p0p1x;    // p0.xyz, p1.x
   vec4 p1yzp2xy; // p1.yz, p2.xy
   vec4 p2zp3;    // p2.z, p3.xyz
}; // 48 bytes

void unpackQuadPositions(QuadPositions qp, out vec3 p0, out vec3 p1, out vec3 p2, out vec3 p3) {
   p0 = qp.p0p1x.xyz;
   p1 = vec3(qp.p0p1x.w, qp.p1yzp2xy.xy);
   p2 = vec3(qp.p1yzp2xy.zw, qp.p2zp3.x);
   p3 = qp.p2zp3.yzw;
}

AABB makeAABB(vec3 bMin, vec3 bMax) {
   return AABB(bMin.x, bMin.y, bMin.z, bMax.x, bMax.y, bMax.z);
}

vec3 aabbMin(AABB aabb) {
   return vec3(aabb.minX, aabb.minY, aabb.minZ);
}

vec3 aabbMax(AABB aabb) {
   return vec3(aabb.maxX, aabb.maxY, aabb.maxZ);
}

#define MAX_QUAD_COUNT 8388608 //[1048576 2097152 4194304 8388608 16777216 33554432]

const uint INVALID_ID = 0xFFFFFFFFu;

const uint RADIX_BITS = 8u;
const uint RADIX = 1u << RADIX_BITS;
const uint WAVE_SIZE = 32u;
#ifdef MC_GL_VENDOR_AMD
#define HPLOC_WG_SIZE 64
#else
#define HPLOC_WG_SIZE 32
#endif
const uint SORT_WG_SIZE = 256u;
const uint SORT_MAX_WORKGROUPS = (MAX_QUAD_COUNT + SORT_WG_SIZE - 1u) / SORT_WG_SIZE;
const uint SORT_RADIX_MASK = RADIX - 1u;
const uint HALF_RADIX = RADIX >> 1u;
const uint SORT_HALF_RADIX_MASK = HALF_RADIX - 1u;
const uint SORT_RADIX_PASSES = 32u / RADIX_BITS;
const uint SORT_KEYS_PER_THREAD = 15u;
const uint SORT_UPSWEEP_WG_SIZE = 128u;
const uint SORT_SCAN_WG_SIZE = 128u;
const uint SORT_DOWNSWEEP_WG_SIZE = 256u;
const uint SORT_PART_SIZE = SORT_KEYS_PER_THREAD * SORT_DOWNSWEEP_WG_SIZE;
const uint SORT_MAX_PARTITIONS = (MAX_QUAD_COUNT + SORT_PART_SIZE - 1u) / SORT_PART_SIZE;
const uint SORT_DOWNSWEEP_SMEM = 4096u;

const uint SORT_SCRATCH_KEYS = 0u;
const uint SORT_SCRATCH_VALS = MAX_QUAD_COUNT;
const uint SORT_SCRATCH_PASS_HIST = MAX_QUAD_COUNT * 2u;
const uint SORT_SCRATCH_GLOBAL_HIST = SORT_SCRATCH_PASS_HIST + RADIX * SORT_MAX_PARTITIONS;
const uint SORT_GLOBAL_HIST_SIZE = SORT_RADIX_PASSES * RADIX;
const uint SORT_GLOBAL_HIST_WORKGROUPS = (SORT_GLOBAL_HIST_SIZE + SORT_WG_SIZE - 1u) / SORT_WG_SIZE;

uint sortPrepareWorkgroupsForQuadEnd(uint quadEnd) {
   uint quadWorkgroups = (quadEnd + SORT_WG_SIZE - 1u) / SORT_WG_SIZE;
   return max(quadWorkgroups, SORT_GLOBAL_HIST_WORKGROUPS);
}

const uint MAX_TEXTURES = 65536u;
const uint MAX_TEXTURE_DATA = 268435456u; // 1GiB of total data

struct TextureInfo {
   uint key;
   uint baseOffset;
   uint sizeX;
   uint sizeY;
};

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

#endif
