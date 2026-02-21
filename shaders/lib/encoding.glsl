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

uint encodeVertexData(vec3 color, float emission) {
   return packUnorm4x8(vec4(color, emission));
}

vec4 decodeVertexData(uint packedVertexData) {
   return unpackUnorm4x8(packedVertexData);
}

#endif
