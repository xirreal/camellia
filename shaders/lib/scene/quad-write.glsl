#ifndef QUAD_WRITE_INCLUDE_GUARD
#define QUAD_WRITE_INCLUDE_GUARD

#ifndef CONTROL_BUFFER_QUALIFIERS
#define CONTROL_BUFFER_QUALIFIERS restrict
#endif
#ifndef QUAD_GEOMETRY_BUFFER_QUALIFIERS
#define QUAD_GEOMETRY_BUFFER_QUALIFIERS restrict writeonly
#endif
#ifndef QUAD_ATTRIBUTES_BUFFER_QUALIFIERS
#define QUAD_ATTRIBUTES_BUFFER_QUALIFIERS restrict writeonly
#endif

#include "/lib/buffers/control.glsl"
#include "/lib/buffers/quad-count.glsl"
#include "/lib/buffers/quad-geometry.glsl"
#include "/lib/buffers/quad-attributes.glsl"

void getConditionalQuadWriteSlot(bool enabled, out uint quadID, out uint slot) {
   uvec4 activeMask = subgroupBallot(enabled);
   uint activeThreads = subgroupBallotBitCount(activeMask);
   uint quadAlloc = (activeThreads + 3u) >> 2u;

   uint baseQuad = INVALID_ID;
   if (subgroupElect() && quadAlloc != 0u) {
      baseQuad = atomicAdd(quadCount, quadAlloc);
   }
   baseQuad = subgroupBroadcastFirst(baseQuad);

   uint lane = subgroupBallotExclusiveBitCount(activeMask);
   quadID = baseQuad + (lane >> 2u);
   slot = lane & 3u;

   if (!enabled || quadID >= MAX_QUAD_COUNT) quadID = INVALID_ID;
}

void getQuadWriteSlot(out uint quadID, out uint slot) {
   getConditionalQuadWriteSlot(true, quadID, slot);
}

void writeQuadRecords(
   uint quadID, vec3 p0, vec3 p1, vec3 p2, vec3 p3,
   vec2 uv0, vec2 uv1, vec2 uv2, vec3 tintColor,
   uint blockID, uint textureID, float emission,
   bool alphaTested, bool translucent, bool isPlayer
) {
   uint mat = (uint(clamp(emission, 0.0, 15.0))) |
         (alphaTested ? 0x10u : 0u) |
         (translucent ? 0x20u : 0u) |
         (isPlayer ? 0x40u : 0u);
   uint materialTexture = (blockID & 0xFFu) | ((mat & 0x7Fu) << 8u) |
      ((textureID & 0xFFFFu) << 15u) | (all(equal(p2, p3)) ? 0x80000000u : 0u);

   vec3 d1 = p1 - p0;
   vec3 d2 = p2 - p0;
   vec3 d3 = p3 - p0;
   uint base = quadID * 4u;
   quadGeometryWords[base] = floatBitsToUint(p0.xy);
   quadGeometryWords[base + 1u] = uvec2(floatBitsToUint(p0.z), packHalf2x16(d1.xy));
   quadGeometryWords[base + 2u] = uvec2(packHalf2x16(vec2(d1.z, d2.x)), packHalf2x16(d2.yz));
   quadGeometryWords[base + 3u] = uvec2(packHalf2x16(d3.xy), packHalf2x16(vec2(d3.z, 0.0)) | (packRGB565(tintColor) << 16u));
   quadAttributeWords[base] = materialTexture;
   quadAttributeWords[base + 1u] = packHalf2x16(uv0);
   quadAttributeWords[base + 2u] = packHalf2x16(uv1);
   quadAttributeWords[base + 3u] = packHalf2x16(uv2);
}

void writeQuad(
   uint quadID, uint slot, vec3 pos, vec2 uv, vec3 tintColor,
   uint blockID, uint textureID, float emission,
   bool alphaTested, bool translucent, bool isPlayer
) {
   uint lane = gl_SubgroupInvocationID;
   uint first = lane - slot;
   vec3 p0 = subgroupShuffle(pos, first);
   vec3 delta = pos - p0;
   float d1z = subgroupShuffle(delta.z, min(first + 1u, gl_SubgroupSize - 1u));
   vec3 p2 = subgroupShuffle(pos, min(first + 2u, gl_SubgroupSize - 1u));
   uint tint = subgroupShuffle(packRGB565(tintColor), first);
   uint mat = uint(clamp(emission, 0.0, 15.0)) | (alphaTested ? 0x10u : 0u) |
      (translucent ? 0x20u : 0u) | (isPlayer ? 0x40u : 0u);
   uint material = (blockID & 0xffu) | (mat << 8u) | ((textureID & 0xffffu) << 15u);
   material = subgroupShuffle(material, first);
   if (quadID == INVALID_ID) return;

   uvec2 words;
   if (slot == 0u) words = floatBitsToUint(p0.xy);
   else if (slot == 1u) words = uvec2(floatBitsToUint(p0.z), packHalf2x16(delta.xy));
   else if (slot == 2u) words = uvec2(packHalf2x16(vec2(d1z, delta.x)), packHalf2x16(delta.yz));
   else words = uvec2(packHalf2x16(delta.xy), packHalf2x16(vec2(delta.z, 0.0)) | (tint << 16u));
   quadGeometryWords[quadID * 4u + slot] = words;
   quadAttributeWords[quadID * 4u + ((slot + 1u) & 3u)] = slot == 3u
      ? material | (all(equal(p2, pos)) ? 0x80000000u : 0u) : packHalf2x16(uv);
}

#endif
