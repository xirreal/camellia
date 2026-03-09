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

#define AS_VERTEX
#include "/lib/storage.glsl"
#include "/lib/encoding.glsl"
#include "/lib/textures.glsl"

void main() {
   gl_Position = vec4(vec3(11.0), 1.0);

   if (control.sceneFrozen != 0u) return;

   // Mark current player quads so the ray tracer can skip them on primary rays
   bool isPlayer = firstPersonCamera && entityId == 1;

   vec3 shadowViewSpacePos = (gl_ModelViewMatrix * vec4(gl_Vertex.xyz, 1.0)).xyz;
   vec3 playerSpacePos = (shadowModelViewInverse * vec4(shadowViewSpacePos, 1.0)).xyz;

   vec2 coord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
   vec3 color = gl_Color.rgb;

   uint textureID = 0;
   #ifdef ENTITY_TEXTURES

   ivec2 tSize = textureSize(gtexture, 0);

   bool isNew = false;
   uint slot = INVALID_ID;

   if (subgroupElect()) {
      slot = textureMapInsert(uint(gtextureId), tSize, isNew);
   }

   slot = subgroupBroadcastFirst(slot);
   isNew = subgroupBroadcastFirst(isNew);

   if (isNew && slot != INVALID_ID) {
      #ifdef ENTITY_PBR
      copyTextureWithPBR(textureMap[slot].baseOffset, gtexture, normals, specular, tSize, textureSize(normals, 0), textureSize(specular, 0));
      #else
      copyTexture(textureMap[slot].baseOffset, gtexture, tSize);
      #endif
   }

   textureID = (slot == INVALID_ID) ? 0 : slot + 1u;
   #else
   textureID = 1; // sentinel to disable alpha testing in rt loop
   #endif

   Vertex vertex = Vertex(playerSpacePos, encodeVertexData(mix(color.rgb, entityColor.rgb, entityColor.a), 0.0, true, false, isPlayer), coord, uint(mc_Entity.x), textureID);

   uint vertexId = getVertexWriteIndex();

   if (vertexId == INVALID_ID) {
      return;
   }

   vertices[vertexId] = vertex;
   updateSceneBounds(playerSpacePos);
}
