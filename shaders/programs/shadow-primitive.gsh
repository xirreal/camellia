layout(triangles) in;
layout(triangle_strip, max_vertices = 3) out;

#include "/lib/scene/primitive-capture.glsl"
#include "/lib/scene/textures-write.glsl"

in vec3 vPlayerPos[];
in vec2 vCoord[];
in vec3 vColor[];
flat in float vEmission[];
flat in uint vBlockId[];
flat in uint vMaterial[];
flat in float vNormalY[];
flat out uvec4 vTextureCopy;

uniform sampler2D gtexture;
uniform int gtextureId;
uniform ivec2 gtextureSize;
uniform int renderStage;

void main() {
   bool terrain = (renderStage >= MC_RENDER_STAGE_TERRAIN_SOLID && renderStage <= MC_RENDER_STAGE_TERRAIN_CUTOUT) ||
      renderStage == MC_RENDER_STAGE_TERRAIN_TRANSLUCENT || renderStage == MC_RENDER_STAGE_TRIPWIRE;
   uint textureID = 0u;
   uvec4 copyJob = uvec4(0u);
   if (terrain) {
      if (subgroupElect() && control.blockAtlasTextureId == INVALID_ID && gtextureId > 0 &&
          all(equal(gtextureSize, textureSize(gtexture, 0)))) {
         atomicCompSwap(control.blockAtlasTextureId, INVALID_ID, uint(gtextureId));
      }
   } else {
      vec4 unusedPosition;
      textureID = captureEntityTexture(uint(gtextureId), gtexture, ivec2(shadowMapResolution), copyJob, unusedPosition);
   }

   if (control.sceneFrozen == 0u && !(terrain && vBlockId[0] == 1u && vNormalY[0] < -0.5)) {
      uint id = getTriangleWriteID();
      if (id != INVALID_ID) {
         writeQuadRecords(id, vPlayerPos[0], vPlayerPos[1], vPlayerPos[2], vPlayerPos[2],
            vCoord[0], vCoord[1], vCoord[2], vColor[0], vBlockId[0], textureID, vEmission[0],
            (vMaterial[0] & 1u) != 0u, (vMaterial[0] & 2u) != 0u, (vMaterial[0] & 4u) != 0u);
      }
   }

   if (copyJob.w == 0u) return;
   for (int i = 0; i < 3; ++i) {
      gl_Position = vec4(i == 1 ? 3.0 : -1.0, i == 2 ? 3.0 : -1.0, 0.0, 1.0);
      vTextureCopy = copyJob;
      EmitVertex();
   }
   EndPrimitive();
}
