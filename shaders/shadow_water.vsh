#version 460 compatibility

in vec2 mc_Entity;
in vec4 at_midBlock;

uniform mat4 shadowModelViewInverse;

#define QUAD_WRITE
#include "/lib/storage.glsl"

#ifdef MC_VENDOR_NVIDIA
out gl_PerVertex {
   flat float16_t gl_Position;
};
#endif

void main() {
   #ifdef MC_VENDOR_NVIDIA
   gl_Position = float16_t(0.0 / 0.0);
   #else
   gl_Position = vec4(0.0 / 0.0);
   #endif

   if (control.sceneFrozen != 0u) return;
   uint blockId = uint(mc_Entity.x);
   if (blockId == 1 && gl_Normal.y < -0.5) return;

   vec3 shadowViewSpacePos = (gl_ModelViewMatrix * vec4(gl_Vertex.xyz, 1.0)).xyz;
   vec3 playerSpacePos = (shadowModelViewInverse * vec4(shadowViewSpacePos, 1.0)).xyz;

   vec2 coord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
   vec3 color = gl_Color.rgb;
   float emission = at_midBlock.w;

   uint quadID, slot;
   getQuadWriteSlot(quadID, slot);
   if (quadID == INVALID_ID) return;

   if (slot == 0u) {
      writeQuadMaterial(quadID, blockId, 0u, emission, false, true, false);
   }
   writeQuadVertex(quadID, slot, playerSpacePos, coord, color);
   updateSceneBounds(playerSpacePos);
}
