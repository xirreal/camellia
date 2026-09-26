#ifndef CONTROL_BUFFER_INCLUDE_GUARD
#define CONTROL_BUFFER_INCLUDE_GUARD

#ifndef CONTROL_BUFFER_QUALIFIERS
#define CONTROL_BUFFER_QUALIFIERS restrict
#endif

#ifdef ENABLE_SUBGROUP_VALIDATION
// 192 bytes per capture path. Layout and failure bits: docs/capture-debug.md.
struct CaptureSubgroupDebug {
   uint groups;
   uint sizeMask;
   uint tests;
   uint full;
   uint selected;
   uint ordered;
   uint aligned;
   uint allocated;
   uint slots;
   uint capacity;
   uint operations;
   uint writeTests;
   uint writeSources;
   uint writeData;
   uint enabled;
   uint firstFailure;
   uvec4 exampleInfo;
   uvec4 exampleLive;
   uvec4 exampleEnabled;
   uvec4 exampleVertices;
   uvec4 exampleQuadIDs;
   uvec4 exampleSlots;
   uvec4 exampleInstances;
   uvec4 exampleContext;
};
const uint CAPTURE_DEBUG_PATHS = 10u;
#endif

layout(std430, binding = 1) CONTROL_BUFFER_QUALIFIERS buffer ControlBuffer {
   uint sortDispatchX; // 0
   uint sortDispatchY; // 4
   uint sortDispatchZ; // 8
   uint hplocDispatchX; // 12
   uint hplocDispatchY; // 16
   uint hplocDispatchZ; // 20
   uint prepareDispatchX; // 24
   uint prepareDispatchY; // 28
   uint prepareDispatchZ; // 32

   uint boundsMinX;
   uint boundsMinY;
   uint boundsMinZ;
   uint boundsMaxX;
   uint boundsMaxY;
   uint boundsMaxZ;
   uint numBVH2Nodes;
   uint sortTotal;
   uint sortErrors;
   uint pairErrors;
   uint rootClusterID;
   uint quadErrNanInf;
   uint quadErrExtent;
   uint quadErrCoplanar;
   uint quadErrDegenerate;
   uint quadErrCollapsed;
   uint textureEntries;
   int lastTextureReloadCount;
   uint textureReloadDelay;
   uint sceneFrozen;
   float autofocusDist;

   mat4 frozenProjInv;
   mat4 frozenModelViewInv;
   vec4 frozenLightPos;
   vec4 frozenCameraPos;
   vec4 frozenSunPos;
   uint wideDispatchX; // 304
   uint wideDispatchY;
   uint wideDispatchZ;
   uint wideWorkgroups;
   uint wideTaskCount;
   uint wideNodeCount;
   coherent uint blockAtlasTextureId;
   uint quadSubgroupTests; // 332
   uint quadSubgroupFull;
   uint quadSubgroupConsecutive;
   uint quadSubgroupAllocator;
   uint quadSubgroupSlots;
   vec4 frozenCloudWeather; // 352: world age, wetness, biome temperature/humidity
   vec4 frozenCloudSky; // 368: world day, lightning, snow/sandstorm weights
#ifdef ENABLE_SUBGROUP_VALIDATION
   uint captureDebugVersion; // 384
   uint captureDebugFrame;
   uint captureComputeSize;
   uint captureDebugPaths;
   CaptureSubgroupDebug captureSubgroups[]; // 400; 10 * 192 bytes
#endif
} control;

#endif
