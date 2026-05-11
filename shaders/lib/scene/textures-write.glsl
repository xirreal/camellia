#ifndef TEXTURES_WRITE_INCLUDE_GUARD
#define TEXTURES_WRITE_INCLUDE_GUARD

#ifndef TEXTURE_INFOS_BUFFER_QUALIFIERS
#define TEXTURE_INFOS_BUFFER_QUALIFIERS restrict
#endif
#ifndef TEXTURE_DATA_BUFFER_QUALIFIERS
#define TEXTURE_DATA_BUFFER_QUALIFIERS restrict writeonly
#endif

#include "/lib/scene/textures-common.glsl"
#include "/lib/buffers/texture-infos.glsl"
#include "/lib/buffers/texture-data.glsl"

uint textureMapInsert(uint textureId, ivec2 texSize, out bool isNew) {
   uint slot = textureId % MAX_TEXTURES;
   isNew = false;

   // Use a sentinel to lock the slot while we write metadata.
   // 0 = empty, INVALID_ID = being initialized, anything else = valid key.
   uint existing = atomicCompSwap(textureMap[slot].key, 0u, INVALID_ID);

   if (existing == 0u) {
      uint paddedDim = nextPow2(uint(max(texSize.x, texSize.y)));
      uint texelCount = paddedDim * paddedDim;
      // Allocate 3x when PBR is enabled: color + normal + specular
      #ifdef ENTITY_PBR
      uint totalAlloc = texelCount * 3u;
      #else
      uint totalAlloc = texelCount;
      #endif
      uint baseOffset = atomicAdd(textureDataOffset, totalAlloc);

      if (baseOffset + totalAlloc > MAX_TEXTURE_DATA) {
         atomicAdd(textureDataOffset, -totalAlloc);
         textureMap[slot].key = 0u; // release the slot
         return INVALID_ID;
      }

      // Write metadata before publishing the key
      textureMap[slot].sizeX = uint(texSize.x);
      textureMap[slot].sizeY = uint(texSize.y);
      textureMap[slot].baseOffset = baseOffset;

      // Ensure metadata writes are visible before we publish the key
      memoryBarrierBuffer();

      textureMap[slot].key = textureId + 1u;
      isNew = true;

      #ifdef ENTITY_TEXTURES_DEBUG
      atomicAdd(control.textureEntries, 1u);
      #endif
   } else if (existing == INVALID_ID) {
      // Another invocation is currently initializing this slot; treat as invalid for now.
      return INVALID_ID;
   }

   return slot;
}

void copyTexture(uint baseOffset, sampler2D albedoSampler, ivec2 albedoSize) {
   uvec4 activeMask = subgroupBallot(true);
   uint activeCount = subgroupBallotBitCount(activeMask);
   uint threadIdx = subgroupBallotExclusiveBitCount(activeMask);

   uint texelCount = texelCountForSize(albedoSize);

   for (uint i = threadIdx; i < texelCount; i += activeCount) {
      uint x, y;
      mortonDecode(i, x, y);

      if (x < uint(albedoSize.x) && y < uint(albedoSize.y)) {
         vec4 color = texelFetch(albedoSampler, ivec2(x, y), 0);
         textureData[baseOffset + i] = packUnorm4x8(color);
      }
   }
}

#ifdef ENTITY_PBR
// Copy color, normal, and specular textures into the SSBO.
// Layout: [color texels] [normal texels] [specular texels], each block is texelCount uints.
// Normal/specular samplers may be smaller (e.g. 1x1 default) so coords are clamped per-texture.
void copyTextureWithPBR(uint baseOffset, sampler2D albedoSampler, sampler2D normalsSampler, sampler2D specularSampler, ivec2 albedoSize, ivec2 normalsSize, ivec2 specularSize) {
   uvec4 activeMask = subgroupBallot(true);
   uint activeCount = subgroupBallotBitCount(activeMask);
   uint threadIdx = subgroupBallotExclusiveBitCount(activeMask);

   uint texelCount = texelCountForSize(albedoSize);

   for (uint i = threadIdx; i < texelCount; i += activeCount) {
      uint x, y;
      mortonDecode(i, x, y);

      if (x < uint(albedoSize.x) && y < uint(albedoSize.y)) {
         ivec2 coord = ivec2(x, y);

         vec4 color = texelFetch(albedoSampler, coord, 0);
         textureData[baseOffset + i] = packUnorm4x8(color);

         ivec2 nCoord = min(coord, normalsSize - 1);
         vec4 normal = texelFetch(normalsSampler, nCoord, 0);
         textureData[baseOffset + texelCount + i] = packUnorm4x8(normal);

         ivec2 sCoord = min(coord, specularSize - 1);
         vec4 spec = texelFetch(specularSampler, sCoord, 0);
         textureData[baseOffset + 2u * texelCount + i] = packUnorm4x8(spec);
      }
   }
}
#endif

#endif
