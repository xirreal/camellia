layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f) uniform writeonly image2D colorimg1;
layout(rgba32f) uniform image2D colorimg5;

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
uniform float frameTimeCounter;

uniform float near;

#include "/lib/storage.glsl"
#include "/lib/hploc.glsl"
#include "/lib/encoding.glsl"
#include "/lib/noise.glsl"
#include "/lib/raytrace.glsl"
#include "/lib/atmosphere.glsl"
#include "/lib/sellmeier.glsl"

const int MAX_BOUNCES = 3;
const float SHADOW_MAX_DIST = 256.0;

#define DOF_ENABLED
#define DOF_AUTOFOCUS
#define DOF_FOCAL_LENGTH 35.0   //[17.0 24.0 35.0 50.0 85.0 105.0 135.0 200.0 250.0 300.0]
#define DOF_FSTOP 16.0           //[1.4 1.8 2.0 2.4 2.8 4.0 5.6 8.0 11.0 16.0]
#define DOF_FOCUS_DISTANCE 5.0  //[1.0 2.0 3.0 4.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 100.0]
#define DOF_SENSOR_WIDTH 36.0   //[23.5 28.7 36.0 44.0 53.0]
#define DOF_BLADES 0            //[0 3 4 5 6 7 8 9 10 11 12 13 14 15 16]

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

void adobeMetalLookup(int metalID, vec3 baseColor, out vec3 F0, out vec3 F82tint);

void decodeLabPBR(vec3 hitPos, vec2 uv, vec3 geomNormal, uint quadID, int triIndex, uint textureID, vec3 baseColor, out vec3 normal, out float roughness, out float metallic, out vec3 F0, out vec3 F82tint, out float emission, out float ao, out float sss) {
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
      F82tint = vec3(1.0);
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
   F82tint = vec3(1.0);
   if (g255 <= 229.5) {
      metallic = 0.0;
      F0 = vec3(clamp(g, 0.0, 0.8));
   } else {
      metallic = 1.0;
      int metalID = int(g255 + 0.5);
      // G == 255 (and any unrecognized metal id) falls back to using the albedo
      // as F0 with a neutral white F82-tint (which reduces F82-tint to Schlick).
      adobeMetalLookup(metalID, baseColor, F0, F82tint);
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

uint pcgHash() {
   uint state = rngState;
   rngState = rngState * 747796405u + 2891336453u;
   uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
   return (word >> 22u) ^ word;
}

uint hash_u32(uint x) {
   // Murmur3 finalizer
   x ^= x >> 16u;
   x *= 0x45d9f3bu;
   x ^= x >> 16u;
   return x;
}

void initRNG(ivec2 coord, int frame, int _seed) {
   rngState = hash_u32(uint(coord.x))
         ^ hash_u32(uint(coord.y) + 1000003u)
         ^ hash_u32(uint(frame) + 2000003u)
         ^ hash_u32(uint(_seed));
   pcgHash();
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

// Fresnel for the Adobe Standard Material's "F82-tint" metallic model.
// See "Novel aspects of the Adobe Standard Material" (Kutz, Hašan, Edmondson, 2023), §2.
// When F82_tint == vec3(1.0) this reduces exactly to the standard Schlick
// approximation, so the same function is used for dielectrics as well.
vec3 fresnelF82Tint(vec3 F0, vec3 F82tint, float cosTheta) {
   const float cosThetaMax = 1.0 / 7.0;
   const float oneMinusCosThetaMax = 1.0 - cosThetaMax;
   float omcm5 = pow5(oneMinusCosThetaMax);
   float omcm6 = omcm5 * oneMinusCosThetaMax;

   vec3 r = F0;
   vec3 whiteMinusR = vec3(1.0) - r;
   vec3 whiteMinusT = vec3(1.0) - F82tint;

   vec3 bNum = (r + whiteMinusR * omcm5) * whiteMinusT;
   float bDen = cosThetaMax * omcm6;
   vec3 b = bNum / bDen;

   float omc = 1.0 - cosTheta;
   vec3 offset = (whiteMinusR - b * cosTheta * omc) * pow5(omc);
   return clamp(r + offset, 0.0, 1.0);
}

// Adobe Standard Material parameter values for F0 ("Base Color") and F82 tint
// ("Specular Edge Color"), calculated using measured spectral data and the full
// Fresnel equations. Values are linear Rec. 709 from Table 1 of the Adobe
// Standard Material Technical Documentation (May 2023).
//
// LabPBR metal-id mapping (G channel, 230..237):
//   230 iron      -> Fe
//   231 gold      -> Au
//   232 aluminum  -> Al
//   233 chrome    -> Cr
//   234 copper    -> Cu
//   235 lead      -> Hg (closest entry in the Adobe table)
//   236 platinum  -> Pt
//   237 silver    -> Ag
const vec3 METAL_F0[8] = vec3[8](
      vec3(0.8951, 0.8755, 0.8154), // 230: Fe (iron)
      vec3(1.0000, 0.7099, 0.3148), // 231: Au (gold)
      vec3(0.9157, 0.9226, 0.9236), // 232: Al (aluminum)
      vec3(0.5496, 0.5561, 0.5531), // 233: Cr (chrome)
      vec3(1.0000, 0.6504, 0.5274), // 234: Cu (copper)
      vec3(0.7815, 0.7795, 0.7783), // 235: Hg (lead slot)
      vec3(0.9602, 0.9317, 0.8260), // 236: Pt (platinum)
      vec3(0.9868, 0.9830, 0.9667) // 237: Ag (silver)
   );
const vec3 METAL_F82_TINT[8] = vec3[8](
      vec3(0.8551, 0.8800, 0.8966), // 230: Fe
      vec3(0.9408, 0.9636, 0.9099), // 231: Au
      vec3(0.9090, 0.9365, 0.9596), // 232: Al
      vec3(0.7372, 0.7511, 0.8170), // 233: Cr
      vec3(0.9755, 0.9349, 0.9301), // 234: Cu
      vec3(0.8103, 0.8532, 0.9046), // 235: Hg
      vec3(0.9501, 0.9461, 0.9352), // 236: Pt
      vec3(0.9929, 0.9961, 1.0000) // 237: Ag
   );

void adobeMetalLookup(int metalID, vec3 baseColor, out vec3 F0, out vec3 F82tint) {
   if (metalID >= 230 && metalID <= 237) {
      int idx = metalID - 230;
      F0 = METAL_F0[idx];
      F82tint = METAL_F82_TINT[idx];
   } else {
      // G == 255 (and any other unrecognized metallic id): use the albedo as
      // F0 and a neutral white F82-tint, which makes F82-tint reduce to Schlick.
      F0 = baseColor;
      F82tint = vec3(1.0);
   }
}

float D_GGX(float NdotH, float roughness) {
   float a = max(roughness * roughness, 0.002);
   float a2 = a * a;
   float denom = (NdotH * NdotH) * (a2 - 1.0) + 1.0;
   return a2 / (PI * denom * denom);
}

// Smith Λ for GGX (α² as input; α = roughness²).
float smithLambdaGGX(float NdotW, float a2) {
   float c = max(NdotW, 1e-5);
   float c2 = c * c;
   return 0.5 * (sqrt(1.0 + a2 * (1.0 - c2) / c2) - 1.0);
}

// Smith G1 for GGX.
float smithG1GGX(float NdotW, float a2) {
   return 1.0 / (1.0 + smithLambdaGGX(NdotW, a2));
}

// Height-correlated Smith G2 for GGX (Heitz 2014).
float smithG2GGX(float NdotV, float NdotL, float a2) {
   return 1.0 / (1.0 + smithLambdaGGX(NdotV, a2) + smithLambdaGGX(NdotL, a2));
}

// Karis 2014 fit for the split-sum environment BRDF integral. Returns
// (A, B) such that single-scatter spec albedo = F0·A + B and total directional
// albedo at F=1 is Ess = A + B. Used for multi-scatter compensation and for
// energy-conserving diffuse coupling.
vec2 envBRDFApprox(float NdotV, float roughness) {
   const vec4 c0 = vec4(-1.0, -0.0275, -0.572, 0.022);
   const vec4 c1 = vec4(1.0, 0.0425, 1.04, -0.04);
   vec4 r = roughness * c0 + c1;
   float a004 = min(r.x * r.x, exp2(-9.28 * NdotV)) * r.x + r.y;
   return vec2(-1.04, 1.04) * a004 + r.zw;
}

// Sample GGX visible normals (Heitz 2018, isotropic). Ve is the view vector
// in tangent space (z = up). Returns the half-vector in tangent space.
vec3 sampleGGXVNDFIsotropic(vec3 Ve, float a, float r1, float r2) {
   vec3 Vh = normalize(vec3(a * Ve.x, a * Ve.y, Ve.z));
   float lensq = Vh.x * Vh.x + Vh.y * Vh.y;
   vec3 T1 = (lensq > 0.0) ? vec3(-Vh.y, Vh.x, 0.0) * inversesqrt(lensq) : vec3(1.0, 0.0, 0.0);
   vec3 T2 = cross(Vh, T1);
   float r = sqrt(r1);
   float phi = 2.0 * PI * r2;
   float t1 = r * cos(phi);
   float t2 = r * sin(phi);
   float s = 0.5 * (1.0 + Vh.z);
   t2 = (1.0 - s) * sqrt(max(0.0, 1.0 - t1 * t1)) + s * t2;
   vec3 Nh = t1 * T1 + t2 * T2 + sqrt(max(0.0, 1.0 - t1 * t1 - t2 * t2)) * Vh;
   return normalize(vec3(a * Nh.x, a * Nh.y, max(1e-5, Nh.z)));
}

// World-space convenience: sample a half-vector from VNDF given world-space N,V.
vec3 sampleGGXHalfWorld(vec3 N, vec3 V, float roughness) {
   float a = max(roughness * roughness, 0.002);
   vec3 up = abs(N.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
   vec3 T = normalize(cross(up, N));
   vec3 B = cross(N, T);
   vec3 Vt = vec3(dot(V, T), dot(V, B), dot(V, N));
   vec3 Ht = sampleGGXVNDFIsotropic(Vt, a, rand(), rand());
   return normalize(T * Ht.x + B * Ht.y + N * Ht.z);
}

// VNDF pdf in solid-angle measure for incoming direction L given V,N.
//   pdf(L) = D(H) · G1(V) · max(VdotH,0) / NdotV / (4·VdotH)
//          = D(H) · G1(V) / (4·NdotV)
float pdfGGXVNDFL(vec3 N, vec3 V, vec3 L, float roughness) {
   if (dot(N, L) <= 0.0 || dot(N, V) <= 0.0) return 0.0;
   vec3 H = normalize(V + L);
   float NdotH = max(dot(N, H), 0.0);
   float NdotV = max(dot(N, V), 1e-5);
   float a = max(roughness * roughness, 0.002);
   float a2 = a * a;
   return D_GGX(NdotH, roughness) * smithG1GGX(NdotV, a2) / (4.0 * NdotV);
}

vec3 diffuseHammon(vec3 albedo, float roughness, float NdotV, float NdotL, float LdotH) {
   float energyBias = mix(0.0, 0.5, roughness);
   float energyFactor = mix(1.0, 1.0 / 1.51, roughness);
   float fd90 = energyBias + 2.0 * LdotH * LdotH * roughness;
   float lightScatter = 1.0 + (fd90 - 1.0) * pow5(1.0 - NdotL);
   float viewScatter = 1.0 + (fd90 - 1.0) * pow5(1.0 - NdotV);
   return albedo * (lightScatter * viewScatter * energyFactor) * (1.0 / PI);
}

// Fdez-Agüera 2019 multi-scatter / diffuse coupling at NdotV.
// Returns the single-scatter+multi-scatter total spec albedo (kS) for use as
// "1 - kS" diffuse weight, and stores the multi-scatter scaling factor for the
// single-scatter spec lobe (Turquin 2019, F0-tinted to match Adobe §1.2).
void specEnergyTerms(vec3 F0, float NdotV, float roughness,
   out vec3 kS, out vec3 specMSFactor) {
   vec2 ab = envBRDFApprox(NdotV, roughness);
   float Ess = max(ab.x + ab.y, 0.01);
   float Ems = max(1.0 - Ess, 0.0);

   // Turquin 2019 single-scatter compensation. Multiplying by F0 gives the
   // F0² behaviour for the multi-scatter contribution from Adobe §1.2.
   specMSFactor = vec3(1.0) + F0 * (Ems / Ess);

   // Fdez-Agüera total spec albedo at NdotV (used for diffuse coupling and
   // for Fresnel-weighted lobe-picking).
   vec3 FssEss = F0 * ab.x + ab.y;
   vec3 Favg = F0 + (vec3(1.0) - F0) * (1.0 / 21.0);
   vec3 Fms = FssEss * Favg / max(vec3(1.0) - Favg * Ems, vec3(1e-5));
   kS = clamp(FssEss + Fms * Ems, vec3(0.0), vec3(1.0));
}

vec3 evalBRDF(vec3 N, vec3 V, vec3 L, vec3 albedo, float roughness, float metallic, vec3 F0, vec3 F82tint) {
   float NdotL = max(dot(N, L), 0.0);
   float NdotV = max(dot(N, V), 0.0);
   if (NdotL <= 0.0 || NdotV <= 0.0) return vec3(0.0);

   vec3 H = normalize(V + L);
   float NdotH = max(dot(N, H), 0.0);
   float VdotH = max(dot(V, H), 0.0);
   float LdotH = max(dot(L, H), 0.0);

   float a = max(roughness * roughness, 0.002);
   float a2 = a * a;

   vec3 F = fresnelF82Tint(F0, F82tint, VdotH);
   float D = D_GGX(NdotH, roughness);
   float G2 = smithG2GGX(NdotV, NdotL, a2);
   vec3 specSS = (D * G2) * F / max(4.0 * NdotV * NdotL, 1e-5);

   vec3 kS;
   vec3 specMSFactor;
   specEnergyTerms(F0, NdotV, roughness, kS, specMSFactor);
   vec3 specTerm = specSS * specMSFactor;

   // Energy-conserving diffuse: the energy that did not leave through the spec
   // lobe (1 - kS) is available for diffuse. This is the practical Karis-Ess
   // approximation of the Ashikhmin-Premoze-Shirley separable diffuse term;
   // the full reciprocal form would require precomputed L(ωi) and T tables.
   vec3 diffuseColor = albedo * (1.0 - metallic);
   vec3 diffTerm = diffuseHammon(diffuseColor, roughness, NdotV, NdotL, LdotH) * (vec3(1.0) - kS);

   return diffTerm + specTerm;
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
   // shadowLightPosition: sun by day, moon by night (Iris auto-swaps).
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

   // World-space direction toward the active shadow light (frozen-aware).
   vec3 lightDir = normalize((mvInv * vec4(lightPos, 0.0)).xyz);

   // Detect day/night from the world-space sun altitude (camera-orientation
   // independent). shadowLightPosition switches at the horizon, so the NEE
   // tint and intensity must follow it. The skyView LUT lookup is also keyed
   // off this sun direction, so we read the frozen value when frozen to keep
   // the lookup axis stable during accumulation.
   vec3 sunPosForFrame = control.sceneFrozen == 1u ? control.frozenSunPos.xyz : sunPosition;
   vec3 worldSunDir = normalize((mvInv * vec4(sunPosForFrame, 0.0)).xyz);
   bool isDay = worldSunDir.y >= 0.0;
   vec3 lightIlluminance = isDay ? SUN_ILLUMINANCE : MOON_ILLUMINANCE;
   vec3 lightTint = isDay ? vec3(1.0, 0.95, 0.8) : vec3(0.7, 0.85, 1.0);

   TraceResult primaryHit = traceBVH(ro, rd, true);

   if (!primaryHit.hit) {
      // The skyView LUT is azimuthally parameterized around the sun
      // (its local frame is built from sun_direction in the LUT generator),
      // so we must sample it with the sun direction even when the active
      // shadow light is the moon at night. Otherwise the lookup azimuth axis
      // mismatches the LUT layout and we get harsh banding at sunset.
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
         radiance += throughput * sampleSky(bounceDir, worldSunDir);
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
      vec3 F82tint;
      float emissionMap;
      float ao;
      float sssAmount;
      vec3 c_hitPos = origin + bounceDir * bounceHit.t;
      decodeLabPBR(c_hitPos, bounceHit.uv, bounceHit.normal, bounceHit.quadID, bounceHit.triIndex, bounceHit.textureID, bounceAlbedo, shadeNormal, roughness, metallic, F0, F82tint, emissionMap, ao, sssAmount);

      vec3 diffuseAlbedo = bounceAlbedo * ao;
      vec3 hitPoint = origin + bounceDir * bounceHit.t;
      vec3 N = shadeNormal;
      vec3 V = normalize(-bounceDir);
      vec3 surfaceThroughput = throughput;

      float d = dot(N, V);
      N = mix(N, bounceHit.normal, 1.0 - smoothstep(0.0, 0.05, d));

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

            int wl = int(rand() * float(GLASS_BIN_COUNT));
            wl = min(wl, GLASS_BIN_COUNT - 1);
            vec3 B, C;
            glassCoeffs_N_BK7(B, C);
            float channelIOR = sellmeierIOR(GLASS_WL_BIN[wl], B, C);
            // mask is column-normalised so Σmask = (1,1,1); ×N undoes 1/N selection prob.
            vec3 channelMask = GLASS_MASK_BIN[wl] * float(GLASS_BIN_COUNT);

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
      float emission = emissionMap * 20.0;
      #else
      float emission = pow(length(bounceAlbedo * 1.5), 2.2) * bounceHit.vertexData.a * 0.2;
      #endif
      if (emission > 0.0) {
         radiance += throughput * bounceAlbedo * emission;
      }

      vec3 shadowOrigin = hitPoint + N * shadowBias;
      vec3 N_geom = bounceHit.normal;
      float NdotL_direct = dot(N, lightDir);
      bool frontLit = NdotL_direct > 0.0;
      bool backLit = sssAmount > 0.0 && NdotL_direct < 0.0;

      // Lobe-pick probability and multi-scatter compensation factor at NdotV.
      float NdotV = max(dot(N, V), 1e-5);
      vec3 kS;
      vec3 specMSFactor;
      specEnergyTerms(F0, NdotV, roughness, kS, specMSFactor);
      float specularProb = clamp(max(max(kS.r, kS.g), kS.b), 0.05, 0.95);

      // Effective sun-cap solid angle used for both NEE and BRDF→sun MIS.
      // SSS surfaces widen the cap for softer shadows; the same cap is reused
      // on the BRDF side so MIS stays consistent.
      #ifdef MC_TEXTURE_FORMAT_LAB_PBR_1_3
      float sunHalfAngle = 0.007 + sssAmount * 0.01;
      #else
      float sunHalfAngle = 0.007 + sssAmount * 0.1;
      #endif
      float sunCosThreshold = cos(sunHalfAngle);
      float sunSolidAngle = max(2.0 * PI * (1.0 - sunCosThreshold), 1e-8);
      float pdfNEE_sun = 1.0 / sunSolidAngle;
      vec3 sunRadiance = lightIlluminance / sunSolidAngle;

      // ---- Next-event estimation toward the sun (with balance-heuristic MIS) ----
      if (frontLit || backLit) {
         vec3 up = abs(lightDir.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
         vec3 tangent = normalize(cross(up, lightDir));
         vec3 bitangent = cross(lightDir, tangent);

         float r = sqrt(rand()) * sunHalfAngle;
         float theta = rand() * 2.0 * PI;
         vec3 sampleDir = normalize(lightDir + (tangent * cos(theta) + bitangent * sin(theta)) * r);
         float sNdotL = dot(N, sampleDir);
         bool ngVisible = dot(N_geom, sampleDir) > 0.0;

         if (frontLit && sNdotL > 0.0 && ngVisible) {
            vec3 shadowTint = traceShadowTinted(shadowOrigin, sampleDir, SHADOW_MAX_DIST);
            if (shadowTint != vec3(0.0)) {
               vec3 brdf = evalBRDF(N, V, sampleDir, diffuseAlbedo, roughness, metallic, F0, F82tint);
               // Marginal BRDF pdf at the NEE direction (for balance heuristic).
               float pdfBRDF_at = specularProb * pdfGGXVNDFL(N, V, sampleDir, roughness)
                     + (1.0 - specularProb) * sNdotL / PI;
               float wNEE = pdfNEE_sun / (pdfNEE_sun + pdfBRDF_at);
               radiance += wNEE * surfaceThroughput * brdf * sNdotL
                     * lightIlluminance * lightTint * shadowTint
                     * atmosphereTransmittance(sampleDir);
            }
         }

         if (backLit) {
            // SSS soft-shadow term — kept outside MIS since the BRDF spec/diffuse
            // sampling never reaches the back hemisphere for the same surface.
            vec3 sssOrigin = hitPoint - N * shadowBias;
            vec3 shadowTint = traceShadowTinted(sssOrigin, sampleDir, SHADOW_MAX_DIST);
            if (shadowTint != vec3(0.0)) {
               float wrap = max(-sNdotL, 0.0);
               vec3 sssColor = diffuseAlbedo * (1.0 - metallic);
               radiance += surfaceThroughput * sssColor * (sssAmount * wrap * (1.0 / PI))
                     * lightIlluminance * lightTint * shadowTint
                     * atmosphereTransmittance(sampleDir);
            }
         }
      }

      // ---- BRDF lobe sampling (VNDF spec + cosine diffuse) ----
      vec3 L_sample;
      float NdotL_sample;
      float pdfBRDF_marginal;
      bool sampleValid;

      if (rand() < specularProb) {
         vec3 H = sampleGGXHalfWorld(N, V, roughness);
         L_sample = reflect(-V, H);
         NdotL_sample = dot(N, L_sample);

         // Reject below shading horizon (rare with VNDF) or below geometric
         // horizon (normal-mapped overhang); otherwise it produces dark fireflies.
         sampleValid = NdotL_sample > 0.0 && dot(N_geom, L_sample) > 0.0;
         if (!sampleValid) break;

         float VdotH = max(dot(V, H), 1e-5);
         float a = max(roughness * roughness, 0.002);
         float a2 = a * a;

         // VNDF-sampled spec BRDF/pdf simplifies to F · G2/G1(V).
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

      // ---- BRDF-side direct sun (MIS partner of NEE) ----
      // Adds the direct-sun contribution from a BRDF lobe sample that happens
      // to land on the sun cap. Without this, smooth metals never see the sun
      // (NEE has near-zero BRDF value at the sun for a sharp lobe, and the
      // sky LUT carries no sun disk). Balance-heuristic weighted against NEE.
      if (frontLit && dot(L_sample, lightDir) >= sunCosThreshold) {
         vec3 shadowTint = traceShadowTinted(shadowOrigin, L_sample, SHADOW_MAX_DIST);
         if (shadowTint != vec3(0.0)) {
            vec3 brdfAtSun = evalBRDF(N, V, L_sample, diffuseAlbedo, roughness, metallic, F0, F82tint);
            float wBRDF = pdfBRDF_marginal / (pdfBRDF_marginal + pdfNEE_sun);
            radiance += wBRDF * surfaceThroughput * brdfAtSun * NdotL_sample
                  * sunRadiance * lightTint * shadowTint
                  * atmosphereTransmittance(L_sample)
                  / max(pdfBRDF_marginal, 1e-8);
         }
      }

      nextDir = L_sample;
      hasFixedDir = true;

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
