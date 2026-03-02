#version 460

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f) uniform writeonly image2D colorimg1;
layout(rgba32f) uniform image2D colorimg5;

uniform float viewWidth;
uniform float viewHeight;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform vec3 shadowLightPosition;
uniform int frameCounter;
uniform bool hideGUI;
uniform bool firstPersonCamera;

uniform sampler2D colortex5;
uniform sampler2D blockAtlas;

uniform float near;

#include "/lib/storage.glsl"
#include "/lib/hploc.glsl"
#include "/lib/encoding.glsl"
#include "/lib/raytrace.glsl"

const int MAX_BOUNCES = 4;
const float SHADOW_MAX_DIST = 256.0;
const float SKY_BRIGHTNESS = 0.02;
const float SUN_BRIGHTNESS = 0.05;
const float PI = 3.14159265359;
const float GLASS_IOR = 1.5;

// ---- RNG ----

uint rngState;

void initRNG(ivec2 coord, int frame) {
   rngState = uint(coord.x * 1973 + coord.y * 9277 + frame * 26699) | 1u;
}

uint pcgHash() {
   uint state = rngState;
   rngState = rngState * 747796405u + 2891336453u;
   uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
   return (word >> 22u) ^ word;
}

float rand() {
   return float(pcgHash()) / 4294967295.0;
}

// ---- Sampling ----

vec3 sampleCosineHemisphere(vec3 normal) {
   float r1 = rand();
   float r2 = rand();
   float phi = 2.0 * PI * r1;
   float sinTheta = sqrt(r2);
   float cosTheta = sqrt(1.0 - r2);

   // Build tangent frame
   vec3 up = abs(normal.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
   vec3 tangent = normalize(cross(up, normal));
   vec3 bitangent = cross(normal, tangent);

   return normalize(tangent * cos(phi) * sinTheta + bitangent * sin(phi) * sinTheta + normal * cosTheta);
}

// ---- Fresnel ----

float fresnelSchlick(float cosTheta, float ior) {
   float r0 = (1.0 - ior) / (1.0 + ior);
   r0 *= r0;
   float c = 1.0 - cosTheta;
   return r0 + (1.0 - r0) * c * c * c * c * c;
}

// ---- Shading ----

vec3 getSkyColor(vec3 rd, vec3 lightDir) {
   float sun = max(dot(rd, lightDir), 0.0);
   float sky = max(rd.y * 0.5 + 0.5, 0.0);
   vec3 skyColor = mix(vec3(0.5, 0.6, 0.8), vec3(0.2, 0.4, 0.9), sky) * SKY_BRIGHTNESS;
   skyColor += vec3(1.0, 0.95, 0.8) * pow(sun, 256.0) * SUN_BRIGHTNESS;
   return skyColor;
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

   // Skip player model AABB in first person
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

   vec3 lightDir = normalize((gbufferModelViewInverse * vec4(0.01 * shadowLightPosition, 0.0)).xyz);

   initRNG(coord, frameCounter);

   // Primary ray
   TraceResult primaryHit = traceBVH(ro, rd);

   if (!primaryHit.hit) {
      vec3 sky = getSkyColor(rd, lightDir);

      vec4 prev = texture(colortex5, uv);
      float frameCount = prev.a;
      vec3 accumulated;
      float newCount;
      if (hideGUI == false) {
         accumulated = sky;
         newCount = 1.0;
      } else {
         newCount = frameCount + 1.0;
         accumulated = mix(prev.rgb, sky, 1.0 / newCount);
      }
      imageStore(colorimg5, coord, vec4(accumulated, newCount));
      return;
   }

   // Pathtracing state
   vec3 throughput = vec3(1.0);
   vec3 radiance = vec3(0.0);
   bool insideMedium = false;
   vec3 mediumColor = vec3(1.0);

   vec3 hitPos = ro;
   vec3 hitNormal = vec3(0.0);
   vec3 nextDir = rd;
   bool hasFixedDir = true;
   float shadowBias = 0.001;

   for (int bounce = 0; bounce < MAX_BOUNCES; bounce++) {
      vec3 origin = hitPos + hitNormal * shadowBias;

      // Choose ray direction: fixed (primary/refract/reflect) or cosine-weighted hemisphere
      vec3 bounceDir;
      if (hasFixedDir) {
         bounceDir = nextDir;
         hasFixedDir = false;
      } else {
         bounceDir = sampleCosineHemisphere(hitNormal);
      }

      TraceResult bounceHit = traceBVH(origin, bounceDir);

      if (!bounceHit.hit) {
         radiance += throughput * getSkyColor(bounceDir, lightDir);
         break;
      }

      // Handle translucent surface
      if (bounceHit.translucent) {
         vec4 glassTexColor;
         if (bounceHit.textureID == 0u) {
            glassTexColor = texture(blockAtlas, bounceHit.uv);
         } else {
            #ifdef ENTITY_TEXTURES
            glassTexColor = sampleEntityTexture(bounceHit.textureID, bounceHit.uv);
            #else
            glassTexColor = vec4(1.0);
            #endif
         }
         float opacity = glassTexColor.a;
         vec3 glassColor = pow(glassTexColor.rgb * glassTexColor.rgb, vec3(2.2)) * bounceHit.vertexData.rgb;
         vec3 hitPoint = origin + bounceDir * bounceHit.t;
         vec3 N = bounceHit.normal;

         float eta = insideMedium ? (GLASS_IOR / 1.0) : (1.0 / GLASS_IOR);
         float cosI = abs(dot(bounceDir, N));
         float fresnel = fresnelSchlick(cosI, GLASS_IOR);

         // Blend between glass (refract/reflect) and diffuse based on texture alpha
         float glassProb = 1.0 - opacity;

         if (rand() < glassProb) {
            // Glass path: Fresnel reflection or refraction
            if (rand() < fresnel) {
               nextDir = reflect(bounceDir, N);
               hitPos = hitPoint + N * 0.001;
               hitNormal = N;
            } else {
               vec3 refracted = refract(bounceDir, N, eta);

               if (dot(refracted, refracted) < 0.001) {
                  nextDir = reflect(bounceDir, N);
                  hitPos = hitPoint + N * 0.001;
                  hitNormal = N;
               } else {
                  nextDir = refracted;

                  if (insideMedium) {
                     vec3 absorption = -log(max(mediumColor, vec3(0.01)));
                     throughput *= exp(-absorption * bounceHit.t);
                     insideMedium = false;
                  } else {
                     insideMedium = true;
                     mediumColor = glassColor;
                  }

                  hitPos = hitPoint - N * 0.001;
                  hitNormal = -N;
               }
            }
            hasFixedDir = true;
            shadowBias = 0.001;
            continue;
         }
         // else: fall through to diffuse path below
      }

      // Apply Beer-Lambert if ray traveled through a medium to reach this opaque surface
      if (insideMedium) {
         vec3 absorption = -log(max(mediumColor, vec3(0.01)));
         throughput *= exp(-absorption * bounceHit.t);
         insideMedium = false;
      }

      // Get albedo at hit
      vec4 texColor;
      if (bounceHit.textureID == 0u) {
         texColor = texture(blockAtlas, bounceHit.uv);
      } else {
         #ifdef ENTITY_TEXTURES
         texColor = sampleEntityTexture(bounceHit.textureID, bounceHit.uv);
         #else
         texColor = vec4(1.0);
         #endif
      }
      vec3 bounceAlbedo = pow(texColor.rgb, vec3(2.2)) * bounceHit.vertexData.rgb;

      // Emissive contribution
      float emission = bounceHit.vertexData.a;
      if (emission > 0.0) {
         float emitter = pow(length(bounceAlbedo * 1.5), 5.6) * 0.5;
         radiance += throughput * bounceAlbedo * emitter * emission;
      }

      // Update throughput
      throughput *= bounceAlbedo;

      // Advance to hit point
      hitPos = origin + bounceDir * bounceHit.t;
      hitNormal = bounceHit.normal;
      shadowBias = 0.001;

      // Direct lighting: NEE with tinted soft shadows
      vec3 shadowOrigin = hitPos + hitNormal * shadowBias;
      float NdotL = max(dot(hitNormal, lightDir), 0.0);
      if (NdotL > 0.0) {
         vec3 up = abs(lightDir.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
         vec3 tangent = normalize(cross(up, lightDir));
         vec3 bitangent = cross(lightDir, tangent);

         float r = sqrt(rand()) * 0.007;
         float theta = rand() * 2.0 * PI;
         vec3 sampleDir = normalize(lightDir + (tangent * cos(theta) + bitangent * sin(theta)) * r);
         float sNdotL = max(dot(hitNormal, sampleDir), 0.0);

         if (sNdotL > 0.0) {
            vec3 shadowTint = traceShadowTinted(shadowOrigin, sampleDir, SHADOW_MAX_DIST);
            if (shadowTint != vec3(0.0)) {
               radiance += throughput * sNdotL * SUN_BRIGHTNESS * vec3(0.9, 0.93, 1.0) * shadowTint;
            }
         }
      }

      // Russian roulette after bounce 1
      if (bounce > 0) {
         float p = max(max(throughput.r, throughput.g), throughput.b);
         if (rand() > p) break;
         throughput /= p;
      }
   }

   vec4 prev = texture(colortex5, uv);
   float frameCount = prev.a;

   vec3 accumulated;
   float newCount;

   if (hideGUI == false) {
      accumulated = radiance;
      newCount = 1.0;
   } else {
      newCount = frameCount + 1.0;
      accumulated = mix(prev.rgb, radiance, 1.0 / newCount);
   }

   imageStore(colorimg5, coord, vec4(accumulated, newCount));
}
