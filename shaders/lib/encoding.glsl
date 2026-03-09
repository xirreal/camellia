#ifndef ENCODING_INCLUDE_GUARD
#define ENCODING_INCLUDE_GUARD

vec2 snz(vec2 v) {
   return vec2((v.x >= 0.0) ? 1.0 : -1.0, (v.y >= 0.0) ? 1.0 : -1.0);
}

uint encodeNormal(vec3 n) {
   float l1 = abs(n.x) + abs(n.y) + abs(n.z);
   vec2 p = n.xy * (1.0 / l1);

   if (n.z < 0.0) {
      p = (1.0 - abs(p.yx)) * snz(p);
   }

   return packSnorm2x16(p);
}

vec3 decodeNormal(uint packedNormal) {
   vec2 p = unpackSnorm2x16(packedNormal);
   vec3 n = vec3(p.x, p.y, 1.0 - abs(p.x) - abs(p.y));

   float t = max(-n.z, 0.0);
   n.x += (n.x >= 0.0 ? -t : t);
   n.y += (n.y >= 0.0 ? -t : t);

   return normalize(n);
}

// Emission byte layout: bits 0-3 = emission (0-15), bit 4 = alpha-tested flag, bit 5 = translucent flag, bit 6 = player model flag
uint encodeVertexData(vec3 color, float emission, bool alphaTested, bool translucent, bool isPlayer) {
    uint rgb = packUnorm4x8(vec4(color, 0.0)) & 0x00FFFFFFu;
    uint emissionBits = uint(clamp(emission, 0.0, 15.0));
    uint alphaFlag = alphaTested ? 0x10u : 0u;
    uint translucentFlag = translucent ? 0x20u : 0u;
    uint playerFlag = isPlayer ? 0x40u : 0u;
    return rgb | ((emissionBits | alphaFlag | translucentFlag | playerFlag) << 24u);
}

uint encodeVertexData(vec3 color, float emission, bool alphaTested, bool translucent) {
    return encodeVertexData(color, emission, alphaTested, translucent, false);
}

uint encodeVertexData(vec3 color, float emission, bool alphaTested) {
    return encodeVertexData(color, emission, alphaTested, false, false);
}

vec4 decodeVertexData(uint encodedData) {
   vec4 v = unpackUnorm4x8(encodedData);
   v.a = float((encodedData >> 24u) & 0xFu) / 15.0;
   return v;
}

bool isAlphaTested(uint encodedData) {
   return ((encodedData >> 28u) & 1u) != 0u;
}

bool isTranslucent(uint encodedData) {
    return ((encodedData >> 29u) & 1u) != 0u;
}

bool isPlayerModel(uint encodedData) {
    return ((encodedData >> 30u) & 1u) != 0u;
}

#endif
