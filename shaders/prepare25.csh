#version 460

#include "/lib/storage.glsl"
#include "/lib/hploc.glsl"

layout(local_size_x = 256) in;

void main() {
   uint gID = gl_GlobalInvocationID.x;
   uint N = control.data[CTRL_SORT_TOTAL];

   if (gID < N) {
      parentIDs[gID] = INVALID_ID;
   }
}
