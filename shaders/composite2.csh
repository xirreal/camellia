#version 460

const ivec3 workGroups = ivec3(131072, 1, 1);

#include "/lib/storage.glsl"
#include "/lib/hploc.glsl"

layout(local_size_x = 64) in;

const float MAX_QUAD_EXTENT = 64.0; // max world-space span on any axis
const float COPLANAR_THRESHOLD = 0.15; // max normal deviation (dot < 1-thresh)
const float DEGEN_AREA_THRESHOLD = 1e-8; // minimum triangle area squared

bool hasNanInf(vec3 v) {
   return any(isnan(v)) || any(isinf(v));
}

float triangleAreaSq(vec3 a, vec3 b, vec3 c) {
   vec3 cr = cross(b - a, c - a);
   return dot(cr, cr);
}

void main() {
   uint gID = gl_GlobalInvocationID.x;
   uint numQuads = min(count >> 2u, MAX_QUAD_COUNT);

   if (gID >= numQuads) return;

   Quad q = quads[gID];
   vec3 p0 = q.v1.position;
   vec3 p1 = q.v2.position;
   vec3 p2 = q.v3.position;
   vec3 p3 = q.v4.position;

   // vertex nan/inf checks
   if (hasNanInf(p0) || hasNanInf(p1) || hasNanInf(p2) || hasNanInf(p3)) {
      atomicAdd(control.quadErrNanInf, 1u);
   }

   // quad extent sanity check
   vec3 qMin = min(min(p0, p1), min(p2, p3));
   vec3 qMax = max(max(p0, p1), max(p2, p3));
   vec3 extent = qMax - qMin;
   if (extent.x > MAX_QUAD_EXTENT || extent.y > MAX_QUAD_EXTENT || extent.z > MAX_QUAD_EXTENT) {
      atomicAdd(control.quadErrExtent, 1u);
   }

   // coplanar quad (should fail on fluids)
   vec3 n1 = cross(p1 - p0, p2 - p0);
   vec3 n2 = cross(p2 - p0, p3 - p0);
   float len1 = length(n1);
   float len2 = length(n2);
   if (len1 > 1e-10 && len2 > 1e-10) {
      n1 /= len1;
      n2 /= len2;
      float coplanarity = dot(n1, n2);
      if (coplanarity < (1.0 - COPLANAR_THRESHOLD)) {
         atomicAdd(control.quadErrCoplanar, 1u);
      }
   }

   // degenerate quad (why do i get a few of these?)
   float area1sq = triangleAreaSq(p0, p1, p2);
   float area2sq = triangleAreaSq(p0, p2, p3);
   if (area1sq < DEGEN_AREA_THRESHOLD || area2sq < DEGEN_AREA_THRESHOLD) {
      atomicAdd(control.quadErrDegenerate, 1u);
   }

   // collapsed quad
   float d01 = length(p1 - p0);
   float d02 = length(p2 - p0);
   float d03 = length(p3 - p0);
   if (d01 < 1e-10 && d02 < 1e-10 && d03 < 1e-10) {
      atomicAdd(control.quadErrCollapsed, 1u);
   }
}
