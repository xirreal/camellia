#ifndef TEXTURES_COMMON_INCLUDE_GUARD
#define TEXTURES_COMMON_INCLUDE_GUARD

#include "/lib/core/settings.glsl"

const uint ENTITY_TEXTURE_FALLBACK = 65535u;

// Texels are packed without square padding; rectangles may cross image rows.
ivec2 entityAtlasCoord(uint address) {
   return ivec2(address & 16383u, address >> 14u);
}

#endif
