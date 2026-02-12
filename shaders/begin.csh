#version 460 compatibility

#define AS_VERTEX
#include "/lib/storage.glsl"

const ivec3 workGroups = ivec3(1, 1, 1);

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

void main() {
   count = 0u;

   control.boundsMinX = 0xFFFFFFFFu;
   control.boundsMinY = 0xFFFFFFFFu;
   control.boundsMinZ = 0xFFFFFFFFu;
   control.boundsMaxX = 0u;
   control.boundsMaxY = 0u;
   control.boundsMaxZ = 0u;

   control.numBVH2Nodes = 0u;

   control.sortTotal = 0u;
   control.sortErrors = 0u;
   control.pairErrors = 0u;

   control.sortDispatchX = 0u;
   control.sortDispatchY = 1u;
   control.sortDispatchZ = 1u;

   control.hplocDispatchX = 0u;
   control.hplocDispatchY = 1u;
   control.hplocDispatchZ = 1u;

   control.buildError = 0u;
   control.rootClusterID = INVALID_ID;

   control.quadErrNanInf = 0u;
   control.quadErrExtent = 0u;
   control.quadErrCoplanar = 0u;
   control.quadErrDegenerate = 0u;
   control.quadErrCollapsed = 0u;

   control.realCount1 = 0u;
   control.realCount2 = 0u;
}
