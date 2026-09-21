#ifndef TEXTURES_COMMON_INCLUDE_GUARD
#define TEXTURES_COMMON_INCLUDE_GUARD

#include "/lib/core/settings.glsl"

const uint ENTITY_TEXTURE_FALLBACK = 65535u;
const uint ENTITY_COPY_MAX_STEPS = 4096u;

bool validEntityTextureRange(uvec2 size, uint offset) {
   if (any(equal(size, uvec2(0u))) || any(greaterThan(size, uvec2(16384u)))) return false;
   return offset < MAX_TEXTURE_DATA && size.x * size.y <= MAX_TEXTURE_DATA - offset;
}

ivec2 entityCopyViewport(ivec2 viewport) {
   return clamp(viewport, ivec2(0), ivec2(shadowMapResolution));
}

ivec2 entityAtlasCoord(uint address) {
   return ivec2(address & 16383u, address >> 14u);
}

#endif
