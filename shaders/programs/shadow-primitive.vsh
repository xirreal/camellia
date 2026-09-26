in vec2 mc_Entity;
in vec4 at_midBlock;
uniform mat4 shadowModelViewInverse;
uniform vec4 entityColor;
uniform float alphaTestRef;
uniform int renderStage;
uniform bool firstPersonCamera;
uniform int entityId;
uniform int blockEntityId;
uniform float far;

out vec3 vPlayerPos;
out vec2 vCoord;
out vec3 vColor;
flat out float vEmission;
flat out uint vBlockId;
flat out uint vMaterial;
flat out float vNormalY;

void main() {
   bool terrain = (renderStage >= MC_RENDER_STAGE_TERRAIN_SOLID && renderStage <= MC_RENDER_STAGE_TERRAIN_CUTOUT) ||
      renderStage == MC_RENDER_STAGE_TERRAIN_TRANSLUCENT || renderStage == MC_RENDER_STAGE_TRIPWIRE;
   bool translucent = renderStage == MC_RENDER_STAGE_TERRAIN_TRANSLUCENT || (!terrain && blockEntityId == 0);
   bool alphaTested = renderStage != MC_RENDER_STAGE_TERRAIN_TRANSLUCENT && alphaTestRef > 0.0;
   vec3 viewPos = (gl_ModelViewMatrix * vec4(gl_Vertex.xyz, 1.0)).xyz;
   if (terrain && alphaTested) {
      float offset = clamp(mix(0.000001, 0.0001, length(viewPos) / far), 0.0, 1.0);
      viewPos += (gl_NormalMatrix * gl_Normal) * offset;
   }
   vPlayerPos = (shadowModelViewInverse * vec4(viewPos, 1.0)).xyz;
   vCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
   vColor = terrain ? gl_Color.rgb : mix(gl_Color.rgb, entityColor.rgb, entityColor.a);
   vEmission = at_midBlock.w;
   vBlockId = uint(mc_Entity.x);
   vMaterial = (alphaTested ? 1u : 0u) | (translucent ? 2u : 0u) |
      (firstPersonCamera && entityId == 1 && !terrain ? 4u : 0u);
   vNormalY = gl_Normal.y;

   gl_Position = vec4(0.0, 0.0, 0.0, 1.0);
}
