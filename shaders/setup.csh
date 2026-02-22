#version 460 compatibility

#define AS_VERTEX
#include "/lib/storage.glsl"
#include "/lib/textures.glsl"

const ivec3 workGroups = ivec3(1, 1, 1);

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

void main() {
   control.textureEntries = 0u;
   textureDataOffset = 0u;
   for (uint i = 0u; i < MAX_TEXTURES; i++) {
      textureMap[i].key = 0u;
   }
}
