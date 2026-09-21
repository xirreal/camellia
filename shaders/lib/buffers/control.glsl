#ifndef CONTROL_BUFFER_INCLUDE_GUARD
#define CONTROL_BUFFER_INCLUDE_GUARD

#ifndef CONTROL_BUFFER_QUALIFIERS
#define CONTROL_BUFFER_QUALIFIERS restrict
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
} control;

#endif
