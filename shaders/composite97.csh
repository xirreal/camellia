#version 460

#include "/lib/core/settings.glsl"
#include "/lib/core/storage.glsl"
#include "/lib/buffers/control.glsl"
#define QUAD_COUNT_BUFFER_QUALIFIERS restrict readonly
#include "/lib/buffers/quad-count.glsl"
#include "/lib/buffers/quad-geometry.glsl"
#include "/lib/bvh/hploc.glsl"

const ivec3 workGroups = ivec3(int((MAX_QUAD_COUNT + 63) / 64), 1, 1);
layout(local_size_x = 64) in;

bool hasNanInf(vec3 v) {
   return any(isnan(v)) || any(isinf(v));
}

float triangleAreaSq(vec3 a, vec3 b, vec3 c) {
   vec3 cr = cross(b - a, c - a);
   return dot(cr, cr);
}

void main() {
   uint gID = gl_GlobalInvocationID.x;
   uint numQuads = min(quadCount, uint(MAX_QUAD_COUNT));
   if (gID >= numQuads) return;

   vec3 p0, p1, p2, p3;
   unpackQuadGeometryPositions(quadGeometry[gID], p0, p1, p2, p3);

   if (hasNanInf(p0) || hasNanInf(p1) || hasNanInf(p2) || hasNanInf(p3)) {
      atomicAdd(control.quadErrNanInf, 1u);
   }

   vec3 qMin = min(min(p0, p1), min(p2, p3));
   vec3 qMax = max(max(p0, p1), max(p2, p3));
   vec3 extent = qMax - qMin;
   if (any(greaterThan(extent, vec3(VALIDATION_MAX_QUAD_EXTENT)))) {
      atomicAdd(control.quadErrExtent, 1u);
   }

   vec3 n1 = cross(p1 - p0, p2 - p0);
   vec3 n2 = cross(p2 - p0, p3 - p0);
   float len1 = length(n1);
   float len2 = length(n2);
   if (len1 > 1e-10 && len2 > 1e-10 && dot(n1 / len1, n2 / len2) < (1.0 - VALIDATION_COPLANAR_THRESHOLD)) {
      atomicAdd(control.quadErrCoplanar, 1u);
   }

   if (triangleAreaSq(p0, p1, p2) < VALIDATION_DEGEN_AREA_THRESHOLD ||
       triangleAreaSq(p0, p2, p3) < VALIDATION_DEGEN_AREA_THRESHOLD) {
      atomicAdd(control.quadErrDegenerate, 1u);
   }

   if (length(p1 - p0) < 1e-10 && length(p2 - p0) < 1e-10 && length(p3 - p0) < 1e-10) {
      atomicAdd(control.quadErrCollapsed, 1u);
   }
}
