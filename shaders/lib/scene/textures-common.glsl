#ifndef TEXTURES_COMMON_INCLUDE_GUARD
#define TEXTURES_COMMON_INCLUDE_GUARD

#include "/lib/core/settings.glsl"

#define ENTITY_TEXTURES
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

uint texelCountForSize(ivec2 texSize) {
   uint paddedDim = nextPow2(uint(max(texSize.x, texSize.y)));
   return paddedDim * paddedDim;
}

#endif
