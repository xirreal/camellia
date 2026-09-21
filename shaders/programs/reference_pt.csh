layout(local_size_x = 8, local_size_y = 4, local_size_z = 1) in;

layout(rgba16f) uniform writeonly image2D colorimg1;
layout(rgba32f) uniform writeonly image2D colorimg5;

uniform float viewWidth;
uniform float viewHeight;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform vec3 sunPosition;
uniform vec3 shadowLightPosition;
uniform int frameCounter;
uniform sampler2D colortex5;
uniform sampler2D blockAtlas;
uniform sampler2D normalAtlas;
uniform sampler2D specularAtlas;
uniform int isEyeInWater;

uniform int randomSeed;

#include "/lib/core/storage.glsl"
#include "/lib/bvh/hploc.glsl"
#include "/lib/core/noise.glsl"
#define BVH_WG_SIZE 32
#define CONTROL_BUFFER_QUALIFIERS restrict
#include "/lib/bvh/raytrace.glsl"
#include "/lib/atmosphere/atmosphere.glsl"
#include "/lib/pt/sellmeier.glsl"
#include "/lib/core/rand.glsl"
#include "/lib/pt/materials.glsl"
#include "/lib/pt/brdf.glsl"

const int MAX_BOUNCES = 8;
const float SHADOW_MAX_DIST = 256.0;

#define DOF_ENABLED
#define DOF_AUTOFOCUS
#define DOF_FOCAL_LENGTH 35.0   //[17.0 24.0 35.0 50.0 85.0 105.0 135.0 200.0 250.0 300.0]
#define DOF_FSTOP 16.0           //[1.4 1.8 2.0 2.4 2.8 4.0 5.6 8.0 11.0 16.0]
#define DOF_FOCUS_DISTANCE 5.0  //[1.0 2.0 3.0 4.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 100.0]
#define DOF_SENSOR_WIDTH 36.0   //[23.5 28.7 36.0 44.0 53.0]
#define DOF_BLADES 0            //[0 3 4 5 6 7 8 9 10 11 12 13 14 15 16]

const float WATER_IOR = 1.33;
const float WATER_WAVE_STRENGTH = 0.1;

#define GLASS_CAUSTICS
#define GLASS_CAUSTIC_DISPERSION
#define GLASS_CAUSTIC_SAMPLES 1        //[0 1 2 4]
#define GLASS_CAUSTIC_CONE_DEGREES 4.0 //[1.0 2.0 4.0 8.0 12.0 16.0]
#define GLASS_CAUSTIC_FILTER 4.0       //[1.0 2.0 4.0 8.0]
#define GLASS_CAUSTIC_CLAMP 12.0       //[0.0 4.0 8.0 12.0 24.0 48.0]

const int GLASS_SHADOW_MAX_BENDS = 4;
const float RAY_ORIGIN_BIAS = 1e-4;
const float REFRACT_TIR_EPSILON = 1e-8;
const float GLASS_NORMAL_REFRACTION_STRENGTH = 0.35;
const float GLASS_REFERENCE_WAVELENGTH = 535.0;
const float SPECULAR_GUIDE_MAX_ROUGHNESS = 0.65;

struct SunVisibility {
   vec3 transmittance;
   vec3 finalDir;
   bool visible;
   bool refracted;
};

vec3 offsetRayOrigin(vec3 p, vec3 n) {
   return p + n * RAY_ORIGIN_BIAS;
}

bool refractWasTIR(vec3 refracted) {
   return dot(refracted, refracted) <= REFRACT_TIR_EPSILON;
}

vec3 sampleConeUniform(vec3 axis, float cosMax, out float pdf) {
   float u = rand();
   float v = rand();
   float cosTheta = mix(cosMax, 1.0, u);
   float sinTheta = sqrt(max(1.0 - cosTheta * cosTheta, 0.0));
   float phi = 2.0 * PI * v;

   vec3 up = abs(axis.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
   vec3 tangent = normalize(cross(up, axis));
   vec3 bitangent = cross(axis, tangent);

   pdf = 1.0 / max(2.0 * PI * (1.0 - cosMax), 1e-8);
   return normalize(tangent * (cos(phi) * sinTheta) + bitangent * (sin(phi) * sinTheta) + axis * cosTheta);
}

vec3 sampleSunDisk(vec3 lightDir, float sunCosThreshold) {
   float pdfUnused;
   return sampleConeUniform(lightDir, sunCosThreshold, pdfUnused);
}

vec3 waterCausticSearchAxis(vec3 lightDir, bool startInsideWater) {
   if (!startInsideWater || lightDir.y <= 0.0) return lightDir;

   vec3 flatWaterIncident = refract(-lightDir, vec3(0.0, 1.0, 0.0), 1.0 / WATER_IOR);
   if (refractWasTIR(flatWaterIncident)) return lightDir;

   return normalize(-flatWaterIncident);
}

float glassReferenceIOR() {
   vec3 B, C;
   glassCoeffs_N_BK7(B, C);
   return sellmeierIOR(GLASS_REFERENCE_WAVELENGTH, B, C);
}

float waterSpectralIOR(float wavelengthNm) {
   const float WATER_CAUCHY_B = 0.003;
   float wavelengthUm = wavelengthNm * 1e-3;
   float referenceUm = GLASS_REFERENCE_WAVELENGTH * 1e-3;
   return WATER_IOR + WATER_CAUCHY_B * (1.0 / (wavelengthUm * wavelengthUm) - 1.0 / (referenceUm * referenceUm));
}

vec3 causticSpectralSample(out float glassChannelIOR, out float waterChannelIOR) {
   int wl = int(rand() * float(GLASS_BIN_COUNT));
   wl = min(wl, GLASS_BIN_COUNT - 1);

   vec3 B, C;
   glassCoeffs_N_BK7(B, C);
   glassChannelIOR = sellmeierIOR(GLASS_WL_BIN[wl], B, C);
   waterChannelIOR = waterSpectralIOR(GLASS_WL_BIN[wl]);
   return GLASS_MASK_BIN[wl] * float(GLASS_BIN_COUNT);
}

vec4 sampleHitTexture(TraceResult hit) {
   if (hit.textureID == 0u) {
      return texture(blockAtlas, hit.uv);
   }

   #ifdef ENTITY_TEXTURES
   return sampleEntityTexture(hit.textureID, hit.uv);
   #else
   return vec4(1.0);
   #endif
}

vec3 refractiveShadeNormal(TraceResult hit, vec3 incidentDir, vec3 baseColor) {
   vec3 shadeNormal = hit.normal;
   float roughness;
   float metallic;
   vec3 F0;
   vec3 F82tint;
   float emissionMap;
   float ao;
   float sssAmount;

   decodeLabPBR(hit.uv, hit.normal, hit.quadID, hit.triIndex, hit.textureID, baseColor,
      shadeNormal, roughness, metallic, F0, F82tint, emissionMap, ao, sssAmount);

   if (dot(shadeNormal, incidentDir) > 0.0) shadeNormal = -shadeNormal;

   float normalWeight = smoothstep(0.05, 0.25, -dot(hit.normal, incidentDir)) * GLASS_NORMAL_REFRACTION_STRENGTH;
   return normalize(mix(hit.normal, shadeNormal, normalWeight));
}

SunVisibility traceSunVisibility(vec3 ro, vec3 rd, float maxDist, vec3 lightDir, float sunCosThreshold, float glassIOR, float waterIOR, vec3 spectralWeight, bool startInsideWater) {
   SunVisibility res;
   res.transmittance = vec3(1.0);
   res.finalDir = rd;
   res.visible = true;
   res.refracted = false;

   vec3 pos = ro;
   vec3 dir = rd;
   float traveled = 0.0;
   bool insideGlass = false;
   bool insideWaterShadow = startInsideWater;
   bool spectralApplied = false;
   vec3 mediumColor = vec3(1.0);

   for (int i = 0; i < GLASS_SHADOW_MAX_BENDS; i++) {
      TraceResult hit = traceBVH(pos, dir);
      if (!hit.hit || traveled + hit.t >= maxDist) {
         float remaining = max(maxDist - traveled, 0.0);
         if (insideWaterShadow) {
            res.transmittance *= exp(-WATER_ABSORPTION * remaining);
         } else if (insideGlass) {
            vec3 absorption = -log(max(mediumColor, vec3(0.01)));
            res.transmittance *= exp(-absorption * remaining);
         }
         res.finalDir = dir;
         res.visible = dot(dir, lightDir) >= sunCosThreshold;
         return res;
      }

      vec3 hitPoint = pos + dir * hit.t;
      traveled += hit.t;

      if (insideWaterShadow) {
         res.transmittance *= exp(-WATER_ABSORPTION * hit.t);
      } else if (insideGlass) {
         vec3 absorption = -log(max(mediumColor, vec3(0.01)));
         res.transmittance *= exp(-absorption * max(hit.t, 0.02));
      }

      if (!hit.translucent) {
         res.visible = false;
         res.transmittance = vec3(0.0);
         return res;
      }

      vec4 texColor = sampleHitTexture(hit);
      vec3 texTint = mix(vec3(1.0), texColor.rgb, step(alphaTestRef, texColor.a));
      vec3 surfaceTint = pow(max(texTint * hit.vertexData.rgb, vec3(0.0)), vec3(2.2));
      float transparency = clamp(1.0 - texColor.a, 0.0, 1.0);

      if (hit.waterSurface) {
         vec3 waveN = waterWaveNormal(hitPoint + (control.sceneFrozen == 1u ? control.frozenCameraPos.xyz : cameraPosition), 0.0, WATER_WAVE_STRENGTH);
         float sign = dot(hit.normal, vec3(0.0, 1.0, 0.0)) >= 0.0 ? 1.0 : -1.0;
         vec3 N = normalize(vec3(waveN.x * sign, waveN.y * sign, waveN.z * sign));
         if (dot(N, dir) > 0.0) N = -N;

         float eta = insideWaterShadow ? waterIOR : (1.0 / waterIOR);
         vec3 refracted = refract(dir, N, eta);
         if (refractWasTIR(refracted)) {
            res.visible = false;
            res.transmittance = vec3(0.0);
            return res;
         }

         float fresnel = fresnelSchlick(abs(dot(dir, N)), waterIOR);
         res.transmittance *= 1.0 - fresnel;
         if (!spectralApplied) {
            res.transmittance *= spectralWeight;
            spectralApplied = true;
         }
         insideWaterShadow = !insideWaterShadow;
         res.refracted = true;
         dir = normalize(refracted);
         pos = offsetRayOrigin(hitPoint, -N);
         continue;
      }

      if (transparency <= 1e-4) {
         res.visible = false;
         res.transmittance = vec3(0.0);
         return res;
      }

      vec3 N = refractiveShadeNormal(hit, dir, surfaceTint);
      float eta = insideGlass ? glassIOR : (1.0 / glassIOR);
      vec3 refracted = refract(dir, N, eta);
      if (refractWasTIR(refracted)) {
         res.visible = false;
         res.transmittance = vec3(0.0);
         return res;
      }

      float fresnel = fresnelSchlick(abs(dot(dir, N)), glassIOR);
      res.transmittance *= surfaceTint * transparency * (1.0 - fresnel);
      if (!spectralApplied) {
         res.transmittance *= spectralWeight;
         spectralApplied = true;
      }

      if (insideGlass) {
         insideGlass = false;
      } else {
         insideGlass = true;
         mediumColor = max(surfaceTint, vec3(0.01));
      }

      res.refracted = true;
      dir = normalize(refracted);
      pos = offsetRayOrigin(hitPoint, -N);
   }

   res.visible = false;
   res.transmittance = vec3(0.0);
   return res;
}

vec3 clampCausticContribution(vec3 c) {
   if (GLASS_CAUSTIC_CLAMP <= 0.0) return c;
   float m = max(max(c.r, c.g), c.b);
   if (m <= GLASS_CAUSTIC_CLAMP) return c;
   return c * (GLASS_CAUSTIC_CLAMP / max(m, 1e-5));
}

void main() {
   ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
   if (coord.x >= int(viewWidth) || coord.y >= int(viewHeight)) return;

   initRNG(coord, frameCounter, randomSeed);

   vec2 jitter = vec2(rand(), rand()) - 0.5;
   vec2 rawUV = (vec2(coord) + 0.5) / vec2(viewWidth, viewHeight);
   vec2 uv = (vec2(coord) + 0.5 + jitter) / vec2(viewWidth, viewHeight);
   vec2 ndc = uv * 2.0 - 1.0;

   mat4 projInv = control.sceneFrozen == 1u ? control.frozenProjInv : gbufferProjectionInverse;
   mat4 mvInv = control.sceneFrozen == 1u ? control.frozenModelViewInv : gbufferModelViewInverse;
   vec3 lightPos = control.sceneFrozen == 1u ? control.frozenLightPos.xyz : shadowLightPosition;

   vec4 clipDir = vec4(ndc, 1.0, 1.0);
   vec4 viewDir = projInv * clipDir;
   viewDir.xyz /= viewDir.w;
   vec3 rd = normalize((mat3(mvInv) * viewDir.xyz));
   vec3 ro = mvInv[3].xyz;

   #if defined(DOF_ENABLED) && defined(DOF_AUTOFOCUS)
   {
      ivec2 center = ivec2(int(viewWidth) / 2, int(viewHeight) / 2);
      if (coord == center) {
         vec2 centerNDC = vec2(center + 0.5) / vec2(viewWidth, viewHeight) * 2.0 - 1.0;
         vec4 centerClip = vec4(centerNDC, 1.0, 1.0);
         vec4 centerView = projInv * centerClip;
         centerView.xyz /= centerView.w;
         vec3 centerRd = normalize(mat3(mvInv) * centerView.xyz);
         vec3 centerRo = mvInv[3].xyz;

         TraceResult centerHit = traceBVH(centerRo, centerRd, true);
         float newDist = centerHit.hit ? centerHit.t : far;

         control.autofocusDist = newDist;
      }
   }
   #endif

   #ifdef DOF_ENABLED
   {
      float focalLength_m = DOF_FOCAL_LENGTH * 0.001;
      float sensorWidth_m = DOF_SENSOR_WIDTH * 0.001;
      float apertureDiam = focalLength_m / DOF_FSTOP;
      float lensRadius = apertureDiam * 0.5;

      float focusDist;
      #ifdef DOF_AUTOFOCUS
      focusDist = max(control.autofocusDist, 0.1);
      #else
      focusDist = DOF_FOCUS_DISTANCE;
      #endif

      focusDist = max(focusDist, 0.1);

      vec3 focalPoint = ro + rd * (focusDist / max(dot(rd, normalize(mat3(mvInv) * vec3(0.0, 0.0, -1.0))), 0.001));

      float physicalHalfTanFOV = sensorWidth_m / (2.0 * focalLength_m);
      float mcHalfTanFOV = projInv[0][0]; // = 1/P[0][0] = tan(halfFOV_x)
      float worldLensRadius = lensRadius * mcHalfTanFOV / physicalHalfTanFOV;

      float r1 = rand();
      float r2 = rand();
      float angle, radius;
      #if DOF_BLADES > 2
      {
         float bladeAngle = 2.0 * PI / float(DOF_BLADES);
         int sector = int(r1 * float(DOF_BLADES));
         float sectorFrac = r1 * float(DOF_BLADES) - float(sector);

         float u = sqrt(sectorFrac);
         float v = r2 * u;
         u = 1.0 - u;

         float a0 = float(sector) * bladeAngle;
         float a1 = a0 + bladeAngle;
         float px = u * cos(a0) + v * cos(a1);
         float py = u * sin(a0) + v * sin(a1);

         angle = atan(py, px);
         radius = sqrt(px * px + py * py) * worldLensRadius;
      }
      #else
      {
         angle = 2.0 * PI * r1;
         radius = sqrt(r2) * worldLensRadius;
      }
      #endif

      vec3 camRight = normalize(vec3(mvInv[0]));
      vec3 camUp = normalize(vec3(mvInv[1]));
      vec3 lensOffset = camRight * (cos(angle) * radius) + camUp * (sin(angle) * radius);

      ro += lensOffset;
      rd = normalize(focalPoint - ro);
   }
   #endif

   vec3 lightDir = normalize((mvInv * vec4(lightPos, 0.0)).xyz);

   vec3 sunPosForFrame = control.sceneFrozen == 1u ? control.frozenSunPos.xyz : sunPosition;
   vec3 worldSunDir = normalize((mvInv * vec4(sunPosForFrame, 0.0)).xyz);
   bool isDay = worldSunDir.y >= 0.0;
   vec3 lightIlluminance = isDay ? SUN_ILLUMINANCE : MOON_ILLUMINANCE;
   vec3 lightTint = isDay ? vec3(1.0, 0.95, 0.8) : vec3(0.7, 0.85, 1.0);
   float referenceGlassIOR = glassReferenceIOR();

   TraceResult primaryHit = traceBVH(ro, rd, true);

   if (!primaryHit.hit) {
      vec3 sky = sampleSky(rd, worldSunDir);

      vec4 prev = texture(colortex5, rawUV);
      float frameCount = prev.a;
      vec3 accumulated;
      float newCount;
      if (control.sceneFrozen != 1u) {
         accumulated = sky;
         newCount = 1.0;
      } else {
         newCount = frameCount + 1.0;
         accumulated = mix(prev.rgb, sky, 1.0 / newCount);
      }
      imageStore(colorimg5, coord, vec4(accumulated, newCount));
      return;
   }

   vec3 throughput = vec3(1.0);
   vec3 radiance = vec3(0.0);
   bool insideMedium = false;
   bool insideWater = false;
   vec3 mediumColor = vec3(1.0);

   vec3 rayOrigin = ro;
   vec3 hitNormal = vec3(0.0);
   vec3 nextDir = rd;
   bool hasFixedDir = true;
   TraceResult cachedHit = primaryHit;
   bool hasCachedHit = true;

   if (isEyeInWater == 1) {
      insideMedium = true;
      insideWater = true;
   }

   for (int bounce = 0; bounce < MAX_BOUNCES; bounce++) {
      vec3 origin = rayOrigin;

      vec3 bounceDir;
      if (hasFixedDir) {
         bounceDir = nextDir;
         hasFixedDir = false;
      } else {
         bounceDir = sampleCosineHemisphere(hitNormal);
         hasCachedHit = false;
      }

      TraceResult bounceHit;
      if (hasCachedHit) {
         bounceHit = cachedHit;
         hasCachedHit = false;
      } else {
         bounceHit = traceBVH(origin, bounceDir);
      }

      if (!bounceHit.hit) {
         radiance += throughput * sampleSky(bounceDir, worldSunDir);
         break;
      }

      vec4 texColor = sampleHitTexture(bounceHit);
      vec3 bounceAlbedo = sampleHitAlbedo(bounceHit, origin, bounceDir, texColor);

      vec3 shadeNormal = bounceHit.normal;
      float roughness;
      float metallic;
      vec3 F0;
      vec3 F82tint;
      float emissionMap;
      float ao;
      float sssAmount;
      decodeLabPBR(bounceHit.uv, bounceHit.normal, bounceHit.quadID, bounceHit.triIndex, bounceHit.textureID, bounceAlbedo, shadeNormal, roughness, metallic, F0, F82tint, emissionMap, ao, sssAmount);

      vec3 diffuseAlbedo = bounceAlbedo * ao;
      vec3 hitPoint = origin + bounceDir * bounceHit.t;
      vec3 N = shadeNormal;
      vec3 V = normalize(-bounceDir);
      vec3 surfaceThroughput = throughput;
      bool shadowStartsInWater = insideMedium && insideWater;

      float d = dot(N, V);
      N = normalize(mix(N, bounceHit.normal, 1.0 - smoothstep(0.0, 0.05, d)));

      if (bounceHit.translucent) {
         if (bounceHit.waterSurface) {
            vec3 waveN = waterWaveNormal(hitPoint + (control.sceneFrozen == 1u ? control.frozenCameraPos.xyz : cameraPosition), 0.0, WATER_WAVE_STRENGTH);
            float sign = dot(N, vec3(0.0, 1.0, 0.0)) >= 0.0 ? 1.0 : -1.0;
            N = normalize(vec3(waveN.x * sign, waveN.y * sign, waveN.z * sign));

            float eta = insideWater ? (WATER_IOR / 1.0) : (1.0 / WATER_IOR);
            float cosI = abs(dot(bounceDir, N));
            float fresnel = fresnelSchlick(cosI, WATER_IOR);

            vec3 refracted = refract(bounceDir, N, eta);
            bool tir = refractWasTIR(refracted);

            if (tir || rand() < fresnel) {
               nextDir = reflect(bounceDir, N);

               if (insideWater) {
                  throughput *= exp(-WATER_ABSORPTION * bounceHit.t);
               }
               rayOrigin = offsetRayOrigin(hitPoint, N);
               hitNormal = N;
            } else {
               nextDir = normalize(refracted);

               if (insideWater) {
                  throughput *= exp(-WATER_ABSORPTION * bounceHit.t);
                  insideWater = false;
                  insideMedium = false;
               } else {
                  insideWater = true;
                  insideMedium = true;
                  mediumColor = vec3(1.0);
               }

               rayOrigin = offsetRayOrigin(hitPoint, -N);
               hitNormal = -N;
            }
            hasFixedDir = true;
            continue;
         } else {
            float opacity = texColor.a;
            vec3 glassTexTint = mix(vec3(1.0), texColor.rgb * texColor.rgb, step(alphaTestRef, opacity));
            vec3 glassColor = pow(max(glassTexTint * bounceHit.vertexData.rgb, vec3(0.0)), vec3(2.2));

            int wl = int(rand() * float(GLASS_BIN_COUNT));
            wl = min(wl, GLASS_BIN_COUNT - 1);
            vec3 B, C;
            glassCoeffs_N_BK7(B, C);
            float channelIOR = sellmeierIOR(GLASS_WL_BIN[wl], B, C);
            vec3 channelMask = GLASS_MASK_BIN[wl] * float(GLASS_BIN_COUNT);

            float eta = insideMedium ? (channelIOR / 1.0) : (1.0 / channelIOR);
            float cosI = abs(dot(bounceDir, N));
            float fresnel = fresnelSchlick(cosI, channelIOR);
            float glassProb = 1.0 - opacity;

            diffuseAlbedo *= roughness;

            if (rand() < glassProb) {
               vec3 refracted = refract(bounceDir, N, eta);
               bool tir = refractWasTIR(refracted);

               if (tir || rand() < fresnel) {
                  nextDir = reflect(bounceDir, N);

                  if (insideMedium) {
                     vec3 absorption = -log(max(mediumColor, vec3(0.01)));
                     throughput *= exp(-absorption * bounceHit.t);
                  }
                  rayOrigin = offsetRayOrigin(hitPoint, N);
                  hitNormal = N;
               } else {
                  nextDir = normalize(refracted);
                  throughput *= channelMask;

                  if (insideMedium) {
                     vec3 absorption = -log(max(mediumColor, vec3(0.01)));
                     throughput *= exp(-absorption * bounceHit.t);
                     insideMedium = false;
                  } else {
                     insideMedium = true;
                     mediumColor = glassColor;
                  }

                  rayOrigin = offsetRayOrigin(hitPoint, -N);
                  hitNormal = -N;
               }
               hasFixedDir = true;
               continue;
            }
         }
      }

      if (insideMedium) {
         if (insideWater) {
            throughput *= exp(-WATER_ABSORPTION * bounceHit.t);
            insideWater = false;
         } else {
            vec3 absorption = -log(max(mediumColor, vec3(0.01)));
            throughput *= exp(-absorption * max(bounceHit.t, 0.4));
         }
         insideMedium = false;
      }

      #ifdef MC_TEXTURE_FORMAT_LAB_PBR_1_3
      float emission = emissionMap * 20.0;
      // glowing text
      if (quadBlockID(bounceHit.quadID) == 3u)
         emission = max(emission, pow(length(bounceAlbedo * 1.5), 2.2) * bounceHit.vertexData.a * 0.2);
      #else
      float emission = pow(length(bounceAlbedo * 1.5), 2.2) * bounceHit.vertexData.a * 0.2;
      #endif
      if (emission > 0.0) {
         radiance += throughput * bounceAlbedo * emission;
      }

      vec3 shadowOrigin = offsetRayOrigin(hitPoint, N);
      vec3 N_geom = bounceHit.normal;
      float NdotL_direct = dot(N, lightDir);
      bool frontLit = NdotL_direct > 0.0;
      bool backLit = sssAmount > 0.0 && NdotL_direct < 0.0;

      float NdotV = max(dot(N, V), 1e-5);
      vec3 kS;
      vec3 specMSFactor;
      specEnergyTerms(F0, NdotV, roughness, kS, specMSFactor);
      float specularProb = clamp(max(max(kS.r, kS.g), kS.b), 0.05, 0.95);

      #ifdef MC_TEXTURE_FORMAT_LAB_PBR_1_3
      float sunHalfAngle = 0.00465 + sssAmount * 0.01;
      #else
      float sunHalfAngle = 0.00465 + sssAmount * 0.1;
      #endif
      float sunCosThreshold = cos(sunHalfAngle);
      float sunSolidAngle = max(2.0 * PI * (1.0 - sunCosThreshold), 1e-8);
      float pdfNEE_sun = 1.0 / sunSolidAngle;
      vec3 sunRadiance = lightIlluminance / sunSolidAngle;

      float specularGuideSampleCount = 0.0;
      #if defined(GLASS_CAUSTICS) && GLASS_CAUSTIC_SAMPLES > 0
      bool specularGuideEnabled = frontLit && roughness <= SPECULAR_GUIDE_MAX_ROUGHNESS;
      if (specularGuideEnabled) {
         specularGuideSampleCount = float(GLASS_CAUSTIC_SAMPLES);
      }
      #endif

      // ---- Next-event estimation toward the sun (with balance-heuristic MIS) ----
      if (frontLit || backLit) {
         vec3 sampleDir = sampleSunDisk(lightDir, sunCosThreshold);
         float sNdotL = dot(N, sampleDir);
         bool ngVisible = dot(N_geom, sampleDir) > 0.0;

         if (frontLit && sNdotL > 0.0 && ngVisible) {
            SunVisibility shadow = traceSunVisibility(shadowOrigin, sampleDir, SHADOW_MAX_DIST, lightDir, sunCosThreshold, referenceGlassIOR, WATER_IOR, vec3(1.0), shadowStartsInWater);
            if (shadow.visible) {
               vec3 brdf = evalBRDF(N, V, sampleDir, diffuseAlbedo, roughness, metallic, F0, F82tint);
               // Marginal BRDF pdf at the NEE direction (for balance heuristic).
               float pdfBRDF_at = specularProb * pdfGGXVNDFL(N, V, sampleDir, roughness)
                     + (1.0 - specularProb) * sNdotL / PI;
               float pdfSpecGuide_at = pdfGGXVNDFL(N, V, sampleDir, roughness);
               float wNEE = pdfNEE_sun / (pdfNEE_sun + pdfBRDF_at + specularGuideSampleCount * pdfSpecGuide_at);
               radiance += wNEE * surfaceThroughput * brdf * sNdotL
                     * lightIlluminance * lightTint * shadow.transmittance
                     * atmosphereTransmittance(shadow.finalDir);
            }
         }

         if (backLit) {
            vec3 sssOrigin = offsetRayOrigin(hitPoint, -N);
            SunVisibility shadow = traceSunVisibility(sssOrigin, sampleDir, SHADOW_MAX_DIST, lightDir, sunCosThreshold, referenceGlassIOR, WATER_IOR, vec3(1.0), shadowStartsInWater);
            if (shadow.visible) {
               float wrap = max(-sNdotL, 0.0);
               vec3 sssColor = diffuseAlbedo * (1.0 - metallic);
               radiance += surfaceThroughput * sssColor * (sssAmount * wrap * (1.0 / PI))
                     * lightIlluminance * lightTint * shadow.transmittance
                     * atmosphereTransmittance(shadow.finalDir);
            }
         }
      }

      #if defined(GLASS_CAUSTICS) && GLASS_CAUSTIC_SAMPLES > 0
      if (specularGuideEnabled) {
         for (int guideSample = 0; guideSample < GLASS_CAUSTIC_SAMPLES; guideSample++) {
            vec3 H = sampleGGXHalfWorld(N, V, roughness);
            vec3 guideDir = reflect(-V, H);
            float gNdotL = dot(N, guideDir);

            if (gNdotL > 0.0 && dot(N_geom, guideDir) > 0.0 && dot(guideDir, lightDir) >= sunCosThreshold) {
               float pdfSpecGuide = pdfGGXVNDFL(N, V, guideDir, roughness);
               if (pdfSpecGuide > 0.0) {
                  SunVisibility shadow = traceSunVisibility(shadowOrigin, guideDir, SHADOW_MAX_DIST, lightDir, sunCosThreshold, referenceGlassIOR, WATER_IOR, vec3(1.0), shadowStartsInWater);
                  if (shadow.visible) {
                     vec3 brdf = evalBRDF(N, V, guideDir, diffuseAlbedo, roughness, metallic, F0, F82tint);
                     float pdfBRDF_at = specularProb * pdfSpecGuide
                           + (1.0 - specularProb) * gNdotL / PI;
                     float wGuide = (specularGuideSampleCount * pdfSpecGuide)
                           / (pdfNEE_sun + pdfBRDF_at + specularGuideSampleCount * pdfSpecGuide);

                     radiance += wGuide * surfaceThroughput * brdf * gNdotL
                           * sunRadiance * lightTint * shadow.transmittance
                           * atmosphereTransmittance(shadow.finalDir)
                           / (pdfSpecGuide * specularGuideSampleCount);
                  }
               }
            }
         }
      }

      vec3 causticAxis = waterCausticSearchAxis(lightDir, shadowStartsInWater);
      if (dot(N, causticAxis) > 0.0) {
         float causticHalfAngle = max(sunHalfAngle, GLASS_CAUSTIC_CONE_DEGREES * (PI / 180.0));
         float causticCosThreshold = cos(causticHalfAngle);
         float causticSolidAngle = max(2.0 * PI * (1.0 - causticCosThreshold), 1e-8);
         float causticPdf = 1.0 / causticSolidAngle;

         float causticSunHalfAngle = max(sunHalfAngle, sunHalfAngle * GLASS_CAUSTIC_FILTER);
         float causticSunCosThreshold = cos(causticSunHalfAngle);
         float causticSunSolidAngle = max(2.0 * PI * (1.0 - causticSunCosThreshold), 1e-8);
         vec3 causticSunRadiance = lightIlluminance / causticSunSolidAngle;

         for (int causticSample = 0; causticSample < GLASS_CAUSTIC_SAMPLES; causticSample++) {
            float sampledPdf;
            vec3 causticDir = sampleConeUniform(causticAxis, causticCosThreshold, sampledPdf);
            float cNdotL = dot(N, causticDir);

            if (cNdotL > 0.0 && dot(N_geom, causticDir) > 0.0) {
               float glassChannelIOR = referenceGlassIOR;
               float waterChannelIOR = WATER_IOR;
               vec3 spectralWeight = vec3(1.0);
               #ifdef GLASS_CAUSTIC_DISPERSION
               spectralWeight = causticSpectralSample(glassChannelIOR, waterChannelIOR);
               #endif
               SunVisibility caustic = traceSunVisibility(shadowOrigin, causticDir, SHADOW_MAX_DIST, lightDir, causticSunCosThreshold, glassChannelIOR, waterChannelIOR, spectralWeight, shadowStartsInWater);
               float minCausticBend = max(sunHalfAngle, 0.002);
               bool bentPath = dot(caustic.finalDir, causticDir) < cos(minCausticBend);

               if (caustic.visible && caustic.refracted && bentPath) {
                  vec3 brdf = evalBRDF(N, V, causticDir, diffuseAlbedo, roughness, metallic, F0, F82tint);
                  float pdfBRDF_at = specularProb * pdfGGXVNDFL(N, V, causticDir, roughness)
                        + (1.0 - specularProb) * cNdotL / PI;
                  float wCaustic = causticPdf / (causticPdf + pdfBRDF_at);

                  vec3 causticContribution = wCaustic * surfaceThroughput * brdf * cNdotL
                        * causticSunRadiance * lightTint * caustic.transmittance
                        * atmosphereTransmittance(caustic.finalDir)
                        / (sampledPdf * float(GLASS_CAUSTIC_SAMPLES));
                  radiance += clampCausticContribution(causticContribution);
               }
            }
         }
      }
      #endif

      vec3 L_sample;
      float NdotL_sample;
      float pdfBRDF_marginal;
      bool sampleValid;

      if (rand() < specularProb) {
         vec3 H = sampleGGXHalfWorld(N, V, roughness);
         L_sample = reflect(-V, H);
         NdotL_sample = dot(N, L_sample);

         sampleValid = NdotL_sample > 0.0 && dot(N_geom, L_sample) > 0.0;
         if (!sampleValid) break;

         float VdotH = max(dot(V, H), 1e-5);
         float a = max(roughness * roughness, 0.002);
         float a2 = a * a;

         vec3 F = fresnelF82Tint(F0, F82tint, VdotH);
         float lambdaV = smithLambdaGGX(NdotV, a2);
         float lambdaL = smithLambdaGGX(NdotL_sample, a2);
         float G2_over_G1V = (1.0 + lambdaV) / max(1.0 + lambdaV + lambdaL, 1e-5);
         vec3 specWeight = F * G2_over_G1V * specMSFactor;

         throughput *= specWeight / specularProb;

         pdfBRDF_marginal = specularProb * pdfGGXVNDFL(N, V, L_sample, roughness)
               + (1.0 - specularProb) * max(NdotL_sample, 0.0) / PI;
      } else {
         L_sample = sampleCosineHemisphere(N);
         NdotL_sample = max(dot(N, L_sample), 0.0);

         sampleValid = NdotL_sample > 0.0 && dot(N_geom, L_sample) > 0.0;
         if (!sampleValid) break;

         vec3 H = normalize(V + L_sample);
         float LdotH = max(dot(L_sample, H), 0.0);

         vec3 diffuseColor = diffuseAlbedo * (1.0 - metallic);
         vec3 diffBRDF = diffuseHammon(diffuseColor, roughness, NdotV, NdotL_sample, LdotH) * (vec3(1.0) - kS);

         float pdfDiff = NdotL_sample / PI;
         throughput *= diffBRDF * NdotL_sample / max(pdfDiff * (1.0 - specularProb), 1e-5);

         pdfBRDF_marginal = specularProb * pdfGGXVNDFL(N, V, L_sample, roughness)
               + (1.0 - specularProb) * pdfDiff;
      }

      if (frontLit && dot(L_sample, lightDir) >= sunCosThreshold) {
         SunVisibility shadow = traceSunVisibility(shadowOrigin, L_sample, SHADOW_MAX_DIST, lightDir, sunCosThreshold, referenceGlassIOR, WATER_IOR, vec3(1.0), shadowStartsInWater);
         if (shadow.visible) {
            vec3 brdfAtSun = evalBRDF(N, V, L_sample, diffuseAlbedo, roughness, metallic, F0, F82tint);
            float pdfSpecGuide_at = pdfGGXVNDFL(N, V, L_sample, roughness);
            float wBRDF = pdfBRDF_marginal / (pdfBRDF_marginal + pdfNEE_sun + specularGuideSampleCount * pdfSpecGuide_at);
            radiance += wBRDF * surfaceThroughput * brdfAtSun * NdotL_sample
                  * sunRadiance * lightTint * shadow.transmittance
                  * atmosphereTransmittance(shadow.finalDir)
                  / max(pdfBRDF_marginal, 1e-8);
         }
      }

      nextDir = L_sample;
      hasFixedDir = true;

      rayOrigin = offsetRayOrigin(hitPoint, N);
      hitNormal = N;

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

   if (control.sceneFrozen != 1u) {
      accumulated = radiance;
      newCount = 1.0;
   } else {
      newCount = frameCount + 1.0;
      accumulated = mix(prev.rgb, radiance, 1.0 / newCount);
   }

   imageStore(colorimg5, coord, vec4(accumulated, newCount));
}
