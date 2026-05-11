#version 460

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

uniform sampler2D colortex6;
uniform sampler2D colortex7;
uniform float viewWidth;
uniform float viewHeight;

uniform vec3 sunPosition;
uniform mat4 gbufferModelViewInverse;

uniform int randomSeed;
uniform int frameCounter;

uniform sampler2D blockAtlas;

#include "/lib/core/storage.glsl"
#include "/lib/core/encoding.glsl"
#include "/lib/bvh/hploc.glsl"
#include "/lib/bvh/raytrace.glsl"
#include "/lib/restir/sampling.glsl"
#include "/lib/restir/reservoir.glsl"
#include "/lib/atmosphere/atmosphere.glsl"

#define RESTIR_MAX_BOUNCES 2

const float RESTIR_SHADOW_MAX_DIST = 256.0;
const float RESTIR_SUN_HALF_ANGLE = 0.007;

vec3 sampleSunCap(vec3 sunDirection, float cosThreshold) {
   vec3 up = abs(sunDirection.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
   vec3 tangent = normalize(cross(up, sunDirection));
   vec3 bitangent = cross(sunDirection, tangent);

   float phi = 2.0 * RESTIR_PI * rand();
   float cosTheta = mix(cosThreshold, 1.0, rand());
   float sinTheta = sqrt(max(0.0, 1.0 - cosTheta * cosTheta));

   return normalize(tangent * cos(phi) * sinTheta + bitangent * sin(phi) * sinTheta + sunDirection * cosTheta);
}

void main() {
   ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
   vec2 uv = vec2(coord + 0.5) / vec2(viewWidth, viewHeight);

   if (uv.x >= 1.0 || uv.y >= 1.0) return;

   vec3 startNormal = texture(colortex7, uv).rgb;
   vec3 startPos = texture(colortex6, uv).rgb;

   if (dot(startNormal, startNormal) <= 0.25) {
      insertInitialSample(coord, Sample(startPos, vec3(0.0), startPos, vec3(0.0), vec3(0.0), 0u));
      return;
   }

   startNormal = normalize(startNormal);
   startPos += startNormal * 0.01;

   initRNG(coord, frameCounter, randomSeed);

   vec3 sunDirection = normalize((mat3(gbufferModelViewInverse) * sunPosition).xyz);

   vec3 radiance = vec3(0.0);
   vec3 throughput = vec3(1.0);

   vec3 rayOrigin = startPos;
   vec3 rayDirection = sampleUniformHemisphere(startNormal);
   vec3 initialRayDirection = rayDirection;

   vec3 firstHitPosition = vec3(0.0);
   vec3 firstHitNormal = vec3(0.0);
   bool hasFirstHit = false;

   #pragma unroll
   for (int i = 0; i < RESTIR_MAX_BOUNCES; i++) {
      RestirTraceResult result = traceBVHRestir(rayOrigin, rayDirection, false);
      throughput *= result.tint;

      if (!result.hit) {
         radiance += throughput * sampleSky(rayDirection, sunDirection);
         break;
      }

      vec3 hitPosition = rayOrigin + rayDirection * result.t;
      vec3 hitNormal = result.normal;

      vec3 albedo = result.albedo;
      float emission = result.emission;

      radiance += throughput * vec3(emission) * albedo;

      vec3 nextDirection = sampleUniformHemisphere(hitNormal);
      float cosTheta = max(dot(hitNormal, nextDirection), 0.0);

      throughput *= albedo * 2.0 * cosTheta;

      if (i == 0) {
         firstHitPosition = hitPosition;
         firstHitNormal = hitNormal;
         hasFirstHit = true;

         float sunCosThreshold = cos(RESTIR_SUN_HALF_ANGLE);
         float sunSolidAngle = max(2.0 * RESTIR_PI * (1.0 - sunCosThreshold), 1e-8);
         float pdfNEESun = 1.0 / sunSolidAngle;
         float pdfBRDF = uniformHemispherePdf();

         // if (sunDirection.y > 0.0) {
         //    vec3 sunSampleDir = sampleSunCap(sunDirection, sunCosThreshold);
         //    float sunNdotL = dot(firstHitNormal, sunSampleDir);

         //    if (sunNdotL > 0.0) {
         //       vec3 shadowTint = traceShadowTinted(firstHitPosition, sunSampleDir, RESTIR_SHADOW_MAX_DIST);

         //       if (shadowTint != vec3(0.0)) {
         //          float wNEE = pdfNEESun / (pdfNEESun + pdfBRDF);
         //          vec3 brdf = albedo / RESTIR_PI;
         //          radiance += brdf * sunNdotL
         //                * SUN_ILLUMINANCE * atmosphereTransmittance(sunSampleDir)
         //                * shadowTint * wNEE;
         //       }
         //    }
         // }
      }

      rayOrigin = hitPosition + hitNormal * 0.01;
      rayDirection = nextDirection;
   }

   vec3 samplePointPos = hasFirstHit ? firstHitPosition : startPos + initialRayDirection;
   vec3 samplePointNormal = hasFirstHit ? firstHitNormal : -initialRayDirection;

   Sample S = Sample(startPos, startNormal, samplePointPos, samplePointNormal, radiance, 0u);
   insertInitialSample(coord, S);
}
