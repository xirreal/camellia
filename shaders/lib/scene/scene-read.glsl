#ifndef SCENE_READ_INCLUDE_GUARD
#define SCENE_READ_INCLUDE_GUARD

#include "/lib/buffers/control.glsl"

vec3 getSceneMax() {
   uvec3 rawMax = uvec3(
         control.boundsMaxX,
         control.boundsMaxY,
         control.boundsMaxZ
      );

   return vec3(
      orderedUintToFloat(rawMax.x),
      orderedUintToFloat(rawMax.y),
      orderedUintToFloat(rawMax.z)
   );
}

vec3 getSceneMin() {
   uvec3 rawMin = uvec3(
         control.boundsMinX,
         control.boundsMinY,
         control.boundsMinZ
      );

   return vec3(
      orderedUintToFloat(rawMin.x),
      orderedUintToFloat(rawMin.y),
      orderedUintToFloat(rawMin.z)
   );
}

#endif
