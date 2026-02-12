#version 460 compatibility

in vec2 mc_Entity;
in vec4 at_midBlock;

uniform mat4 shadowModelViewInverse;

#define AS_VERTEX
#include "/lib/storage.glsl"
#include "/lib/encoding.glsl"

void main() {
   VertexAlloc alloc = getVertexWriteIndex();

   gl_Position = vec4(vec3(11.0), 1.0);

   if (alloc.vertexId == INVALID_ID) {
      return;
   }

   vec3 shadowViewSpacePos = (gl_ModelViewMatrix * vec4(gl_Vertex.xyz, 1.0)).xyz;
   vec3 playerSpacePos = (shadowModelViewInverse * vec4(shadowViewSpacePos, 1.0)).xyz;

   vec2 coord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
   vec3 normal = normalize(mat3(shadowModelViewInverse) * gl_NormalMatrix * gl_Normal);
   float emission = at_midBlock.w;

   Vertex vertex = Vertex(playerSpacePos, encodeNormal(normal), coord, emission, 0.0);

   vertices[alloc.vertexId] = vertex;
   updateSceneBounds(playerSpacePos);

   fillHoleVertices(alloc, vertex);
}
