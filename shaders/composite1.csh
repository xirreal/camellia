#version 460

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f) uniform writeonly image2D colorimg1;

uniform float viewWidth;
uniform float viewHeight;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform vec3 shadowLightPosition;
uniform bool firstPersonCamera;

uniform sampler2D blockAtlas;

uniform float near;

#include "/lib/storage.glsl"
#include "/lib/hploc.glsl"
#include "/lib/encoding.glsl"
#include "/lib/raytrace.glsl"

const float SHADOW_BIAS = 0.01;
const float SHADOW_MAX_DIST = 64.0;

void main() {
   ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
   if (coord.x >= int(viewWidth) || coord.y >= int(viewHeight)) return;

   vec2 uv = (vec2(coord) + 0.5) / vec2(viewWidth, viewHeight);
   vec2 ndc = uv * 2.0 - 1.0;

   // Camera ray in view space
   vec4 clipDir = vec4(ndc, 1.0, 1.0);
   vec4 viewDir = gbufferProjectionInverse * clipDir;
   viewDir.xyz /= viewDir.w;
   vec3 rd = normalize((gbufferModelViewInverse * vec4(viewDir.xyz, 0.0)).xyz);

   vec3 ro = (gbufferModelViewInverse * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

   if (firstPersonCamera) {
      vec3 extents = vec3(0.6);
      vec3 safeRd = rd + step(abs(rd), vec3(1e-8)) * 1e-8;
      vec3 t1 = (-extents - ro) / safeRd;
      vec3 t2 = (extents - ro) / safeRd;
      vec3 tMax = max(t1, t2);
      float tExit = min(tMax.x, min(tMax.y, tMax.z));

      if (tExit > 0.0) {
         ro += rd * (tExit + 0.001);
      }
   }

   TraceResult hit = traceBVH(ro, rd);

   if (!hit.hit) {
      imageStore(colorimg1, coord, vec4(0.0));
      return;
   }

   // Sample albedo from atlas
   vec4 texColor;
   if (hit.textureID == 0u) {
      texColor = texture(blockAtlas, hit.uv);
   } else {
      #ifdef ENTITY_TEXTURES
      texColor = sampleEntityTexture(hit.textureID, hit.uv);
      #else
      texColor = vec4(1.0);
      #endif
   }
   vec3 albedo = texColor.rgb * hit.vertexData.rgb;

   // Sun/moon direction in player space
   vec3 lightDir = normalize((gbufferModelViewInverse * vec4(0.01 * shadowLightPosition, 0.0)).xyz);

   // Shadow ray from hit point
   float NdotL = max(dot(hit.normal, lightDir), 0.0);
   float shadow = 1.0;

   if (NdotL > 0.0) {
      vec3 hitPos = ro + rd * hit.t;
      vec3 shadowOrigin = hitPos + hit.normal * SHADOW_BIAS;
      shadow = traceShadow(shadowOrigin, lightDir, SHADOW_MAX_DIST) ? 0.0 : 1.0;
   }

   float lighting = max(NdotL * shadow, 0.05) + 0.2;
   imageStore(colorimg1, coord, vec4(albedo * lighting, 1.0));
}
