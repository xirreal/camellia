#version 460

#include "/lib/core/settings.glsl"

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba8) uniform writeonly image2D colorimg0;

uniform sampler2D colortex0;
uniform float viewWidth;
uniform float viewHeight;
uniform int textureReloadCount;

#include "/lib/core/storage.glsl"
#define CONTROL_BUFFER_QUALIFIERS restrict readonly
#include "/lib/buffers/control.glsl"
#include "/lib/scene/scene-read.glsl"
#define QUAD_COUNT_BUFFER_QUALIFIERS restrict readonly
#include "/lib/buffers/quad-count.glsl"
#include "/lib/buffers/morton.glsl"
#include "/lib/buffers/texture-infos.glsl"
#include "/lib/bvh/hploc.glsl"
#include "/lib/ui/text-rendering.glsl"

vec3 gradient(float t) {
   return mix(vec3(0.4, 1.0, 0.4), vec3(0.9, 0.2, 0.25), t);
}

#ifdef ENABLE_SUBGROUP_VALIDATION
void printSubgroupResult(uint passed, uint total) {
   text.fgCol = total == 0u ? vec4(0.6, 0.6, 0.6, 1.0)
      : vec4(gradient(passed == total ? 0.0 : 1.0), 1.0);
   printUnsignedIntWithSeparators(passed);
   printString((_slash));
   printUnsignedIntWithSeparators(total);
   printLine();
}
#endif

void main() {
   #ifdef ENABLE_DEBUG_OVERLAY
   #endif
   ivec2 coord = ivec2(gl_GlobalInvocationID.xy);

   if (coord.x >= int(viewWidth) || coord.y >= int(viewHeight)) return;

   vec3 color = texture(colortex0, vec2(coord + 0.5) / vec2(viewWidth, viewHeight)).rgb;

   beginText(ivec2(coord * 0.25), ivec2(2, int(viewHeight * 0.25) - 1));
   text.bgCol = vec4(0.0, 0.0, 0.0, 0.7);

   uint numQuads = quadCount;
   float fullness = float(numQuads) / float(MAX_QUAD_COUNT);

   text.fgCol = vec4(1.0);
   printString((_Q, _u, _a, _d, _s, _colon));
   text.fgCol = vec4(gradient(fullness), 1.0);
   printUnsignedIntWithSeparators(numQuads);
   printString((_slash));
   printUnsignedIntWithSeparators(uint(MAX_QUAD_COUNT));
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

   #ifdef ENTITY_TEXTURES_DEBUG
   printLine();
   float texFullness = float(control.textureEntries) / float(MAX_TEXTURES);

   text.fgCol = vec4(1.0);
   printString((_T, _e, _x, _t, _u, _r, _e, _s, _colon));
   text.fgCol = vec4(gradient(texFullness), 1.0);
   printUnsignedIntWithSeparators(control.textureEntries);
   printString((_slash));
   printUnsignedIntWithSeparators(MAX_TEXTURES);
   printLine();

   text.fgCol = vec4(1.0);
   printBar(texFullness, 300, vec3(0.4, 1.0, 0.4), vec3(0.9, 0.2, 0.25));
   printLine();

   text.fgCol = vec4(1.0);
   printString((_T, _e, _x, _space, _D, _a, _t, _a, _colon));
   float dataFullness = float(textureDataOffset) / float(MAX_TEXTURE_DATA);
   text.fgCol = vec4(gradient(dataFullness), 1.0);
   printUnsignedIntWithSeparators(textureDataOffset);
   printString((_slash));
   printUnsignedIntWithSeparators(MAX_TEXTURE_DATA);
   printLine();

   text.fgCol = vec4(1.0);
   printBar(dataFullness, 300, vec3(0.4, 1.0, 0.4), vec3(0.9, 0.2, 0.25));
   printLine();

   text.fgCol = vec4(1.0);
   printString((_R, _e, _l, _o, _a, _d, _s, _colon));
   text.fgCol = vec4(0.4, 1.0, 0.4, 1.0);
   printUnsignedIntWithSeparators(textureReloadCount);
   printLine();
   #endif

   #ifdef ENABLE_SORT_VALIDATION
   printLine();
   text.fgCol = vec4(1.0);
   printString((_S, _o, _r, _t, _e, _d, _colon));

   uint numLeaves = quadCount;
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
   #endif

   #ifdef ENABLE_QUAD_VALIDATION
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

   printLine();
   text.fgCol = vec4(1.0);
   printString((_Q, _u, _a, _d, _space, _V, _a, _l, _i, _d, _colon));
   printLine();

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
   #endif

   endText(color);

   #ifdef ENABLE_SUBGROUP_VALIDATION
   // Keep capture diagnostics visible even when sort/geometry diagnostics are on.
   beginText(ivec2(coord * 0.25), ivec2(max(2, int(viewWidth * 0.25) - 204), int(viewHeight * 0.25) - 1));
   text.bgCol = vec4(0.0, 0.0, 0.0, 0.7);
   uint selected = 0u, aligned = 0u, enabled = 0u, groups = 0u, operations = 0u, capacity = 0u;
   uint writers = 0u, sources = 0u, data = 0u, triangleWriters = 0u;
   for (uint path = 0u; path < control.captureDebugPaths; ++path) {
      selected += control.captureSubgroups[path].selected;
      aligned += control.captureSubgroups[path].aligned;
      groups += control.captureSubgroups[path].groups;
      operations += control.captureSubgroups[path].operations;
      capacity += control.captureSubgroups[path].capacity;
      writers += control.captureSubgroups[path].writeTests;
      sources += control.captureSubgroups[path].writeSources;
      data += control.captureSubgroups[path].writeData;
      if (path != 9u) enabled += control.captureSubgroups[path].enabled;
      else triangleWriters = control.captureSubgroups[path].writeTests;
   }
   text.fgCol = vec4(1.0);
   printString((_C, _a, _p, _t, _u, _r, _e, _space, _c, _h, _e, _c, _k, _s));
   printLine();
   printString((_C, _o, _m, _p, _u, _t, _e, _space, _s, _i, _z, _e, _colon));
   printUnsignedInt(control.captureComputeSize);
   printLine();
   printString((_F, _u, _l, _l, _colon));
   printSubgroupResult(control.quadSubgroupFull, control.quadSubgroupTests);
   text.fgCol = vec4(1.0);
   printString((_O, _r, _d, _e, _r, _colon));
   printSubgroupResult(control.quadSubgroupConsecutive, control.quadSubgroupTests);
   text.fgCol = vec4(1.0);
   printString((_A, _l, _i, _g, _n, _colon));
   printSubgroupResult(aligned, control.quadSubgroupTests);
   text.fgCol = vec4(1.0);
   printString((_S, _e, _l, _e, _c, _t, _colon));
   printSubgroupResult(selected, control.quadSubgroupTests);
   text.fgCol = vec4(1.0);
   printString((_A, _l, _l, _o, _c, _a, _t, _o, _r, _colon));
   printSubgroupResult(control.quadSubgroupAllocator, enabled);
   text.fgCol = vec4(1.0);
   printString((_S, _l, _o, _t, _s, _colon));
   printSubgroupResult(control.quadSubgroupSlots, enabled);
   text.fgCol = vec4(1.0);
   printString((_O, _p, _s, _colon));
   printSubgroupResult(groups - operations, groups);
   text.fgCol = vec4(1.0);
   printString((_W, _r, _i, _t, _e, _space, _s, _r, _c, _colon));
   printSubgroupResult(sources, writers - triangleWriters);
   text.fgCol = vec4(1.0);
   printString((_W, _r, _i, _t, _e, _space, _d, _a, _t, _a, _colon));
   printSubgroupResult(data, writers);
   text.fgCol = vec4(1.0);
   printString((_D, _r, _o, _p, _p, _e, _d, _colon));
   text.fgCol = vec4(gradient(capacity == 0u ? 0.0 : 1.0), 1.0);
   printUnsignedIntWithSeparators(capacity);
   printLine();
   printLine();
   text.fgCol = vec4(1.0);
   printString((_P, _a, _t, _h, _space, _G, _r, _o, _u, _p, _s, _space, _F, _l, _a, _g, _s));
   printLine();
   for (uint path = 0u; path < control.captureDebugPaths; ++path) {
      uint count = control.captureSubgroups[path].groups;
      uint flags = control.captureSubgroups[path].firstFailure;
      text.fgCol = count == 0u ? vec4(0.6, 0.6, 0.6, 1.0) : vec4(gradient(flags == 0u ? 0.0 : 1.0), 1.0);
      printUnsignedInt(path);
      printString((_space));
      printUnsignedIntWithSeparators(count);
      printString((_space));
      printUnsignedInt(flags);
      printLine();
   }
   endText(color);
   #endif

   imageStore(colorimg0, coord, vec4(color, 1.0));
}
