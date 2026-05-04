#version 460

#ifdef MC_GL_VENDOR_NVIDIA
#extension GL_NV_gpu_shader5 : require
#endif

in vec2 mc_Entity;
in vec4 at_midBlock;

uniform mat4 shadowModelViewInverse;

flat out vec3 vPlayerPos;
flat out vec3 vNormal;
flat out vec2 vCoord;
flat out float vEmission;
flat out vec3 vColor;
flat out uint vBlockId;

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

   vec3 shadowViewSpacePos = (gl_ModelViewMatrix * vec4(gl_Vertex.xyz, 1.0)).xyz;
   vPlayerPos = (shadowModelViewInverse * vec4(shadowViewSpacePos, 1.0)).xyz;
   vCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
   vNormal = normalize(mat3(shadowModelViewInverse) * gl_NormalMatrix * gl_Normal);
   vEmission = at_midBlock.w;
   vColor = gl_Color.rgb;
   vBlockId = uint(mc_Entity.x);
}
