#version 460 compatibility

in vec2 mc_Entity;
in vec4 at_midBlock;

uniform mat4 shadowModelViewInverse;
uniform int gtextureId;
uniform ivec2 gtextureSize;
uniform sampler2D gtexture;

#define QUAD_WRITE
#include "/lib/core/storage.glsl"
#include "/lib/scene/quad-write.glsl"

void main() {
   gl_Position = vec4(0.0 / 0.0);

   if (control.sceneFrozen != 0u) return;
   // Keep gtexture active so Iris tracks its ID; reject stale binding sizes.
   if (subgroupElect() && control.blockAtlasTextureId == INVALID_ID && gtextureId > 0 &&
       all(equal(gtextureSize, textureSize(gtexture, 0)))) {
      atomicCompSwap(control.blockAtlasTextureId, INVALID_ID, uint(gtextureId));
   }
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

   writeQuad(quadID, slot, playerSpacePos, coord, color, blockId, 0u, emission, false, true, false);
}
