#version 460

//#define ENABLE_DEBUG_OVERLAY

layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;

layout(rgba8) uniform writeonly image2D colorimg0;

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform float viewWidth;
uniform float viewHeight;

#include "/lib/storage.glsl"
#include "/lib/hploc.glsl"
#include "/lib/text-rendering.glsl"

vec3 gradient(float t) {
   return mix(vec3(0.4, 1.0, 0.4), vec3(0.9, 0.2, 0.25), t);
}

void main() {
   ivec2 coord = ivec2(gl_GlobalInvocationID.xy);

   if (coord.x >= int(viewWidth) || coord.y >= int(viewHeight)) return;

   vec3 color = texture(colortex1, vec2(coord + 0.5) / vec2(viewWidth, viewHeight)).rgb;

   #ifdef ENABLE_DEBUG_OVERLAY

   beginText(ivec2(coord * 0.25), ivec2(2, int(viewHeight * 0.25) - 1));
   text.bgCol = vec4(0.0, 0.0, 0.0, 0.7);

   uint numQuads = count / 4u;
   float fullness = float(count) / float(MAX_VERTEX_COUNT);

   text.fgCol = vec4(1.0);
   printString((_V, _e, _r, _t, _i, _c, _e, _s, _colon));
   text.fgCol = vec4(gradient(fullness), 1.0);
   printUnsignedIntWithSeparators(count);
   printString((_slash));
   printUnsignedIntWithSeparators(MAX_VERTEX_COUNT);
   printLine();

   text.fgCol = vec4(1.0);
   printString((_Q, _u, _a, _d, _s, _colon));
   text.fgCol = vec4(gradient(fullness), 1.0);
   printUnsignedIntWithSeparators(numQuads);
   printString((_slash));
   printUnsignedIntWithSeparators(MAX_QUAD_COUNT);
   printLine();

   text.fgCol = vec4(1.0);
   printString((_U, _s, _a, _g, _e, _colon));
   text.fgCol = vec4(gradient(fullness), 1.0);
   printFloat(fullness * 100.0);
   printString((_percent));
   printLine();

   text.fgCol = vec4(1.0);
   printBar(fullness, 300, vec3(0.4, 1.0, 0.4), vec3(0.9, 0.2, 0.25));
   printLine();

   printString((_M, _i, _n, _colon, _opprn));
   printVec3(getSceneMin());
   printString((_clprn));
   printLine();

   printString((_M, _a, _x, _colon, _opprn));
   printVec3(getSceneMax());
   printString((_clprn));
   printLine();

   // Sort validation
   printLine();
   text.fgCol = vec4(1.0);
   printString((_S, _o, _r, _t, _e, _d, _colon));

   uint numLeaves = count >> 2u;
   uint sortErrors = control.sortErrors;

   if (sortErrors == 0u) {
      text.fgCol = vec4(0.4, 1.0, 0.4, 1.0);
      printString((_t, _r, _u, _e));
   } else {
      text.fgCol = vec4(0.9, 0.2, 0.25, 1.0);
      printString((_f, _a, _l, _s, _e));
      printString((_space, _opprn));
      printUnsignedInt(sortErrors);
      printString((_clprn));
   }
   printLine();

   text.fgCol = vec4(1.0);
   printString((_P, _a, _i, _r, _s, _colon));
   uint pairErrors = control.pairErrors;
   if (pairErrors == 0u) {
      text.fgCol = vec4(0.4, 1.0, 0.4, 1.0);
      printString((_t, _r, _u, _e));
   } else {
      text.fgCol = vec4(0.9, 0.2, 0.25, 1.0);
      printString((_f, _a, _l, _s, _e));
      printString((_space, _opprn));
      printUnsignedInt(pairErrors);
      printString((_clprn));
   }
   printLine();

   // Morton codes sample
   printLine();
   text.fgCol = vec4(1.0);
   printString((_M, _o, _r, _t, _o, _n, _space, _C, _o, _d, _e, _s, _colon));
   printLine();

   uint startIndex = (numLeaves > 10u) ? (numLeaves / 2u - 5u) : 0u;
   for (uint i = 0u; i < 10u && (startIndex + i) < numLeaves; i++) {
      uint index = startIndex + i;
      uint mortonCode = mortonCodes[index];
      text.fgCol = vec4(1.0);
      printUnsignedInt(index);
      printString((_colon, _space));
      text.fgCol = vec4(0.4, 1.0, 0.4, 1.0);
      printUnsignedIntWithSeparators(mortonCode);
      printLine();
   }
   printLine();

   // Build error
   printLine();
   text.fgCol = vec4(1.0);
   printString((_B, _u, _i, _l, _d, _space, _E, _r, _r, _o, _r, _s, _colon));
   printLine();

   if (control.buildError == ERROR_OUT_OF_BOUNDS) {
      text.fgCol = vec4(0.9, 0.2, 0.25, 1.0);
      printString((_O, _u, _t, _space, _o, _f, _space, _b, _o, _u, _n, _d, _s));
   } else if (control.buildError == ERROR_TIMEOUT) {
      text.fgCol = vec4(0.9, 0.6, 0.1, 1.0);
      printString((_T, _i, _m, _e, _o, _u, _t));
   } else {
      text.fgCol = vec4(0.4, 1.0, 0.4, 1.0);
      printString((_n, _o, _n, _e));
   }
   printLine();

   // BVH root
   printLine();
   text.fgCol = vec4(1.0);
   printString((_R, _o, _o, _t, _colon));
   if (control.rootClusterID == INVALID_ID) {
      text.fgCol = vec4(0.9, 0.2, 0.25, 1.0);
      printString((_n, _o, _n, _e));
   } else {
      text.fgCol = vec4(0.4, 1.0, 0.4, 1.0);
      printUnsignedIntWithSeparators(control.rootClusterID);
   }
   printLine();

   text.fgCol = vec4(1.0);
   printString((_B, _V, _H, _space, _N, _o, _d, _e, _s, _colon));
   text.fgCol = vec4(0.4, 1.0, 0.4, 1.0);
   printUnsignedIntWithSeparators(control.numBVH2Nodes);
   printLine();

   // Quad validation
   printLine();
   text.fgCol = vec4(1.0);
   printString((_Q, _u, _a, _d, _space, _V, _a, _l, _i, _d, _colon));
   printLine();

   uint totalQuadErr = control.quadErrNanInf + control.quadErrExtent
         + control.quadErrCoplanar + control.quadErrDegenerate
         + control.quadErrCollapsed;

   text.fgCol = vec4(1.0);
   printString((_space, _N, _a, _N, _colon));
   text.fgCol = (control.quadErrNanInf == 0u)
      ? vec4(0.4, 1.0, 0.4, 1.0) : vec4(0.9, 0.2, 0.25, 1.0);
   printUnsignedIntWithSeparators(control.quadErrNanInf);
   printLine();

   text.fgCol = vec4(1.0);
   printString((_space, _E, _x, _t, _colon));
   text.fgCol = (control.quadErrExtent == 0u)
      ? vec4(0.4, 1.0, 0.4, 1.0) : vec4(0.9, 0.2, 0.25, 1.0);
   printUnsignedIntWithSeparators(control.quadErrExtent);
   printLine();

   text.fgCol = vec4(1.0);
   printString((_space, _C, _o, _p, _colon));
   text.fgCol = (control.quadErrCoplanar == 0u)
      ? vec4(0.4, 1.0, 0.4, 1.0) : vec4(0.9, 0.2, 0.25, 1.0);
   printUnsignedIntWithSeparators(control.quadErrCoplanar);
   printLine();

   text.fgCol = vec4(1.0);
   printString((_space, _D, _e, _g, _colon));
   text.fgCol = (control.quadErrDegenerate == 0u)
      ? vec4(0.4, 1.0, 0.4, 1.0) : vec4(0.9, 0.2, 0.25, 1.0);
   printUnsignedIntWithSeparators(control.quadErrDegenerate);
   printLine();

   text.fgCol = vec4(1.0);
   printString((_space, _C, _l, _p, _colon));
   text.fgCol = (control.quadErrCollapsed == 0u)
      ? vec4(0.4, 1.0, 0.4, 1.0) : vec4(0.9, 0.2, 0.25, 1.0);
   printUnsignedIntWithSeparators(control.quadErrCollapsed);
   printLine();

   endText(color);

   #endif

   imageStore(colorimg0, coord, vec4(color, 1.0));
}
