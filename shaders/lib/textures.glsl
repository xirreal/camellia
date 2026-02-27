#ifndef TEXTURES_INCLUDE_GUARD
#define TEXTURES_INCLUDE_GUARD

#define ENTITY_TEXTURES
//#define ENTITY_TEXTURES_DEBUG

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

#ifdef AS_VERTEX

uint textureMapInsert(uint textureId, ivec2 texSize, out bool isNew) {
   uint slot = textureId % MAX_TEXTURES;
   isNew = false;

   uint existing = atomicCompSwap(textureMap[slot].key, 0u, textureId + 1u);

   if (existing == 0u) {
      isNew = true;

      uint paddedDim = nextPow2(uint(max(texSize.x, texSize.y)));
      uint texelCount = paddedDim * paddedDim;
      uint baseOffset = atomicAdd(textureDataOffset, texelCount);

      if (baseOffset + texelCount > MAX_TEXTURE_DATA) {
         textureMap[slot].key = 0u;
         return INVALID_ID;
      }

      textureMap[slot].sizeX = uint(texSize.x);
      textureMap[slot].sizeY = uint(texSize.y);
      textureMap[slot].baseOffset = baseOffset;
      #ifdef ENTITY_TEXTURES_DEBUG
      atomicAdd(control.textureEntries, 1u);
      #endif
   }

   return slot;
}

void copyTexture(uint baseOffset, ivec2 texSize, sampler2D tex) {
   uvec4 activeMask = subgroupBallot(true);
   uint activeCount = subgroupBallotBitCount(activeMask);
   uint threadIdx = subgroupBallotExclusiveBitCount(activeMask);

   uint paddedDim = nextPow2(uint(max(texSize.x, texSize.y)));
   uint texelCount = paddedDim * paddedDim;

   for (uint i = threadIdx; i < texelCount; i += activeCount) {
      uint x, y;
      mortonDecode(i, x, y);

      if (x < uint(texSize.x) && y < uint(texSize.y)) {
         vec4 color = texelFetch(tex, ivec2(x, y), 0);
         textureData[baseOffset + i] = packUnorm4x8(color);
      }
   }
}

#endif

#endif
