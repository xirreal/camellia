#ifndef NORMAL_MAP_INCLUDE_GUARD
#define NORMAL_MAP_INCLUDE_GUARD

vec3 decodeMinecraftNormalMap(vec4 normalSample) {
   vec2 xy = normalSample.rg * 2.0 - 1.0;
   // Minecraft resource-pack normal maps use DirectX-style tangent-space Y.
   xy.y = -xy.y;
   return normalize(vec3(xy, sqrt(max(1.0 - dot(xy, xy), 0.00001))));
}

#endif
