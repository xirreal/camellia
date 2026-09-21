#version 460 compatibility

in vec2 mc_Entity;
in vec4 at_midBlock;

uniform mat4 shadowModelViewInverse;
uniform sampler2D gtexture;
uniform sampler2D normals;
uniform sampler2D specular;
uniform int gtextureId = 0;

#define QUAD_WRITE
#include "/lib/core/storage.glsl"
#include "/lib/scene/quad-write.glsl"
#include "/lib/scene/textures-write.glsl"

void main() {
   gl_Position = vec4(0.0 / 0.0);

   // Pending PBR copies must finish even while captured geometry is frozen.
   uint textureID = captureEntityTexture(uint(gtextureId), gtexture, normals, specular);
   if (control.sceneFrozen != 0u) return;

   vec3 shadowViewSpacePos = (gl_ModelViewMatrix * vec4(gl_Vertex.xyz, 1.0)).xyz;
   vec3 playerSpacePos = (shadowModelViewInverse * vec4(shadowViewSpacePos, 1.0)).xyz;

   vec2 coord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
   vec3 color = gl_Color.rgb;
   float emission = at_midBlock.w;

   uint quadID, quadSlot;
   getQuadWriteSlot(quadID, quadSlot);
   if (quadID == INVALID_ID) return;

   writeQuad(quadID, quadSlot, playerSpacePos, coord, color, uint(mc_Entity.x), textureID, emission, true, false, false);
}
