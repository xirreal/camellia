#ifndef TEXTURES_WRITE_INCLUDE_GUARD
#define TEXTURES_WRITE_INCLUDE_GUARD

#define TEXTURE_INFOS_BUFFER_QUALIFIERS restrict coherent
#include "/lib/scene/textures-common.glsl"
#include "/lib/buffers/texture-infos.glsl"

#ifdef ENTITY_TEXTURES
layout(rgba8) uniform writeonly image2D entityAtlasImg;

uint reserveEntityTexels(uint count) {
   uint offset = atomicAdd(textureDataOffset, 0u);
   while (count <= MAX_TEXTURE_DATA - offset) {
      uint previous = atomicCompSwap(textureDataOffset, offset, offset + count);
      if (previous == offset) return offset;
      offset = previous;
   }
   return INVALID_ID;
}

uint textureMapInsert(uint textureId, ivec2 texSize, out uint baseOffset) {
   baseOffset = INVALID_ID;
   uint key = textureId + 1u;
   if (key == 0u || any(lessThanEqual(texSize, ivec2(0))) ||
       any(greaterThan(texSize, ivec2(16384)))) return ENTITY_TEXTURE_FALLBACK;
   uint slot = textureId % MAX_TEXTURES;
   // ponytail: at most 64 probes; use a stronger hash if collision clusters exhaust the probe budget.
   for (uint probe = 0u; probe < 64u; ++probe) {
      uint existing = textureMap[slot].key;
      if (existing == 0u) existing = atomicCompSwap(textureMap[slot].key, 0u, key);
      if (existing == key) return slot + 1u;
      if (existing == 0u) {
         uint count = uint(texSize.x) * uint(texSize.y);
#ifdef ENTITY_PBR
         count *= 3u;
#endif
         baseOffset = reserveEntityTexels(count);
         textureMap[slot].baseOffset = baseOffset;
         textureMap[slot].sizeX = uint(texSize.x);
         textureMap[slot].sizeY = uint(texSize.y);
         atomicAdd(control.textureEntries, 1u);
         // Geometry only stores the ID. Sampling starts in a later Iris pass,
         // after metadata and image copies from all shadow draws are complete.
         return slot + 1u;
      }
      slot = (slot + 1u) % MAX_TEXTURES;
   }
   return ENTITY_TEXTURE_FALLBACK;
}
#endif

uint captureEntityTexture(uint textureId, sampler2D albedo, sampler2D normals, sampler2D specular) {
#ifdef ENTITY_TEXTURES
   ivec2 size = textureSize(albedo, 0);
   uint id = ENTITY_TEXTURE_FALLBACK;
   uint baseOffset = INVALID_ID;
   if (subgroupElect()) id = textureMapInsert(textureId, size, baseOffset);
   id = subgroupBroadcastFirst(id);
   baseOffset = subgroupBroadcastFirst(baseOffset);
   if (baseOffset != INVALID_ID) {
      uvec4 activeMask = subgroupBallot(true);
      uint count = uint(size.x) * uint(size.y);
#ifdef ENTITY_PBR
      ivec2 normalSize = textureSize(normals, 0);
      ivec2 specularSize = textureSize(specular, 0);
#endif
      for (uint i = subgroupBallotExclusiveBitCount(activeMask); i < count; i += subgroupBallotBitCount(activeMask)) {
         ivec2 coord = ivec2(i % uint(size.x), i / uint(size.x));
         imageStore(entityAtlasImg, entityAtlasCoord(baseOffset + i), texelFetch(albedo, coord, 0));
#ifdef ENTITY_PBR
         imageStore(entityAtlasImg, entityAtlasCoord(baseOffset + count + i), texelFetch(normals, min(coord, normalSize - 1), 0));
         imageStore(entityAtlasImg, entityAtlasCoord(baseOffset + 2u * count + i), texelFetch(specular, min(coord, specularSize - 1), 0));
#endif
      }
   }
   return id;
#else
   return ENTITY_TEXTURE_FALLBACK;
#endif
}

#endif
