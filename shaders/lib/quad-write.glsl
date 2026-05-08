#ifndef QUAD_WRITE_INCLUDE_GUARD
#define QUAD_WRITE_INCLUDE_GUARD

#ifndef CONTROL_BUFFER_QUALIFIERS
#define CONTROL_BUFFER_QUALIFIERS restrict
#endif
#ifndef QUAD_DATA_BUFFER_QUALIFIERS
#define QUAD_DATA_BUFFER_QUALIFIERS restrict
#endif

#include "/lib/buffers/control.glsl"
#include "/lib/buffers/quad-data.glsl"
#include "/lib/buffers/quad-pos-write.glsl"
#include "/lib/scene-bounds.glsl"

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

#endif
