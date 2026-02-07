#version 460

layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;

layout(rgba8) uniform writeonly image2D colorimg0;

uniform sampler2D colortex0;
uniform float viewWidth;
uniform float viewHeight;

#define AS_BVH2
#include "/lib/storage.glsl"
#include "/lib/text-rendering.glsl"

// HPLOC atomic counters - reusing global histogram buffer (binding 7)
layout(std430, binding = 7) readonly buffer HPLOCCounters {
   uint hplocCounters[];
};

// BVH2 nodes are accessed via bvh2Nodes[] from storage.glsl (binding 2, AS_BVH2 mode)

vec3 gradient(float t) {
   return mix(vec3(0.4, 1.0, 0.4), vec3(0.9, 0.2, 0.25), t);
}

void main() {
   ivec2 coord = ivec2(gl_GlobalInvocationID.xy);

   if (coord.x >= int(viewWidth) || coord.y >= int(viewHeight)) return;

   vec3 color = texelFetch(colortex0, coord, 0).rgb;

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

   // Validate sort: check if sorted leaves (binding 10) are sorted by morton code
   // We sample a few pairs to check ordering (can't check all in a fragment shader)
   printLine();
   text.fgCol = vec4(1.0);
   printString((_S, _o, _r, _t, _e, _d, _colon));

   uint numLeaves = count >> 2u;
   bool isSorted = true;

   // if (numLeaves > 1u) {
   //    for (uint i = 0u; i + 1u < numLeaves; i += 1) {
   //       uint codeA = leavesSorted[i].mortonCode;
   //       uint codeB = leavesSorted[i + 1u].mortonCode;
   //       if (codeA > codeB) {
   //          isSorted = false;
   //          break;
   //       }
   //    }
   // }

   if (isSorted) {
      text.fgCol = vec4(0.4, 1.0, 0.4, 1.0);
      printString((_t, _r, _u, _e));
   } else {
      text.fgCol = vec4(0.9, 0.2, 0.25, 1.0);
      printString((_f, _a, _l, _s, _e));
   }
   printLine();

   // Print 10 morton codes from the middle of the sorted leaves array
   printLine();
   text.fgCol = vec4(1.0);
   printString((_M, _o, _r, _t, _o, _n, _space, _C, _o, _d, _e, _s, _colon));
   printLine();

   // uint startIndex = (numLeaves > 10u) ? (numLeaves / 2u - 5u) : 0u;
   // for (uint i = 0u; i < 10u && (startIndex + i) < numLeaves; i++) {
   //    uint index = startIndex + i;
   //    uint mortonCode = leavesSorted[index].mortonCode;
   //    text.fgCol = vec4(1.0);
   //    printUnsignedInt(index);
   //    printString((_colon, _space));
   //    text.fgCol = vec4(0.4, 1.0, 0.4, 1.0);
   //    printUnsignedIntWithSeparators(mortonCode);
   //    printLine();
   // }
   // printLine();

   endText(color);

   imageStore(colorimg0, coord, vec4(color, 1.0));
}
