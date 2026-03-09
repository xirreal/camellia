#version 460 compatibility

#define AS_VERTEX
#include "/lib/storage.glsl"
#include "/lib/textures.glsl"

uniform int textureReloadCount;

const ivec3 workGroups = ivec3(256, 1, 1);

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

void main() {
   uint id = gl_GlobalInvocationID.x;
   if (id == 0u) {
      control.textureEntries = 0u;
      textureDataOffset = 0u;
      control.lastTextureReloadCount = textureReloadCount;
      control.textureReloadDelay = 0u;
   }

   if (id < MAX_TEXTURES) {
      textureMap[id].key = 0u;
   }
}
