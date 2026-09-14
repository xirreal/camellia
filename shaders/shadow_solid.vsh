#version 460 compatibility

in vec2 mc_Entity;
in vec4 at_midBlock;

uniform mat4 shadowModelViewInverse;

#define QUAD_WRITE
#include "/lib/core/storage.glsl"
#include "/lib/scene/quad-write.glsl"

void main() {
   gl_Position = vec4(0.0 / 0.0);

   if (control.sceneFrozen != 0u) return;

   vec3 shadowViewSpacePos = (gl_ModelViewMatrix * vec4(gl_Vertex.xyz, 1.0)).xyz;
   vec3 playerSpacePos = (shadowModelViewInverse * vec4(shadowViewSpacePos, 1.0)).xyz;

   vec2 coord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
   vec3 color = gl_Color.rgb;
   float emission = at_midBlock.w;

   uint quadID, slot;
   getQuadWriteSlot(quadID, slot);
   if (quadID == INVALID_ID) return;

   writeQuad(quadID, slot, playerSpacePos, coord, color, uint(mc_Entity.x), 0u, emission, false, false, false);
}
