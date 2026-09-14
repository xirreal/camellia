#ifndef QUAD_READ_INCLUDE_GUARD
#define QUAD_READ_INCLUDE_GUARD

#include "/lib/buffers/quad-attributes.glsl"

uint quadBlockID(uint q) {
   return quadAttributes[q].materialTexture & 0xFFu;
}

bool quadPlayerModel(uint q) {
   return (quadAttributes[q].materialTexture & 0x4000u) != 0u;
}

#endif
