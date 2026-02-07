#version 460 compatibility

#define AS_VERTEX
#include "/lib/storage.glsl"

const ivec3 workGroups = ivec3(1, 1, 1);

layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;

void main() {
   if (gl_GlobalInvocationID.x == 0) {
      count = 0;
      bounds.minX = 0xFFFFFFFF;
      bounds.minY = 0xFFFFFFFF;
      bounds.minZ = 0xFFFFFFFF;
      bounds.maxX = 0;
      bounds.maxY = 0;
      bounds.maxZ = 0;
   }
}
