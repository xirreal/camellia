uniform mat4 gbufferModelViewInverse;

#include "/lib/core/settings.glsl"

#if defined GBUFFERS_TERRAIN_CUTOUT && !defined ENABLE_GBUFFER_CAPTURE
uniform float far;
#endif

#ifdef GBUFFERS_GEOMETRY_CAPTURE
in vec2 mc_Entity;
#endif

#if defined GBUFFERS_GEOMETRY_CAPTURE && defined ENABLE_GBUFFER_CAPTURE
#define QUAD_WRITE
#include "/lib/core/storage.glsl"
#include "/lib/scene/quad-write.glsl"
#endif

in vec4 at_tangent;
#ifdef GBUFFERS_VERTEX_EMISSION
in vec4 at_midBlock;
#endif

out vec3 vPlayerPos;
out vec3 vWorldNormal;
out vec4 vWorldTangent;
#ifdef GBUFFERS_VERTEX_EMISSION
out float vVertexEmission;
#endif
out vec4 vColor;
out vec2 vTexCoord;
flat out uint vBlockID;

void main() {
   vec4 viewSpacePos = gl_ModelViewMatrix * gl_Vertex;
   #ifdef GBUFFERS_TERRAIN_CUTOUT
   float depth = length(viewSpacePos.xyz) / far;
   float nearFactor = clamp(mix(0.000001, 0.0001, depth), 0.0, 1.0);
   viewSpacePos.xyz += (gl_NormalMatrix * gl_Normal) * nearFactor;
   #endif
   mat3 normalToPlayer = mat3(gbufferModelViewInverse) * gl_NormalMatrix;

   gl_Position = gl_ProjectionMatrix * viewSpacePos;
   vPlayerPos = (gbufferModelViewInverse * viewSpacePos).xyz;
   vWorldNormal = normalize(normalToPlayer * gl_Normal);
   vWorldTangent = vec4(normalize(normalToPlayer * at_tangent.xyz), at_tangent.w);
   #ifdef GBUFFERS_VERTEX_EMISSION
   vVertexEmission = at_midBlock.w;
   #endif
   vColor = gl_Color;
   vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
   #ifdef GBUFFERS_GEOMETRY_CAPTURE
   vBlockID = uint(mc_Entity.x);
   #else
   vBlockID = 0u;
   #endif

   #if defined GBUFFERS_GEOMETRY_CAPTURE && defined ENABLE_GBUFFER_CAPTURE
   if (control.sceneFrozen == 0u) {
      uint lane = gl_SubgroupInvocationID;
      uint quadLane = lane & ~3u;
      uint lastLane = gl_SubgroupSize - 1u;
      vec3 p0 = subgroupShuffle(vPlayerPos, quadLane);
      vec3 p1 = subgroupShuffle(vPlayerPos, min(quadLane + 1u, lastLane));
      vec3 p2 = subgroupShuffle(vPlayerPos, min(quadLane + 2u, lastLane));
      vec3 p3 = subgroupShuffle(vPlayerPos, min(quadLane + 3u, lastLane));

      bool captureGeometry = length((p0 + p1 + p2 + p3) * 0.25) > float(SHADOW_CAPTURE_DISTANCE);
      uint blockID = subgroupShuffle(uint(mc_Entity.x), quadLane);
      #ifdef GBUFFERS_TRANSLUCENT_GEOMETRY
      captureGeometry = captureGeometry && !(blockID == 1u && subgroupShuffle(gl_Normal.y, quadLane) < -0.5);
      #endif

      uint quadID, quadSlot;
      getConditionalQuadWriteSlot(captureGeometry, quadID, quadSlot);
      writeQuad(quadID, quadSlot, vPlayerPos, vTexCoord, gl_Color.rgb,
         blockID, 0u,
         #ifdef GBUFFERS_VERTEX_EMISSION
         vVertexEmission,
         #else
         0.0,
         #endif
         #ifdef GBUFFERS_ALPHA_GEOMETRY
         true,
         #else
         false,
         #endif
         #ifdef GBUFFERS_TRANSLUCENT_GEOMETRY
         true,
         #else
         false,
         #endif
         false);
   }
   #endif
}
