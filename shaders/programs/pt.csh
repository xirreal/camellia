layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f) uniform writeonly image2D colorimg1;
layout(rgba32f) uniform image2D colorimg5;

uniform float viewWidth;
uniform float viewHeight;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform vec3 shadowLightPosition;
uniform int frameCounter;
uniform sampler2D colortex5;
uniform sampler2D blockAtlas;
uniform sampler2D normalAtlas;
uniform sampler2D specularAtlas;
uniform int isEyeInWater;
uniform vec3 cameraPosition;

uniform int randomSeed;
uniform float frameTimeCounter;

uniform float near;

#include "/lib/storage.glsl"
#include "/lib/hploc.glsl"
#include "/lib/encoding.glsl"
#include "/lib/noise.glsl"
#include "/lib/raytrace.glsl"

const int MAX_BOUNCES = 4;
const float SHADOW_MAX_DIST = 256.0;
const float SKY_BRIGHTNESS = 1.6;
const float SUN_BRIGHTNESS = 20.0;
const float PI = 3.14159265359;

#define DOF_ENABLED
#define DOF_AUTOFOCUS
#define DOF_FOCAL_LENGTH 35.0   //[17.0 24.0 35.0 50.0 85.0 105.0 135.0 200.0 250.0 300.0]
#define DOF_FSTOP 16.0           //[1.4 1.8 2.0 2.4 2.8 4.0 5.6 8.0 11.0 16.0]
#define DOF_FOCUS_DISTANCE 5.0  //[1.0 2.0 3.0 4.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 100.0]
#define DOF_SENSOR_WIDTH 36.0   //[23.5 28.7 36.0 44.0 53.0]
#define DOF_BLADES 0            //[0 3 4 5 6 7 8 9 10 11 12 13 14 15 16]

const vec3 GLASS_IOR_RGB = vec3(1.510, 1.515, 1.525);

const float WATER_IOR = 1.33;
const float WATER_TINT_DESAT = 1.0;
const float WATER_WAVE_STRENGTH = 0.1;

void computeTangentBasis(uint quadID, int triIndex, vec3 geomNormal, out vec3 tangent, out vec3 bitangent) {
   vec3 p0, p1, p2, p3;
   decodeQuadPositions(quadID, p0, p1, p2, p3);

   vec3 tp0 = p0;
   vec3 tp1 = (triIndex == 0) ? p1 : p2;
   vec3 tp2 = (triIndex == 0) ? p2 : p3;

   vec2 uv0 = quadUV(quadID, 0u);
   vec2 uv1 = (triIndex == 0) ? quadUV(quadID, 1u) : quadUV(quadID, 2u);
   vec2 uv2 = (triIndex == 0) ? quadUV(quadID, 2u) : quadUV(quadID, 3u);

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

void decodeLabPBR(vec3 hitPos, vec2 uv, vec3 geomNormal, uint quadID, int triIndex, uint textureID, vec3 baseColor, out vec3 normal, out float roughness, out float metallic, out vec3 F0, out float emission, out float ao, out float sss) {
   vec4 nTexSample;
   vec4 spec;

   if (textureID != 0u) {
      #ifdef ENTITY_PBR
      nTexSample = sampleEntityNormal(textureID, uv);
      spec = sampleEntitySpecular(textureID, uv);
      #else
      normal = geomNormal;
      roughness = 1.0;
      metallic = 0.0;
      F0 = vec3(0.04);
      emission = 0.0;
      ao = 1.0;
      sss = 0.0;
      return;
      #endif
   } else {
      nTexSample = texture(normalAtlas, uv);
      spec = texture(specularAtlas, uv);
   }

   vec2 nxy = nTexSample.rg * 2.0 - 1.0;
   vec3 nTex = normalize(vec3(nxy, sqrt(max(1.0 - dot(nxy, nxy), 0.00001))));
   ao = nTexSample.b;

   vec3 tangent;
   vec3 bitangent;
   computeTangentBasis(quadID, triIndex, geomNormal, tangent, bitangent);
   normal = normalize(tangent * nTex.x + bitangent * nTex.y + geomNormal * nTex.z);
   roughness = 1.0 - spec.r;

   float g = spec.g;
   float g255 = g * 255.0;
   if (g255 <= 229.5) {
      metallic = 0.0;
      F0 = vec3(clamp(g, 0.0, 0.6));
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

   #ifdef MC_TEXTURE_FORMAT_LAB_PBR_1_3
   float b255 = spec.b * 255.0;
   if (b255 >= 64.5) {
      sss = (b255 - 65.0) / 190.0;
   } else {
      sss = 0.0;
   }
   #else
   if (quadBlockID(quadID) == 2u) {
      vec3 elFracto = fract(hitPos + cameraPosition);
      float edgeWeight = distance(vec3(0.5, elFracto.y * elFracto.y * elFracto.y, 0.5), elFracto);

      edgeWeight = pow(edgeWeight * 2.0, 4.0);
      sss = clamp(edgeWeight, 0.0, 0.6);
   } else {
      sss = 0.0;
   }
   #endif
}

// ---- RNG ----

uint rngState;

uint hash(uint x) {
   x ^= x >> 16;
   x *= 0x7feb352dU;
   x ^= x >> 15;
   x *= 0x846ca68bU;
   x ^= x >> 16;
   return x;
}

void initRNG(ivec2 coord, int frame, int _seed) {
   uint seed = uint(coord.x) + uint(coord.y) * 4096u + uint(frame) * 16777216u + uint(_seed) * 65536u;
   rngState = seed ^ hash(seed);
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

vec3 sampleCosineHemisphere(vec3 normal) {
   float r1 = rand();
   float r2 = rand();
   float phi = 2.0 * PI * r1;
   float sinTheta = sqrt(r2);
   float cosTheta = sqrt(1.0 - r2);

   vec3 up = abs(normal.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
   vec3 tangent = normalize(cross(up, normal));
   vec3 bitangent = cross(normal, tangent);

   return normalize(tangent * cos(phi) * sinTheta + bitangent * sin(phi) * sinTheta + normal * cosTheta);
}

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

const vec3 METAL_N[8] = vec3[8](
      vec3(2.9114, 2.9497, 2.5845), // 230: iron
      vec3(0.18299, 0.42108, 1.3734), // 231: gold
      vec3(1.3456, 0.96521, 0.61722), // 232: aluminum
      vec3(3.1071, 3.1812, 2.3230), // 233: chrome
      vec3(0.27105, 0.67693, 1.3164), // 234: copper
      vec3(1.9100, 1.8300, 1.4400), // 235: lead
      vec3(2.3757, 2.0847, 1.8453), // 236: platinum
      vec3(0.15943, 0.14512, 0.13547) // 237: silver
   );
const vec3 METAL_K[8] = vec3[8](
      vec3(3.0893, 2.9318, 2.7670),
      vec3(3.4242, 2.3459, 1.7704),
      vec3(7.4746, 6.3995, 5.3031),
      vec3(3.3314, 3.3291, 3.1350),
      vec3(3.6092, 2.6248, 2.2921),
      vec3(3.5100, 3.4000, 3.1800),
      vec3(4.2655, 3.7153, 3.1365),
      vec3(3.9291, 3.1900, 2.3808)
   );

vec3 labPBRMetalF0(int metalID) {
   int idx = metalID - 230;
   if (idx < 0 || idx > 7) return vec3(1.0);
   return conductorF0(METAL_N[idx], METAL_K[idx]);
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
         float newDist = centerHit.hit ? centerHit.t : 100.0;

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

   vec3 lightDir = normalize((mvInv * vec4(0.01 * lightPos, 0.0)).xyz);

   TraceResult primaryHit = traceBVH(ro, rd, true);

   if (!primaryHit.hit) {
      vec3 sky = getSkyColor(rd, lightDir);

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

   vec3 hitPos = ro;
   vec3 hitNormal = vec3(0.0);
   vec3 nextDir = rd;
   bool hasFixedDir = true;
   float shadowBias = 0.001;
   TraceResult cachedHit = primaryHit;
   bool hasCachedHit = true;

   if (isEyeInWater == 1) {
      insideMedium = true;
      insideWater = true;
   }

   for (int bounce = 0; bounce < MAX_BOUNCES; bounce++) {
      vec3 origin = hitPos + hitNormal * shadowBias;

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
         radiance += throughput * getSkyColor(bounceDir, lightDir);
         break;
      }

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
      vec3 bounceAlbedo = pow(texColor.rgb * bounceHit.vertexData.rgb, vec3(2.2));

      vec3 shadeNormal = bounceHit.normal;
      float roughness;
      float metallic;
      vec3 F0;
      float emissionMap;
      float ao;
      float sssAmount;
      vec3 c_hitPos = origin + bounceDir * bounceHit.t;
      decodeLabPBR(c_hitPos, bounceHit.uv, bounceHit.normal, bounceHit.quadID, bounceHit.triIndex, bounceHit.textureID, bounceAlbedo, shadeNormal, roughness, metallic, F0, emissionMap, ao, sssAmount);

      // radiance = vec3(sssAmount);
      // break;

      vec3 diffuseAlbedo = bounceAlbedo * ao;
      vec3 hitPoint = origin + bounceDir * bounceHit.t;
      vec3 N = shadeNormal;
      vec3 V = normalize(-bounceDir);
      vec3 surfaceThroughput = throughput;

      if (bounceHit.translucent) {
         if (bounceHit.waterSurface) {
            vec3 waterTintRaw = pow(bounceHit.vertexData.rgb, vec3(2.2));
            float luma = dot(waterTintRaw, vec3(0.2126, 0.7152, 0.0722));
            vec3 waterTint = mix(waterTintRaw, vec3(luma), WATER_TINT_DESAT);

            vec3 waveN = waterWaveNormal(hitPoint + (control.sceneFrozen == 1u ? control.frozenCameraPos.xyz : cameraPosition), 0.0, WATER_WAVE_STRENGTH);
            float sign = dot(N, vec3(0.0, 1.0, 0.0)) >= 0.0 ? 1.0 : -1.0;
            N = normalize(vec3(waveN.x * sign, waveN.y * sign, waveN.z * sign));

            float eta = insideWater ? (WATER_IOR / 1.0) : (1.0 / WATER_IOR);
            float cosI = abs(dot(bounceDir, N));
            float fresnel = fresnelSchlick(cosI, WATER_IOR);

            vec3 refracted = refract(bounceDir, N, eta);
            bool tir = dot(refracted, refracted) < 0.001;

            if (tir || rand() < fresnel) {
               nextDir = reflect(bounceDir, N);

               if (insideWater) {
                  throughput *= exp(-WATER_ABSORPTION * bounceHit.t);
                  hitPos = hitPoint + N * 0.001;
                  hitNormal = N;
               } else {
                  hitPos = hitPoint + N * 0.001;
                  hitNormal = N;
               }
            } else {
               nextDir = refracted;

               if (insideWater) {
                  throughput *= exp(-WATER_ABSORPTION * bounceHit.t);
                  insideWater = false;
                  insideMedium = false;
               } else {
                  throughput *= waterTint;
                  insideWater = true;
                  insideMedium = true;
                  mediumColor = vec3(1.0);
               }

               hitPos = hitPoint - N * 0.001;
               hitNormal = -N;
            }
            hasFixedDir = true;
            continue;
         } else {
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
            vec3 glassColor = pow(glassTexColor.rgb * glassTexColor.rgb * bounceHit.vertexData.rgb, vec3(2.2));

            int wl = int(rand() * 3.0); // 0=R, 1=G, 2=B
            wl = min(wl, 2);
            float channelIOR = GLASS_IOR_RGB[wl];
            vec3 channelMask = vec3(0.0);
            channelMask[wl] = 3.0; // weight by 3 to compensate 1/3 selection probability

            float eta = insideMedium ? (channelIOR / 1.0) : (1.0 / channelIOR);
            float cosI = abs(dot(bounceDir, N));
            float fresnel = fresnelSchlick(cosI, channelIOR);
            float glassProb = 1.0 - opacity;

            diffuseAlbedo *= roughness;

            if (rand() < glassProb) {
               vec3 refracted = refract(bounceDir, N, eta);
               bool tir = dot(refracted, refracted) < 0.001;

               if (tir || rand() < fresnel) {
                  nextDir = reflect(bounceDir, N);

                  if (insideMedium) {
                     vec3 absorption = -log(max(mediumColor, vec3(0.01)));
                     throughput *= exp(-absorption * bounceHit.t);
                     hitPos = hitPoint - N * 0.001;
                     hitNormal = -N;
                  } else {
                     hitPos = hitPoint + N * 0.001;
                     hitNormal = N;
                  }
               } else {
                  nextDir = refracted;
                  throughput *= channelMask;

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
      float emission = emissionMap * 3.0;
      #else
      float emission = pow(length(bounceAlbedo * 1.5), 2.2) * bounceHit.vertexData.a;
      #endif
      if (emission > 0.0) {
         radiance += throughput * bounceAlbedo * emission * 2.0;
      }

      vec3 shadowOrigin = hitPoint + N * shadowBias;
      float NdotL_direct = dot(N, lightDir);
      bool frontLit = NdotL_direct > 0.0;
      bool backLit = sssAmount > 0.0 && NdotL_direct < 0.0;
      if (frontLit || backLit) {
         vec3 up = abs(lightDir.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
         vec3 tangent = normalize(cross(up, lightDir));
         vec3 bitangent = cross(lightDir, tangent);

         #ifdef MC_TEXTURE_FORMAT_LAB_PBR_1_3
         float r = sqrt(rand()) * (0.007 + (sssAmount * 0.01));
         #else
         float r = sqrt(rand()) * (0.007 + (sssAmount * 0.1));
         #endif
         float theta = rand() * 2.0 * PI;
         vec3 sampleDir = normalize(lightDir + (tangent * cos(theta) + bitangent * sin(theta)) * r);
         float sNdotL = dot(N, sampleDir);

         if (frontLit && sNdotL > 0.0) {
            vec3 shadowTint = traceShadowTinted(shadowOrigin, sampleDir, SHADOW_MAX_DIST);
            if (shadowTint != vec3(0.0)) {
               vec3 brdf = evalBRDF(N, V, sampleDir, diffuseAlbedo, roughness, metallic, F0);
               radiance += surfaceThroughput * brdf * sNdotL * SUN_BRIGHTNESS * vec3(1.0, 0.95, 0.8) * shadowTint;
            }
         }

         if (backLit) {
            vec3 sssOrigin = hitPoint - N * shadowBias;
            vec3 shadowTint = traceShadowTinted(sssOrigin, sampleDir, SHADOW_MAX_DIST);
            if (shadowTint != vec3(0.0)) {
               float wrap = max(-sNdotL, 0.0);
               vec3 sssColor = diffuseAlbedo * (1.0 - metallic);
               radiance += surfaceThroughput * sssColor * (sssAmount * wrap * (1.0 / PI)) * SUN_BRIGHTNESS * vec3(1.0, 0.95, 0.8) * shadowTint;
            }
         }
      }

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
         throughput *= specBRDF * NdotL / max(pdf * specularProb, 1e-5);

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
         throughput *= diffBRDF * NdotL / max(pdf * (1.0 - specularProb), 1e-5);

         nextDir = L;
         hasFixedDir = true;
      }

      hitPos = hitPoint;
      hitNormal = N;
      shadowBias = 0.001;

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
