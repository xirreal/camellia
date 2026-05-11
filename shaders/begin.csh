#version 460 compatibility

uniform int textureReloadCount;
uniform bool hideGUI;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform vec3 shadowLightPosition;
uniform vec3 sunPosition;
uniform bool firstPersonCamera;
uniform vec3 cameraPosition;

uniform int frameCounter;

#define QUAD_WRITE
#include "/lib/core/storage.glsl"
#include "/lib/buffers/control.glsl"
#define QUAD_DATA_BUFFER_QUALIFIERS restrict writeonly
#include "/lib/buffers/quad-data.glsl"
#define TEXTURE_INFOS_BUFFER_QUALIFIERS restrict writeonly
#include "/lib/buffers/texture-infos.glsl"
#include "/lib/core/settings.glsl"

const ivec3 workGroups = ivec3(256, 1, 1);

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

void main() {
   uint id = gl_GlobalInvocationID.x;

   if (control.lastTextureReloadCount != textureReloadCount) {
      if (id == 0) {
         control.textureReloadDelay = 2u;
         control.lastTextureReloadCount = textureReloadCount;
      }
   }

   if (control.textureReloadDelay > 0u) {
      if (id == 0) {
         control.textureEntries = 0u;
         textureDataOffset = 0u;
         control.textureReloadDelay--;
      }
      if (id < MAX_TEXTURES) {
         textureMap[id].key = 0u;
      }
   }

   #if MODE == 1
   if (hideGUI && frameCounter > 15) {
      if (id == 0) {
         if (control.sceneFrozen == 0u) {
            control.frozenProjInv = gbufferProjectionInverse;
            control.frozenModelViewInv = gbufferModelViewInverse;
            control.frozenLightPos = vec4(shadowLightPosition, 0.0);
            control.frozenSunPos = vec4(sunPosition, 0.0);
            control.frozenFirstPerson = firstPersonCamera ? 1u : 0u;
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

      control.buildError = 0u;
      control.rootClusterID = INVALID_ID;

      control.quadErrNanInf = 0u;
      control.quadErrExtent = 0u;
      control.quadErrCoplanar = 0u;
      control.quadErrDegenerate = 0u;
      control.quadErrCollapsed = 0u;

      control.realCount1 = 0u;
      control.realCount2 = 0u;
   }
}
