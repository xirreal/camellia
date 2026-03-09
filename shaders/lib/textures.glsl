#ifndef TEXTURES_INCLUDE_GUARD
#define TEXTURES_INCLUDE_GUARD

#define ENTITY_TEXTURES
//#define ENTITY_TEXTURES_DEBUG
//#define ENTITY_PBR

uint expandBits2D(uint v) {
   v &= 0xFFFFu;
   v = (v | (v << 8)) & 0x00FF00FFu;
   v = (v | (v << 4)) & 0x0F0F0F0Fu;
   v = (v | (v << 2)) & 0x33333333u;
   v = (v | (v << 1)) & 0x55555555u;
   return v;
}

uint morton2D(uint x, uint y) {
   return expandBits2D(x) | (expandBits2D(y) << 1);
}

uint compactBy1(uint x) {
   x &= 0x55555555u;
   x = (x ^ (x >> 1)) & 0x33333333u;
   x = (x ^ (x >> 2)) & 0x0F0F0F0Fu;
   x = (x ^ (x >> 4)) & 0x00FF00FFu;
   x = (x ^ (x >> 8)) & 0x0000FFFFu;
   return x;
}

void mortonDecode(uint m, out uint x, out uint y) {
   x = compactBy1(m);
   y = compactBy1(m >> 1);
}

uint nextPow2(uint v) {
   v--;
   v |= v >> 1;
   v |= v >> 2;
   v |= v >> 4;
   v |= v >> 8;
   v |= v >> 16;
   return v + 1;
}

// Compute the texel count (padded to pow2 square) for a given texture size.
uint texelCountForSize(ivec2 texSize) {
   uint paddedDim = nextPow2(uint(max(texSize.x, texSize.y)));
   return paddedDim * paddedDim;
}

vec4 sampleEntityTexture(uint textureID, vec2 uv) {
   uint slot = textureID - 1u;
   TextureInfo entry = textureMap[slot];

   uv = clamp(uv, vec2(0.0), vec2(1.0));
   ivec2 texel = clamp(
         ivec2(uv * vec2(float(entry.sizeX), float(entry.sizeY))),
         ivec2(0),
         ivec2(int(entry.sizeX) - 1, int(entry.sizeY) - 1)
      );

   uint idx = morton2D(uint(texel.x), uint(texel.y));
   return unpackUnorm4x8(textureData[entry.baseOffset + idx]);
}

#ifdef ENTITY_PBR

// Sample entity normal map. Stored at baseOffset + texelCount.
vec4 sampleEntityNormal(uint textureID, vec2 uv) {
   uint slot = textureID - 1u;
   TextureInfo entry = textureMap[slot];

   uint paddedDim = nextPow2(max(entry.sizeX, entry.sizeY));
   uint texelCount = paddedDim * paddedDim;

   uv = clamp(uv, vec2(0.0), vec2(1.0));
   ivec2 texel = clamp(
         ivec2(uv * vec2(float(entry.sizeX), float(entry.sizeY))),
         ivec2(0),
         ivec2(int(entry.sizeX) - 1, int(entry.sizeY) - 1)
      );

   uint idx = morton2D(uint(texel.x), uint(texel.y));
   return unpackUnorm4x8(textureData[entry.baseOffset + texelCount + idx]);
}

// Sample entity specular map. Stored at baseOffset + 2*texelCount.
vec4 sampleEntitySpecular(uint textureID, vec2 uv) {
   uint slot = textureID - 1u;
   TextureInfo entry = textureMap[slot];

   uint paddedDim = nextPow2(max(entry.sizeX, entry.sizeY));
   uint texelCount = paddedDim * paddedDim;

   uv = clamp(uv, vec2(0.0), vec2(1.0));
   ivec2 texel = clamp(
         ivec2(uv * vec2(float(entry.sizeX), float(entry.sizeY))),
         ivec2(0),
         ivec2(int(entry.sizeX) - 1, int(entry.sizeY) - 1)
      );

   uint idx = morton2D(uint(texel.x), uint(texel.y));
   return unpackUnorm4x8(textureData[entry.baseOffset + 2u * texelCount + idx]);
}

#endif

#ifdef AS_VERTEX

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

#endif
