#version 460

#include "/lib/core/settings.glsl"
#include "/lib/core/storage.glsl"
#define CONTROL_BUFFER_QUALIFIERS restrict readonly
#include "/lib/buffers/control.glsl"
#define PARENT_ID_BUFFER_QUALIFIERS restrict writeonly
#include "/lib/buffers/parent-id.glsl"

layout(local_size_x = 256) in;

void main() {
   uint gID = gl_GlobalInvocationID.x;
   uint N = control.sortTotal;
   if (control.sceneFrozen == 1u) return;

   if (gID < N) {
      parentIDs[gID] = INVALID_ID;
   }
}
