#ifndef TEXTURES_WRITE_INCLUDE_GUARD
#define TEXTURES_WRITE_INCLUDE_GUARD

#define TEXTURE_INFOS_BUFFER_QUALIFIERS restrict coherent
#include "/lib/scene/textures-common.glsl"
#include "/lib/buffers/texture-infos.glsl"

#ifdef ENTITY_TEXTURES
layout(rgba8) uniform writeonly image2D entityAtlasImg;
#ifdef ENTITY_PBR
uniform int frameCounter;
layout(rgba8) uniform writeonly image2D entityNormalAtlasImg;
layout(rgba8) uniform writeonly image2D entitySpecularAtlasImg;
#endif

uint reserveEntityTexels(uint count) {
   uint offset = atomicAdd(textureDataOffset, 0u);
   while (count <= MAX_TEXTURE_DATA - offset) {
      uint previous = atomicCompSwap(textureDataOffset, offset, offset + count);
      if (previous == offset) return offset;
      offset = previous;
   }
   return INVALID_ID;
}

uint textureMapInsert(uint textureId, sampler2D albedo, out ivec2 texSize, out uint baseOffset, out bool copyAlbedo) {
   texSize = ivec2(0);
   baseOffset = INVALID_ID;
   copyAlbedo = false;
   uint key = textureId + 1u;
   uint slot = textureId % MAX_TEXTURES;
   // ponytail: at most 64 probes; use a stronger hash if collision clusters exhaust the probe budget.
   for (uint probe = 0u; probe < 64u; ++probe) {
      uint existing = textureMap[slot].key;
      if (existing == 0u) existing = atomicCompSwap(textureMap[slot].key, 0u, key);
      if (existing == key) {
#ifdef ENTITY_PBR
         // Iris supplies default PBR maps on first use and loads the real maps
         // next frame. Claim exactly one later copy, reusing the albedo allocation.
         uint pendingFrame = textureMap[slot].pbrPendingFrame;
         if (pendingFrame != INVALID_ID && pendingFrame != uint(frameCounter) &&
             atomicCompSwap(textureMap[slot].pbrPendingFrame, pendingFrame, INVALID_ID) == pendingFrame) {
            texSize = ivec2(textureMap[slot].sizeX, textureMap[slot].sizeY);
            baseOffset = textureMap[slot].baseOffset;
         }
#endif
         return slot + 1u;
      }
      if (existing == 0u) {
         texSize = textureSize(albedo, 0);
         if (all(greaterThan(texSize, ivec2(0))) && all(lessThanEqual(texSize, ivec2(16384)))) {
            baseOffset = reserveEntityTexels(uint(texSize.x) * uint(texSize.y));
         }
         textureMap[slot].baseOffset = baseOffset;
         textureMap[slot].sizeX = uint(texSize.x);
         textureMap[slot].sizeY = uint(texSize.y);
#ifdef ENTITY_PBR
         if (baseOffset != INVALID_ID) textureMap[slot].pbrPendingFrame = uint(frameCounter);
#endif
         copyAlbedo = true;
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
#ifndef ENTITY_TEXTURES
   // Keep the sampler active so Iris still reports IDs when copying is disabled.
   if (any(lessThanEqual(textureSize(albedo, 0), ivec2(0)))) return ENTITY_TEXTURE_FALLBACK;
#endif
   if (textureId == 0u || textureId == INVALID_ID) return ENTITY_TEXTURE_FALLBACK;
   // Terrain records its binding before entity draws. ID zero already samples
   // the permanently bound block albedo/normal/specular atlases in every reader.
   if (textureId == control.blockAtlasTextureId) return 0u;
#ifdef ENTITY_TEXTURES
   ivec2 size = ivec2(0);
   uint id = ENTITY_TEXTURE_FALLBACK;
   uint baseOffset = INVALID_ID;
   bool copyAlbedo = false;
   if (subgroupElect()) id = textureMapInsert(textureId, albedo, size, baseOffset, copyAlbedo);
   id = subgroupBroadcastFirst(id);
   baseOffset = subgroupBroadcastFirst(baseOffset);
   copyAlbedo = subgroupBroadcastFirst(copyAlbedo);
   if (baseOffset != INVALID_ID) {
      size = subgroupBroadcastFirst(size);
      uvec4 activeMask = subgroupBallot(true);
      uint count = uint(size.x) * uint(size.y);
      uint stride = subgroupBallotBitCount(activeMask);
#ifdef ENTITY_PBR
      ivec2 normalSize = textureSize(normals, 0);
      ivec2 specularSize = textureSize(specular, 0);
#endif
      for (uint i = subgroupBallotExclusiveBitCount(activeMask); i < count; i += stride) {
         ivec2 coord = ivec2(i % uint(size.x), i / uint(size.x));
         ivec2 atlasCoord = entityAtlasCoord(baseOffset + i);
         if (copyAlbedo) imageStore(entityAtlasImg, atlasCoord, texelFetch(albedo, coord, 0));
#ifdef ENTITY_PBR
         if (!copyAlbedo) {
            // Resample at texel centers: PBR maps can differ from the albedo size.
            vec2 uv = (vec2(coord) + 0.5) / vec2(size);
            vec4 normalValue = all(greaterThan(normalSize, ivec2(0)))
               ? texelFetch(normals, ivec2(uv * vec2(normalSize)), 0) : vec4(0.5, 0.5, 1.0, 1.0);
            vec4 specularValue = all(greaterThan(specularSize, ivec2(0)))
               ? texelFetch(specular, ivec2(uv * vec2(specularSize)), 0) : vec4(0.0, 0.04, 0.0, 0.0);
            imageStore(entityNormalAtlasImg, atlasCoord, normalValue);
            imageStore(entitySpecularAtlasImg, atlasCoord, specularValue);
         }
#endif
      }
   }
   return id;
#else
   return ENTITY_TEXTURE_FALLBACK;
#endif
}

#endif
