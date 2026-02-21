#version 460 compatibility

in vec2 mc_Entity;
in vec4 at_midBlock;

uniform mat4 shadowModelViewInverse;
uniform int renderStage;

#define AS_VERTEX
#include "/lib/storage.glsl"
#include "/lib/encoding.glsl"

void main() {
   gl_Position = vec4(vec3(11.0), 1.0);

   vec3 shadowViewSpacePos = (gl_ModelViewMatrix * vec4(gl_Vertex.xyz, 1.0)).xyz;
   vec3 playerSpacePos = (shadowModelViewInverse * vec4(shadowViewSpacePos, 1.0)).xyz;

   vec2 coord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
   vec3 color = gl_Color.rgb;
   float emission = at_midBlock.w;

   uint textureID = -1;
   if (renderStage == MC_RENDER_STAGE_TERRAIN_SOLID) {
      textureID = 0;
   }

   Vertex vertex = Vertex(playerSpacePos, encodeVertexData(color, emission), coord, uint(mc_Entity.x), textureID);

   uint vertexId = getVertexWriteIndex();

   if (vertexId == INVALID_ID) {
      return;
   }

   vertices[vertexId] = vertex;
   updateSceneBounds(playerSpacePos);
}
