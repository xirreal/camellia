#ifndef SCENE_BOUNDS_INCLUDE_GUARD
#define SCENE_BOUNDS_INCLUDE_GUARD

#include "/lib/scene/scene-read.glsl"

void updateSceneBounds(vec3 pos) {
   vec3 sMin = subgroupMin(pos);
   vec3 sMax = subgroupMax(pos);

   if (subgroupElect()) {
      uvec3 uMin = encodeBound(sMin);
      uvec3 uMax = encodeBound(sMax);

      atomicMin(control.boundsMinX, uMin.x);
      atomicMin(control.boundsMinY, uMin.y);
      atomicMin(control.boundsMinZ, uMin.z);

      atomicMax(control.boundsMaxX, uMax.x);
      atomicMax(control.boundsMaxY, uMax.y);
      atomicMax(control.boundsMaxZ, uMax.z);
   }
}

#endif
