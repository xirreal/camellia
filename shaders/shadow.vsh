#version 460 compatibility

in vec2 mc_Entity;
in vec4 at_midBlock;

uniform mat4 shadowModelViewInverse;

out vec3 vPlayerPos;
out vec3 vNormal;
out vec2 vCoord;
out float vEmission;
out vec3 vColor;
flat out uint vBlockId;

void main() {
   gl_Position = vec4(vec3(11.0), 1.0);

   vec3 shadowViewSpacePos = (gl_ModelViewMatrix * vec4(gl_Vertex.xyz, 1.0)).xyz;
   vPlayerPos = (shadowModelViewInverse * vec4(shadowViewSpacePos, 1.0)).xyz;
   vCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
   vNormal = normalize(mat3(shadowModelViewInverse) * gl_NormalMatrix * gl_Normal);
   vEmission = at_midBlock.w;
   vColor = gl_Color.rgb;
   vBlockId = uint(mc_Entity.x);
}
