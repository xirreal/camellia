#version 460 compatibility

in vec2 mc_Entity;

uniform vec4 entityColor;
uniform mat4 shadowModelViewInverse;
uniform sampler2D gtexture;
uniform int gtextureId;
uniform bool firstPersonCamera;
uniform int entityId;

#define QUAD_WRITE
#define CAPTURE_DEBUG_PATH 3
#include "/lib/core/storage.glsl"
#include "/lib/scene/quad-write.glsl"
#include "/lib/scene/textures-write.glsl"

flat out uvec4 vTextureCopy;

void main() {
   // Pending PBR copies must finish even while captured geometry is frozen.
   uint textureID = captureEntityTexture(uint(gtextureId), gtexture, ivec2(shadowMapResolution), vTextureCopy, gl_Position);
   if (control.sceneFrozen != 0u) return;

   // Mark current player quads so the ray tracer can skip them on primary rays
   bool isPlayer = firstPersonCamera && entityId == 1;

   vec3 shadowViewSpacePos = (gl_ModelViewMatrix * vec4(gl_Vertex.xyz, 1.0)).xyz;
   vec3 playerSpacePos = (shadowModelViewInverse * vec4(shadowViewSpacePos, 1.0)).xyz;

   vec2 coord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
   vec3 color = mix(gl_Color.rgb, entityColor.rgb, entityColor.a);

   uint quadID, quadSlot;
   getQuadWriteSlot(quadID, quadSlot);
   if (quadID == INVALID_ID) return;

   writeQuad(quadID, quadSlot, playerSpacePos, coord, color, uint(mc_Entity.x), textureID, 0.0, true, true, isPlayer);
}
