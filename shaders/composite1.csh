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
uniform sampler2D normalAtlas;
uniform sampler2D specularAtlas;

uniform float near;

#include "/lib/storage.glsl"
#include "/lib/hploc.glsl"
#include "/lib/encoding.glsl"
#include "/lib/raytrace.glsl"

const int MAX_BOUNCES = 4;
const float SHADOW_MAX_DIST = 256.0;
const float SKY_BRIGHTNESS = 0.75;
const float SUN_BRIGHTNESS = 5.0;
const float PI = 3.14159265359;
const float GLASS_IOR = 1.5;

void computeTangentBasis(uint quadID, int triIndex, vec3 geomNormal, out vec3 tangent, out vec3 bitangent) {
   vec3 p0, p1, p2, p3;
   decodeQuadPositions(quadID, p0, p1, p2, p3);

   vec3 tp0 = p0;
   vec3 tp1 = (triIndex == 0) ? p1 : p2;
   vec3 tp2 = (triIndex == 0) ? p2 : p3;

   vec2 uv0 = quads[quadID].v1.uv;
   vec2 uv1 = (triIndex == 0) ? quads[quadID].v2.uv : quads[quadID].v3.uv;
   vec2 uv2 = (triIndex == 0) ? quads[quadID].v3.uv : quads[quadID].v4.uv;

   vec3 edge1 = tp1 - tp0;
   vec3 edge2 = tp2 - tp0;
   vec2 dUV1 = uv1 - uv0;
   vec2 dUV2 = uv2 - uv0;

   float denom = dUV1.x * dUV2.y - dUV1.y * dUV2.x;
   float handedness = (denom < 0.0) ? -1.0 : 1.0;
   vec3 t = (abs(denom) > 1e-8) ? (edge1 * dUV2.y - edge2 * dUV1.y) / denom : vec3(1.0, 0.0, 0.0);
   tangent = normalize(t - geomNormal * dot(geomNormal, t));
   bitangent = normalize(cross(geomNormal, tangent)) * handedness;
}

vec3 labPBRMetalF0(int metalID);

void decodeLabPBR(vec2 uv, vec3 geomNormal, uint quadID, int triIndex, uint textureID, vec3 baseColor, out vec3 normal, out float roughness, out float metallic, out vec3 F0, out float emission, out float ao) {
   if (textureID != 0u) {
      normal = geomNormal;
      roughness = 1.0;
      metallic = 0.0;
      F0 = vec3(0.04);
      emission = 0.0;
      ao = 1.0;
      return;
   }

   vec4 nTexSample = texture(normalAtlas, uv);
   vec2 nxy = nTexSample.rg * 2.0 - 1.0;
   nxy.y = -nxy.y;
   float nz = sqrt(max(1.0 - dot(nxy, nxy), 0.0));
   vec3 nTex = vec3(nxy, nz);
   ao = nTexSample.b;

   vec3 tangent;
   vec3 bitangent;
   computeTangentBasis(quadID, triIndex, geomNormal, tangent, bitangent);
   normal = normalize(tangent * nTex.x + bitangent * nTex.y + geomNormal * nTex.z);

   vec4 spec = texture(specularAtlas, uv);
   float perceptualSmoothness = spec.r;
   roughness = pow(1.0 - perceptualSmoothness, 2.0);

   float g = spec.g;
   float g255 = g * 255.0;
   if (g255 <= 229.5) {
      metallic = 0.0;
      F0 = vec3(clamp(g, 0.0, 229.0 / 255.0));
   } else {
      metallic = 1.0;
      int metalID = int(g255 + 0.5);
      if (metalID >= 230 && metalID <= 237) {
         F0 = labPBRMetalF0(metalID);
      } else {
         F0 = baseColor;
      }
   }

   emission = (spec.a >= (254.5 / 255.0)) ? 0.0 : spec.a;
}

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

float pow5(float x) {
   float x2 = x * x;
   return x2 * x2 * x;
}

vec3 fresnelSchlickVec(vec3 F0, float cosTheta) {
   return F0 + (1.0 - F0) * pow5(1.0 - cosTheta);
}

vec3 conductorF0(vec3 n, vec3 k) {
   vec3 n2 = n * n;
   vec3 k2 = k * k;
   vec3 num = (n2 - 2.0 * n + vec3(1.0)) + k2;
   vec3 den = (n2 + 2.0 * n + vec3(1.0)) + k2;
   return num / den;
}

vec3 labPBRMetalF0(int metalID) {
   if (metalID == 230) return conductorF0(vec3(2.9114, 2.9497, 2.5845), vec3(3.0893, 2.9318, 2.7670)); // iron
   if (metalID == 231) return conductorF0(vec3(0.18299, 0.42108, 1.3734), vec3(3.4242, 2.3459, 1.7704)); // gold
   if (metalID == 232) return conductorF0(vec3(1.3456, 0.96521, 0.61722), vec3(7.4746, 6.3995, 5.3031)); // aluminum
   if (metalID == 233) return conductorF0(vec3(3.1071, 3.1812, 2.3230), vec3(3.3314, 3.3291, 3.1350)); // chrome
   if (metalID == 234) return conductorF0(vec3(0.27105, 0.67693, 1.3164), vec3(3.6092, 2.6248, 2.2921)); // copper
   if (metalID == 235) return conductorF0(vec3(1.9100, 1.8300, 1.4400), vec3(3.5100, 3.4000, 3.1800)); // lead
   if (metalID == 236) return conductorF0(vec3(2.3757, 2.0847, 1.8453), vec3(4.2655, 3.7153, 3.1365)); // platinum
   if (metalID == 237) return conductorF0(vec3(0.15943, 0.14512, 0.13547), vec3(3.9291, 3.1900, 2.3808)); // silver
   return vec3(1.0);
}

float D_GGX(float NdotH, float roughness) {
   float a = max(roughness * roughness, 0.002);
   float a2 = a * a;
   float denom = (NdotH * NdotH) * (a2 - 1.0) + 1.0;
   return a2 / (PI * denom * denom);
}

float G_Smith(float NdotV, float NdotL, float roughness) {
   float r = roughness + 1.0;
   float k = (r * r) / 8.0;
   float gv = NdotV / (NdotV * (1.0 - k) + k);
   float gl = NdotL / (NdotL * (1.0 - k) + k);
   return gv * gl;
}

vec3 diffuseHammon(vec3 albedo, float roughness, float NdotV, float NdotL, float LdotH) {
   float energyBias = mix(0.0, 0.5, roughness);
   float energyFactor = mix(1.0, 1.0 / 1.51, roughness);
   float fd90 = energyBias + 2.0 * LdotH * LdotH * roughness;
   float lightScatter = 1.0 + (fd90 - 1.0) * pow5(1.0 - NdotL);
   float viewScatter = 1.0 + (fd90 - 1.0) * pow5(1.0 - NdotV);
   return albedo * (lightScatter * viewScatter * energyFactor) * (1.0 / PI);
}

vec3 evalBRDF(vec3 N, vec3 V, vec3 L, vec3 albedo, float roughness, float metallic, vec3 F0) {
   float NdotL = max(dot(N, L), 0.0);
   float NdotV = max(dot(N, V), 0.0);
   if (NdotL <= 0.0 || NdotV <= 0.0) return vec3(0.0);

   vec3 H = normalize(V + L);
   float NdotH = max(dot(N, H), 0.0);
   float VdotH = max(dot(V, H), 0.0);

   vec3 F = fresnelSchlickVec(F0, VdotH);
   float D = D_GGX(NdotH, roughness);
   float G = G_Smith(NdotV, NdotL, roughness);
   vec3 specTerm = (D * G) * F / max(4.0 * NdotV * NdotL, 1e-5);

   vec3 diffuseColor = albedo * (1.0 - metallic);
   vec3 diffTerm = diffuseHammon(diffuseColor, roughness, NdotV, NdotL, max(dot(L, H), 0.0)) * (vec3(1.0) - F);

   return diffTerm + specTerm;
}

vec3 sampleGGX(vec3 N, float roughness) {
   float a = max(roughness * roughness, 0.002);
   float a2 = a * a;

   float r1 = rand();
   float r2 = rand();
   float phi = 2.0 * PI * r1;
   float cosTheta = sqrt((1.0 - r2) / (1.0 + (a2 - 1.0) * r2));
   float sinTheta = sqrt(max(0.0, 1.0 - cosTheta * cosTheta));

   vec3 up = abs(N.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
   vec3 tangent = normalize(cross(up, N));
   vec3 bitangent = cross(N, tangent);

   return normalize(tangent * (cos(phi) * sinTheta) + bitangent * (sin(phi) * sinTheta) + N * cosTheta);
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

   initRNG(coord, frameCounter);

   vec2 jitter = vec2(rand(), rand()) - 0.5;
   vec2 rawUV = (vec2(coord) + 0.5) / vec2(viewWidth, viewHeight);
   vec2 uv = (vec2(coord) + 0.5 + jitter) / vec2(viewWidth, viewHeight);
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

   // Primary ray
   TraceResult primaryHit = traceBVH(ro, rd);

   if (!primaryHit.hit) {
      vec3 sky = getSkyColor(rd, lightDir);

      vec4 prev = texture(colortex5, rawUV);
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

      vec3 shadeNormal = bounceHit.normal;
      float roughness;
      float metallic;
      vec3 F0;
      float emissionMap;
      float ao;
      decodeLabPBR(bounceHit.uv, bounceHit.normal, bounceHit.quadID, bounceHit.triIndex, bounceHit.textureID, bounceAlbedo, shadeNormal, roughness, metallic, F0, emissionMap, ao);

      vec3 diffuseAlbedo = bounceAlbedo * ao;
      vec3 hitPoint = origin + bounceDir * bounceHit.t;
      vec3 N = shadeNormal;
      vec3 V = normalize(-bounceDir);
      vec3 surfaceThroughput = throughput;

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

         float eta = insideMedium ? (GLASS_IOR / 1.0) : (1.0 / GLASS_IOR);
         float cosI = abs(dot(bounceDir, N));
         float fresnel = fresnelSchlick(cosI, GLASS_IOR);

         // Blend between glass (refract/reflect) and diffuse based on texture alpha
         float glassProb = 1.0 - opacity;

         // Scale translucent diffuse by roughness to avoid overly opaque direct lighting
         diffuseAlbedo *= roughness;

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
         throughput *= exp(-absorption * max(bounceHit.t, 0.4));
         insideMedium = false;
      }

      // Emissive contribution
      float emission = max(bounceHit.vertexData.a, emissionMap);
      if (emission > 0.0) {
         float emitter = pow(length(bounceAlbedo * 1.5), 5.6) * 0.5;
         radiance += throughput * bounceAlbedo * emitter * emission * 2.0;
      }

      // Direct lighting: NEE with tinted soft shadows
      vec3 shadowOrigin = hitPoint + N * shadowBias;
      float NdotL = max(dot(N, lightDir), 0.0);
      if (NdotL > 0.0) {
         vec3 up = abs(lightDir.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
         vec3 tangent = normalize(cross(up, lightDir));
         vec3 bitangent = cross(lightDir, tangent);

         float r = sqrt(rand()) * 0.007;
         float theta = rand() * 2.0 * PI;
         vec3 sampleDir = normalize(lightDir + (tangent * cos(theta) + bitangent * sin(theta)) * r);
         float sNdotL = max(dot(N, sampleDir), 0.0);

         if (sNdotL > 0.0) {
            vec3 shadowTint = traceShadowTinted(shadowOrigin, sampleDir, SHADOW_MAX_DIST);
            if (shadowTint != vec3(0.0)) {
               vec3 brdf = evalBRDF(N, V, sampleDir, diffuseAlbedo, roughness, metallic, F0);
               radiance += surfaceThroughput * brdf * sNdotL * SUN_BRIGHTNESS * vec3(0.9, 0.93, 1.0) * shadowTint;
            }
         }
      }

      // Sample BRDF (Hammon diffuse + GGX)
      float specularProb = clamp(max(max(F0.r, F0.g), F0.b), 0.05, 0.95);
      if (rand() < specularProb) {
         vec3 H = sampleGGX(N, roughness);
         vec3 L = reflect(-V, H);

         float NdotL = max(dot(N, L), 0.0);
         if (NdotL <= 0.0) break;

         float NdotV = max(dot(N, V), 0.0);
         float NdotH = max(dot(N, H), 0.0);
         float VdotH = max(dot(V, H), 0.0);

         vec3 F = fresnelSchlickVec(F0, VdotH);
         float D = D_GGX(NdotH, roughness);
         float G = G_Smith(NdotV, NdotL, roughness);
         vec3 specBRDF = (D * G) * F / max(4.0 * NdotV * NdotL, 1e-5);

         float pdf = D * NdotH / max(4.0 * VdotH, 1e-5);
         throughput *= specBRDF * NdotL / max(pdf, 1e-5);

         nextDir = L;
         hasFixedDir = true;
      } else {
         vec3 L = sampleCosineHemisphere(N);

         float NdotL = max(dot(N, L), 0.0);
         float NdotV = max(dot(N, V), 0.0);

         vec3 H = normalize(V + L);
         float VdotH = max(dot(V, H), 0.0);

         vec3 F = fresnelSchlickVec(F0, VdotH);
         vec3 diffuseColor = diffuseAlbedo * (1.0 - metallic);
         vec3 diffBRDF = diffuseHammon(diffuseColor, roughness, NdotV, NdotL, max(dot(L, H), 0.0)) * (vec3(1.0) - F);

         float pdf = NdotL * (1.0 / PI);
         throughput *= diffBRDF * NdotL / max(pdf, 1e-5);

         nextDir = L;
         hasFixedDir = true;
      }

      // Advance to hit point
      hitPos = hitPoint;
      hitNormal = N;
      shadowBias = 0.001;

      // Russian roulette after bounce 1
      if (bounce > 0) {
         float p = max(max(throughput.r, throughput.g), throughput.b);
         if (rand() > p) break;
         throughput /= p;
      }
   }

   vec4 prev = texture(colortex5, rawUV);
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
