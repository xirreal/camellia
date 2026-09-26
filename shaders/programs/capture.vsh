uniform mat4 gbufferModelViewInverse;

#include "/lib/core/settings.glsl"

#if defined GBUFFERS_TERRAIN_CUTOUT && !defined ENABLE_GBUFFER_CAPTURE
uniform float far;
#endif
#ifdef GBUFFERS_PRIMITIVE_CAPTURE
uniform float far;
uniform float alphaTestRef;
uniform int renderStage;
#endif

#ifdef GBUFFERS_GEOMETRY_CAPTURE
in vec2 mc_Entity;
#endif

#if !defined AMD_PRIMITIVE_CAPTURE && ((defined GBUFFERS_GEOMETRY_CAPTURE && defined ENABLE_GBUFFER_CAPTURE) || defined GBUFFERS_LAYER_CAPTURE)
#define QUAD_WRITE
#ifdef GBUFFERS_LAYER_CAPTURE
#define CAPTURE_DEBUG_PATH 8
#elif defined GBUFFERS_TRANSLUCENT_GEOMETRY
#define CAPTURE_DEBUG_PATH 7
#elif defined GBUFFERS_ALPHA_GEOMETRY
#define CAPTURE_DEBUG_PATH 6
#else
#define CAPTURE_DEBUG_PATH 5
#endif
#include "/lib/core/storage.glsl"
#include "/lib/scene/quad-write.glsl"
#endif

#ifdef GBUFFERS_LAYER_CAPTURE
uniform int blockEntityId;
uniform int gtextureId;
uniform sampler2D gtexture;
uniform float viewWidth;
uniform float viewHeight;
flat out uvec4 vTextureCopy;
out vec4 vTextureCopyPosition;
#ifndef AMD_PRIMITIVE_CAPTURE
#include "/lib/scene/textures-write.glsl"
#endif
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
   #if defined GBUFFERS_TERRAIN_CUTOUT || defined GBUFFERS_PRIMITIVE_CAPTURE
   #ifdef GBUFFERS_PRIMITIVE_CAPTURE
   if (alphaTestRef > 0.0 && renderStage != MC_RENDER_STAGE_TERRAIN_TRANSLUCENT) {
   #endif
   float depth = length(viewSpacePos.xyz) / far;
   float nearFactor = clamp(mix(0.000001, 0.0001, depth), 0.0, 1.0);
   viewSpacePos.xyz += (gl_NormalMatrix * gl_Normal) * nearFactor;
   #ifdef GBUFFERS_PRIMITIVE_CAPTURE
   }
   #endif
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
   #elif defined GBUFFERS_LAYER_CAPTURE
   vBlockID = uint(blockEntityId);
   #else
   vBlockID = 0u;
   #endif

   #if defined GBUFFERS_LAYER_CAPTURE && defined AMD_PRIMITIVE_CAPTURE
   vVertexEmission = blockEntityId == 3 && gl_MultiTexCoord1.x >= 240.0 ? 15.0 : 0.0;
   #elif defined GBUFFERS_LAYER_CAPTURE
   bool captureLayer = blockEntityId == 3 || blockEntityId == 4;
   uint textureID = captureEntityTexture(uint(gtextureId), gtexture, ivec2(viewWidth, viewHeight), vTextureCopy, vTextureCopyPosition);
   if (control.sceneFrozen == 0u) {
      uint quadID, quadSlot;
      getConditionalQuadWriteSlot(captureLayer, quadID, quadSlot);
      float emission = blockEntityId == 3 && gl_MultiTexCoord1.x >= 240.0 ? 15.0 : 0.0;
      writeQuad(quadID, quadSlot, vPlayerPos, vTexCoord, gl_Color.rgb,
         uint(blockEntityId), textureID, emission, true, false, false);
   }
   #endif

   #if defined GBUFFERS_GEOMETRY_CAPTURE && defined ENABLE_GBUFFER_CAPTURE && !defined AMD_PRIMITIVE_CAPTURE
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
