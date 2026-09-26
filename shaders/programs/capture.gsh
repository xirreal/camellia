#if defined(MC_GL_VENDOR_AMD) || defined(MC_GL_VENDOR_ATI) || defined(MC_GL_RENDERER_RADEON)
#include "/lib/core/settings.glsl"
#endif

layout(triangles) in;
#ifdef GBUFFERS_LAYER_CAPTURE
layout(triangle_strip, max_vertices = 6) out;
#else
layout(triangle_strip, max_vertices = 3) out;
#endif

in vec3 vPlayerPos[];
in vec3 vWorldNormal[];
in vec4 vWorldTangent[];
in float vVertexEmission[];
in vec4 vColor[];
in vec2 vTexCoord[];
flat in uint vBlockID[];
#ifndef AMD_PRIMITIVE_CAPTURE
flat in uvec4 vTextureCopy[];
in vec4 vTextureCopyPosition[];
#endif

out vec3 gPlayerPos;
out vec3 gWorldNormal;
out vec4 gWorldTangent;
out float gVertexEmission;
out vec4 gColor;
out vec2 gTexCoord;
flat out uint gBlockID;
flat out uvec4 gTextureCopy;

#ifdef AMD_PRIMITIVE_CAPTURE
#include "/lib/scene/primitive-capture.glsl"
#ifdef GBUFFERS_LAYER_CAPTURE
#include "/lib/scene/textures-write.glsl"
uniform int gtextureId;
uniform sampler2D gtexture;
uniform float viewWidth;
uniform float viewHeight;
#else
uniform int renderStage;
#endif
#endif

void main() {
   #ifdef AMD_PRIMITIVE_CAPTURE
   uint textureID = 0u;
   uvec4 copyJob = uvec4(0u);
   bool translucent = false;
   #ifdef GBUFFERS_LAYER_CAPTURE
   vec4 unusedPosition;
   textureID = captureEntityTexture(uint(gtextureId), gtexture, ivec2(viewWidth, viewHeight), copyJob, unusedPosition);
   bool capture = vBlockID[0] == 3u || vBlockID[0] == 4u;
   #else
   bool terrain = (renderStage >= MC_RENDER_STAGE_TERRAIN_SOLID && renderStage <= MC_RENDER_STAGE_TERRAIN_CUTOUT) ||
      renderStage == MC_RENDER_STAGE_TERRAIN_TRANSLUCENT || renderStage == MC_RENDER_STAGE_TRIPWIRE;

   if (!terrain) return;
   translucent = renderStage == MC_RENDER_STAGE_TERRAIN_TRANSLUCENT;
   bool capture = false;
   #ifdef ENABLE_GBUFFER_CAPTURE
   capture = length((vPlayerPos[0] + vPlayerPos[1] + vPlayerPos[2]) / 3.0) > float(SHADOW_CAPTURE_DISTANCE) &&
      !(translucent && vBlockID[0] == 1u && vWorldNormal[0].y < -0.5);
   #endif
   #endif
   if (control.sceneFrozen == 0u && capture) {
      uint id = getTriangleWriteID();
      if (id != INVALID_ID) {
         writeQuadRecords(id, vPlayerPos[0], vPlayerPos[1], vPlayerPos[2], vPlayerPos[2],
            vTexCoord[0], vTexCoord[1], vTexCoord[2], vColor[0].rgb, vBlockID[0], textureID,
            vVertexEmission[0], !translucent, translucent, false);
      }
   }
   #endif

   for (int i = 0; i < 3; ++i) {
      gl_Position = gl_in[i].gl_Position;
      gPlayerPos = vPlayerPos[i];
      gWorldNormal = vWorldNormal[i];
      gWorldTangent = vWorldTangent[i];
      gVertexEmission = vVertexEmission[i];
      gColor = vColor[i];
      gTexCoord = vTexCoord[i];
      gBlockID = vBlockID[i];
      gTextureCopy = uvec4(0u);
      EmitVertex();
   }
   EndPrimitive();
   #ifdef GBUFFERS_LAYER_CAPTURE
   #ifdef AMD_PRIMITIVE_CAPTURE
   if (copyJob.w == 0u) return;
   #else
   if (vTextureCopy[0].w == 0u) return;
   #endif
   for (int i = 0; i < 3; ++i) {
      #ifdef AMD_PRIMITIVE_CAPTURE
      gl_Position = vec4(i == 1 ? 3.0 : -1.0, i == 2 ? 3.0 : -1.0, 0.0, 1.0);
      gTextureCopy = copyJob;
      #else
      gl_Position = vTextureCopyPosition[i];
      gTextureCopy = vTextureCopy[i];
      #endif
      EmitVertex();
   }
   EndPrimitive();
   #endif
}
