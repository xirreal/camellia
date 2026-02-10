#version 460

layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;

layout(rgba8) uniform writeonly image2D colorimg0;

uniform sampler2D colortex0;
uniform sampler2D colortex1;
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

   int halfWidth = int(viewWidth) / 2;
   vec3 color;

   if (coord.x < halfWidth) {
      color = texelFetch(colortex0, coord, 0).rgb;
   } else {
      vec4 rtData = texelFetch(colortex1, coord, 0);
      if (rtData.a > 0.0) {
         color = rtData.rgb;
      } else {
         vec2 uv = vec2(coord) / vec2(viewWidth, viewHeight);
         color = vec3(uv.x * 0.05, uv.y * 0.05, 0.08);
      }
   }

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
   uint sortErrors = control.data[CTRL_SORT_ERRORS];

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
   uint pairErrors = control.data[CTRL_PAIR_ERRORS];
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

   // BVH2 node count
   printLine();
   text.fgCol = vec4(1.0);
   printString((_B, _V, _H, _2, _colon));
   text.fgCol = vec4(0.4, 1.0, 0.4, 1.0);
   printUnsignedIntWithSeparators(control.data[CTRL_BVH2_NODE_COUNT]);
   text.fgCol = vec4(1.0);
   printString((_slash));
   if (numLeaves > 0u) {
      printUnsignedIntWithSeparators(numLeaves - 1u);
   } else {
      printUnsignedInt(0u);
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

   endText(color);

   beginText(ivec2(coord * 0.25), ivec2(2, 10));
   text.bgCol = vec4(0.0, 0.0, 0.0, 0.7);

   printString((_G, _b, _f, _u, _f, _f, _e, _r));

   endText(color);

   beginText(ivec2(coord * 0.25), ivec2(viewWidth * 0.25 * 0.5 + 3, 10));
   text.bgCol = vec4(0.0, 0.0, 0.0, 0.7);

   printString((_R, _T));

   endText(color);

   // Divider line
   if (abs(coord.x - halfWidth) <= 1) {
      color = vec3(1.0);
   }

   imageStore(colorimg0, coord, vec4(color, 1.0));
}
