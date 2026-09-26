#if defined(MC_GL_VENDOR_AMD) || defined(MC_GL_VENDOR_ATI) || defined(MC_GL_RENDERER_RADEON)
#version 460 compatibility
#include "/programs/shadow-primitive.vsh"
#else
#version 460

in vec2 mc_Entity;
in vec4 at_midBlock;

uniform mat4 shadowModelViewInverse;

flat out vec3 vPlayerPos;
flat out vec2 vCoord;
flat out float vEmission;
flat out vec3 vColor;
flat out uint vBlockId;

void main() {
   gl_Position = vec4(0.0 / 0.0);

   vec3 shadowViewSpacePos = (gl_ModelViewMatrix * vec4(gl_Vertex.xyz, 1.0)).xyz;
   vPlayerPos = (shadowModelViewInverse * vec4(shadowViewSpacePos, 1.0)).xyz;
   vCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
   vEmission = at_midBlock.w;
   vColor = gl_Color.rgb;
   vBlockId = uint(mc_Entity.x);
}
#endif
