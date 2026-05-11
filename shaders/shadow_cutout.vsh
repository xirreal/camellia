#version 460 compatibility

in vec2 mc_Entity;
in vec4 at_midBlock;

uniform mat4 shadowModelViewInverse;

#define QUAD_WRITE
#include "/lib/core/storage.glsl"
#include "/lib/scene/quad-write.glsl"

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

   vec3 normal = gl_NormalMatrix * gl_Normal;
   vec3 shadowViewSpacePos = (gl_ModelViewMatrix * vec4(gl_Vertex.xyz, 1.0)).xyz;
   const float NEAR_EPSILON = 0.000001;
   const float FAR_EPSILON = 0.0001;

   float depth = length(shadowViewSpacePos) / far;
   float nearFactor = clamp(mix(NEAR_EPSILON, FAR_EPSILON, depth), 0.0, 1.0);

   shadowViewSpacePos += normal * nearFactor;
   vec3 playerSpacePos = (shadowModelViewInverse * vec4(shadowViewSpacePos, 1.0)).xyz;

   vec2 coord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
   vec3 color = gl_Color.rgb;
   float emission = at_midBlock.w;

   uint quadID, slot;
   getQuadWriteSlot(quadID, slot);
   if (quadID == INVALID_ID) return;

   if (slot == 0u) {
      writeQuadMaterial(quadID, uint(mc_Entity.x), 0u, emission, true, false, false);
   }
   writeQuadVertex(quadID, slot, playerSpacePos, coord, color);
   updateSceneBounds(playerSpacePos);
}
