#version 460 compatibility

in vec2 mc_Entity;
in vec4 at_midBlock;

uniform mat4 shadowModelViewInverse;

#define AS_VERTEX
#include "/lib/storage.glsl"
#include "/lib/encoding.glsl"

void main() {
   uint vertexId = getVertexWriteIndex();

   gl_Position = ftransform();

   vec3 shadowViewSpacePos = (gl_ModelViewMatrix * vec4(gl_Vertex.xyz, 1.0)).xyz;
   vec3 playerSpacePos = (shadowModelViewInverse * vec4(shadowViewSpacePos, 1.0)).xyz;

   vec2 coord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
   vec3 normal = normalize(mat3(shadowModelViewInverse) * gl_NormalMatrix * gl_Normal);
   float emission = at_midBlock.w;

   vertices[vertexId] = Vertex(playerSpacePos, encodeNormal(normal), coord, emission, 0.0);
   updateSceneBounds(playerSpacePos);
}
