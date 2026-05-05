#version 460 compatibility

in vec2 mc_Entity;
in vec4 at_midBlock;

uniform vec4 entityColor;
uniform mat4 shadowModelViewInverse;
uniform sampler2D gtexture;
uniform sampler2D normals;
uniform sampler2D specular;
uniform int gtextureId;
uniform bool firstPersonCamera;
uniform int entityId;

#define QUAD_WRITE
#include "/lib/storage.glsl"
#include "/lib/quad-write.glsl"
#include "/lib/textures-write.glsl"

#ifdef MC_GL_VENDOR_NVIDIA
out gl_PerVertex {
   flat float16_t gl_Position;
};
#endif

void main() {
   #ifdef MC_GL_VENDOR_NVIDIA
   gl_Position = float16_t(0.0 / 0.0);
   #else
   gl_Position = vec4(0.0 / 0.0);
   #endif

   if (control.sceneFrozen != 0u) return;

   // Mark current player quads so the ray tracer can skip them on primary rays
   bool isPlayer = firstPersonCamera && entityId == 1;

   vec3 shadowViewSpacePos = (gl_ModelViewMatrix * vec4(gl_Vertex.xyz, 1.0)).xyz;
   vec3 playerSpacePos = (shadowModelViewInverse * vec4(shadowViewSpacePos, 1.0)).xyz;

   vec2 coord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
   vec3 color = mix(gl_Color.rgb, entityColor.rgb, entityColor.a);

   uint textureID = 0;
   #ifdef ENTITY_TEXTURES

   ivec2 tSize = textureSize(gtexture, 0);

   bool isNew = false;
   uint texSlot = INVALID_ID;

   if (subgroupElect()) {
      texSlot = textureMapInsert(uint(gtextureId), tSize, isNew);
   }

   texSlot = subgroupBroadcastFirst(texSlot);
   isNew = subgroupBroadcastFirst(isNew);

   if (isNew && texSlot != INVALID_ID) {
      #ifdef ENTITY_PBR
      copyTextureWithPBR(textureMap[texSlot].baseOffset, gtexture, normals, specular, tSize, textureSize(normals, 0), textureSize(specular, 0));
      #else
      copyTexture(textureMap[texSlot].baseOffset, gtexture, tSize);
      #endif
   }

   textureID = (texSlot == INVALID_ID) ? 0 : texSlot + 1u;
   #else
   textureID = 1; // sentinel to disable alpha testing in rt loop
   #endif

   uint quadID, quadSlot;
   getQuadWriteSlot(quadID, quadSlot);
   if (quadID == INVALID_ID) return;

   if (quadSlot == 0u) {
      writeQuadMaterial(quadID, uint(mc_Entity.x), textureID, 0.0, true, false, isPlayer);
   }
   writeQuadVertex(quadID, quadSlot, playerSpacePos, coord, color);
   updateSceneBounds(playerSpacePos);
}
