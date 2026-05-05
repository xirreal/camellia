#ifndef QUAD_READ_INCLUDE_GUARD
#define QUAD_READ_INCLUDE_GUARD

#include "/lib/buffers/quad-data.glsl"

uint quadBlockID(uint q) {
   return quadData[q].encodedMaterial & 0x00FFFFFFu;
}

uint quadMaterial(uint q) {
   return quadData[q].encodedMaterial >> 24u;
}

float quadEmission(uint q) {
   return float(quadMaterial(q) & 0x0Fu);
}

bool quadAlphaTested(uint q) {
   return (quadMaterial(q) & 0x10u) != 0u;
}

bool quadTranslucent(uint q) {
   return (quadMaterial(q) & 0x20u) != 0u;
}

bool quadPlayerModel(uint q) {
   return (quadMaterial(q) & 0x40u) != 0u;
}

uint quadTextureID(uint q) {
   return quadData[q].textureID;
}

vec2 quadUV(uint q, uint i) {
   uint p = (i == 0u) ? quadData[q].uv0 :
      (i == 1u) ? quadData[q].uv1 :
      (i == 2u) ? quadData[q].uv2 : quadData[q].uv3;
   return unpackHalf2x16(p);
}

vec3 quadTint(uint q, uint i) {
   uint w = (i < 2u) ? quadData[q].tint01 : quadData[q].tint23;
   uint s = (i & 1u) * 16u;
   return unpackRGB565((w >> s) & 0xFFFFu);
}

#endif
