#version 460 compatibility

uniform int textureReloadCount;
uniform bool hideGUI;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform vec3 shadowLightPosition;
uniform vec3 sunPosition;
uniform vec3 cameraPosition;

uniform int frameCounter;

#define QUAD_WRITE
#include "/lib/core/storage.glsl"
#include "/lib/buffers/control.glsl"
#include "/lib/buffers/quad-count.glsl"
#define TEXTURE_INFOS_BUFFER_QUALIFIERS restrict writeonly
#include "/lib/buffers/texture-infos.glsl"
#include "/lib/core/settings.glsl"

const ivec3 workGroups = ivec3(1, 1, 1);

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

void main() {
   uint id = gl_GlobalInvocationID.x;

   // One workgroup: finish every cache clear before publishing reset state.
   bool resetTextures = control.lastTextureReloadCount != textureReloadCount || control.textureReloadDelay > 0u;
   if (resetTextures) {
      for (uint slot = id; slot < MAX_TEXTURES; slot += 256u) {
         textureMap[slot].key = 0u;
         textureMap[slot].pbrPendingFrame = INVALID_ID;
      }
   }
   barrier();
   if (id != 0u) return;
   if (control.lastTextureReloadCount != textureReloadCount) {
      control.textureReloadDelay = 2u;
      control.lastTextureReloadCount = textureReloadCount;
   }
   if (resetTextures) {
      control.textureEntries = 0u;
      textureDataOffset = 0u;
      control.blockAtlasTextureId = INVALID_ID;
      control.textureReloadDelay--;
   }

   #if MODE == 1
   if (hideGUI && frameCounter > 15 && !resetTextures) {
      if (id == 0) {
         if (control.sceneFrozen == 0u) {
            control.frozenProjInv = gbufferProjectionInverse;
            control.frozenModelViewInv = gbufferModelViewInverse;
            control.frozenLightPos = vec4(shadowLightPosition, 0.0);
            control.frozenSunPos = vec4(sunPosition, 0.0);
            control.frozenCameraPos = vec4(cameraPosition, 0.0);
         }
         control.sceneFrozen = 1u;

         control.prepareDispatchX = 0u;
         control.prepareDispatchY = 1u;
         control.prepareDispatchZ = 1u;

         control.sortDispatchX = 0u;
         control.sortDispatchY = 1u;
         control.sortDispatchZ = 1u;

         control.hplocDispatchX = 0u;
         control.hplocDispatchY = 1u;
         control.hplocDispatchZ = 1u;
         control.wideDispatchX = 0u;
      }
      return;
   }
   #endif

   if (id == 0) {
      control.sceneFrozen = 0u;

      quadCount = 0u;

      control.boundsMinX = 0xFFFFFFFFu;
      control.boundsMinY = 0xFFFFFFFFu;
      control.boundsMinZ = 0xFFFFFFFFu;
      control.boundsMaxX = 0u;
      control.boundsMaxY = 0u;
      control.boundsMaxZ = 0u;

      control.numBVH2Nodes = 0u;

      control.sortTotal = 0u;
      control.sortErrors = 0u;
      control.pairErrors = 0u;

      control.prepareDispatchX = 0u;
      control.prepareDispatchY = 1u;
      control.prepareDispatchZ = 1u;

      control.sortDispatchX = 0u;
      control.sortDispatchY = 1u;
      control.sortDispatchZ = 1u;

      control.hplocDispatchX = 0u;
      control.hplocDispatchY = 1u;
      control.hplocDispatchZ = 1u;

      control.rootClusterID = INVALID_ID;

      control.quadErrNanInf = 0u;
      control.quadErrExtent = 0u;
      control.quadErrCoplanar = 0u;
      control.quadErrDegenerate = 0u;
      control.quadErrCollapsed = 0u;
      control.quadSubgroupTests = 0u;
      control.quadSubgroupFull = 0u;
      control.quadSubgroupConsecutive = 0u;
      control.quadSubgroupAllocator = 0u;
      control.quadSubgroupSlots = 0u;
      #ifdef ENABLE_SUBGROUP_VALIDATION
      control.captureDebugVersion = 1u;
      control.captureDebugFrame = uint(frameCounter);
      control.captureComputeSize = gl_SubgroupSize;
      control.captureDebugPaths = CAPTURE_DEBUG_PATHS;
      for (uint path = 0u; path < control.captureDebugPaths; ++path) {
         control.captureSubgroups[path] = CaptureSubgroupDebug(
            0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u,
            0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u,
            uvec4(0u), uvec4(0u), uvec4(0u), uvec4(0u),
            uvec4(0u), uvec4(0u), uvec4(0u), uvec4(0u));
      }
      #endif
   }
}
