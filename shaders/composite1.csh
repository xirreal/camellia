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

float hash12(vec2 p)
{
   vec3 p3 = fract(vec3(p.xyx) * .1031);
   p3 += dot(p3, p3.yzx + 33.33);
   return fract((p3.x + p3.y) * p3.z);
}

void main() {
   ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
   if (coord.x >= int(viewWidth) || coord.y >= int(viewHeight)) return;

   vec2 uv = (vec2(coord) + 0.5) / vec2(viewWidth, viewHeight);
   vec2 ndc = uv * 2.0 - 1.0;

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

   vec3 lightDir = normalize((gbufferModelViewInverse * vec4(0.01 * shadowLightPosition, 0.0)).xyz);

   float NdotL = max(dot(hit.normal, lightDir), 0.0);
   float shadow = 1.0;

   if (NdotL > 0.0) {
      vec3 hitPos = ro + rd * hit.t;
      vec3 shadowOrigin = hitPos + hit.normal * SHADOW_BIAS;

      int NUM_SAMPLES = 4;
      float lightSpread = 0.03;
      float shadowAccum = 0.0;
      float weightAccum = 0.0;

      vec3 up = abs(lightDir.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
      vec3 tangent = normalize(cross(up, lightDir));
      vec3 bitangent = cross(lightDir, tangent);

      float seed = hash12(vec2(coord)) * 6.28318530718;

      for (int i = 0; i < NUM_SAMPLES; i++) {
         float r = sqrt((float(i) + 0.5) / float(NUM_SAMPLES));
         float theta = float(i) * 2.3999632 + seed;

         vec2 diskPos = vec2(r * cos(theta), r * sin(theta));

         vec3 sampleDir = normalize(lightDir + (tangent * diskPos.x + bitangent * diskPos.y) * lightSpread);
         float sampleNdotL = dot(hit.normal, sampleDir);

         if (sampleNdotL > 0.0) {
            float rayLit = traceShadow(shadowOrigin, sampleDir, SHADOW_MAX_DIST) ? 0.0 : 1.0;
            shadowAccum += rayLit * sampleNdotL;
            weightAccum += sampleNdotL;
         }
      }

      shadow = weightAccum > 0.0 ? shadowAccum / weightAccum : 0.0;
   }

   float lighting = max(NdotL * shadow, 0.05) + 0.2;
   imageStore(colorimg1, coord, vec4(albedo * lighting, 1.0));
}
