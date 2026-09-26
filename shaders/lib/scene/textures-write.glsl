#ifndef TEXTURES_WRITE_INCLUDE_GUARD
#define TEXTURES_WRITE_INCLUDE_GUARD

#define TEXTURE_INFOS_BUFFER_QUALIFIERS restrict coherent
#include "/lib/scene/textures-common.glsl"
#include "/lib/buffers/texture-infos.glsl"

#ifdef ENTITY_TEXTURES
#ifdef ENTITY_PBR
uniform int frameCounter;
#endif

uint reserveEntityTexels(uint count) {
   uint offset = atomicAdd(textureDataOffset, 0u);
   // ponytail: cap CAS retries at 64; contention falls back instead of spinning forever.
   for (uint attempt = 0u; attempt < 64u; ++attempt) {
      if (offset > MAX_TEXTURE_DATA || count > MAX_TEXTURE_DATA - offset) return INVALID_ID;
      uint previous = atomicCompSwap(textureDataOffset, offset, offset + count);
      if (previous == offset) return offset;
      offset = previous;
   }
   return INVALID_ID;
}

uint textureMapInsert(uint textureId, sampler2D albedo, uint maxCopyTexels, out ivec2 texSize, out uint baseOffset, out bool copyAlbedo) {
   texSize = ivec2(0);
   baseOffset = INVALID_ID;
   copyAlbedo = false;
   uint key = textureId + 1u;
   uint slot = textureId % MAX_TEXTURES;
   // todo: investigate if this is necessary? maybe diff hash would be better
   for (uint probe = 0u; probe < 64u; ++probe) {
      uint existing = atomicAdd(textureMap[slot].key, 0u);
      if (existing == 0u) {
         if (maxCopyTexels == 0u) return ENTITY_TEXTURE_FALLBACK;
         existing = atomicCompSwap(textureMap[slot].key, 0u, key);
      }
      if (existing == key) {
#ifdef ENTITY_PBR
         // 26.2+ uploads entity pbr a frame late to work around some bugs
         // so we need to do the copy a frame later
         uint pendingFrame = atomicAdd(textureMap[slot].pbrPendingFrame, 0u);
         if (pendingFrame != INVALID_ID && pendingFrame != uint(frameCounter)) {
            uvec2 size = uvec2(textureMap[slot].sizeX, textureMap[slot].sizeY);
            uint offset = textureMap[slot].baseOffset;
            if (validEntityTextureRange(size, offset) && size.x * size.y <= maxCopyTexels &&
                atomicCompSwap(textureMap[slot].pbrPendingFrame, pendingFrame, INVALID_ID) == pendingFrame) {
               texSize = ivec2(size);
               baseOffset = offset;
            }
         }
#endif
         return slot + 1u;
      }
      if (existing == 0u) {
         texSize = textureSize(albedo, 0);
         if (all(greaterThan(texSize, ivec2(0))) && all(lessThanEqual(texSize, ivec2(16384))) &&
             uint(texSize.x) * uint(texSize.y) <= maxCopyTexels) {
            baseOffset = reserveEntityTexels(uint(texSize.x) * uint(texSize.y));
         }
         textureMap[slot].baseOffset = baseOffset;
         textureMap[slot].sizeX = uint(texSize.x);
         textureMap[slot].sizeY = uint(texSize.y);
#ifdef ENTITY_PBR
         memoryBarrierBuffer();
         if (baseOffset != INVALID_ID) atomicExchange(textureMap[slot].pbrPendingFrame, uint(frameCounter));
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

uint captureEntityTexture(uint textureId, sampler2D albedo, ivec2 viewport, out uvec4 copyJob, out vec4 copyPosition) {
   copyJob = uvec4(0u);
   copyPosition = vec4(2.0, 2.0, 2.0, 1.0);
#ifndef ENTITY_TEXTURES
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
   #ifdef QUAD_WRITE_RECORDS_ONLY
   // A geometry invocation owns an entire triangle and emits its own copy.
   bool completeQuad = true;
   #else
   uvec4 activeMask = subgroupBallot(true);
   uint lane = gl_SubgroupInvocationID;
   uint firstLane = lane & ~3u;
   uint firstVertex = subgroupShuffle(uint(gl_VertexID), firstLane);
   // workaround sodium bug where sometimes not all lanes are active in a quad
   // causing the copy to be incomplete
   bool completeQuad = firstLane + 3u < gl_SubgroupSize;
   for (uint i = 1u; i < 4u; ++i) {
      uint quadLane = min(firstLane + i, gl_SubgroupSize - 1u);
      completeQuad = completeQuad && subgroupBallotBitExtract(activeMask, quadLane) &&
         subgroupShuffle(uint(gl_VertexID), quadLane) == firstVertex + i;
   }
   #endif
   ivec2 copyViewport = entityCopyViewport(viewport);
   uint maxCopyTexels = completeQuad ? uint(copyViewport.x * copyViewport.y) * ENTITY_COPY_MAX_STEPS : 0u;
   if (subgroupElect()) id = textureMapInsert(textureId, albedo, maxCopyTexels, size, baseOffset, copyAlbedo);
   id = subgroupBroadcastFirst(id);
   baseOffset = subgroupBroadcastFirst(baseOffset);
   copyAlbedo = subgroupBroadcastFirst(copyAlbedo);
   if (baseOffset != INVALID_ID && completeQuad) {
      size = subgroupBroadcastFirst(size);
      #ifdef QUAD_WRITE_RECORDS_ONLY
      if (subgroupElect()) copyJob = uvec4(baseOffset, uvec2(size), copyAlbedo ? 1u : 2u);
      #else
      copyJob = uvec4(baseOffset, uvec2(size), copyAlbedo ? 1u : 2u);
      uint corner = lane - firstLane;
      copyPosition = vec4(corner == 1u ? 3.0 : -1.0, corner >= 2u ? 3.0 : -1.0, 0.0, 1.0);
      #endif
   }
   return id;
#else
   return ENTITY_TEXTURE_FALLBACK;
#endif
}

#endif
