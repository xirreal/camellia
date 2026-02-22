#ifndef TEXTURES_INCLUDE_GUARD
#define TEXTURES_INCLUDE_GUARD

#define ENTITY_TEXTURES
//#define ENTITY_TEXTURES_DEBUG

uint pcg_hash(uint v) {
   uint state = v * 747796405u + 2891336453u;
   uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
   return (word >> 22u) ^ word;
}

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

uint computeTextureHash(sampler2D tex) {
   ivec2 size = textureSize(tex, 0);
   vec2 invSize = 1.0 / vec2(size);
   float inset = 1.5;

   vec2 lo = invSize * inset;
   vec2 hi = 1.0 - invSize * inset;
   vec2 mid = vec2(0.5);

   uint s0 = packUnorm4x8(textureLod(tex, vec2(lo.x, lo.y), 0.0));
   uint s1 = packUnorm4x8(textureLod(tex, vec2(mid.x, lo.y), 0.0));
   uint s2 = packUnorm4x8(textureLod(tex, vec2(hi.x, lo.y), 0.0));
   uint s3 = packUnorm4x8(textureLod(tex, vec2(lo.x, mid.y), 0.0));
   uint s4 = packUnorm4x8(textureLod(tex, vec2(mid.x, mid.y), 0.0));
   uint s5 = packUnorm4x8(textureLod(tex, vec2(hi.x, mid.y), 0.0));
   uint s6 = packUnorm4x8(textureLod(tex, vec2(lo.x, hi.y), 0.0));
   uint s7 = packUnorm4x8(textureLod(tex, vec2(mid.x, hi.y), 0.0));
   uint s8 = packUnorm4x8(textureLod(tex, vec2(hi.x, hi.y), 0.0));

   uint hash = 2166136261u;
   uint[11] data = uint[](uint(size.x), uint(size.y), s0, s1, s2, s3, s4, s5, s6, s7, s8);

   #pragma unroll
   for (int i = 0; i < 11; i++) {
      hash ^= data[i];
      hash *= 16777619u;
   }

   return max(pcg_hash(hash), 1u);
}

uint textureMapInsert(uint hash, ivec2 texSize, out bool isNew) {
   isNew = false;

   for (uint probe = 0u; probe < 8u; probe++) {
      uint slot = (hash + probe) & (MAX_TEXTURES - 1u);

      uint existing = textureMap[slot].key;

      if (existing == hash) {
         return slot;
      }

      if (existing != 0u) {
         #ifdef ENTITY_TEXTURES_DEBUG
         atomicAdd(control.textureCollisions, 1u);
         #endif
         continue;
      }

      existing = atomicCompSwap(textureMap[slot].key, 0u, hash);

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
         return slot;
      }

      if (existing == hash) {
         return slot;
      }

      #ifdef ENTITY_TEXTURES_DEBUG
      atomicAdd(control.textureCollisions, 1u);
      #endif
   }

   return INVALID_ID;
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
