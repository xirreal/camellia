#ifndef BRDF_INCLUDE_GUARD
#define BRDF_INCLUDE_GUARD

#include "/lib/core/rand.glsl"

const float BRDF_PI = 3.14159265358979323846;

vec3 sampleCosineHemisphere(vec3 normal) {
   float r1 = rand();
   float r2 = rand();
   float phi = 2.0 * BRDF_PI * r1;
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
// See "Novel aspects of the Adobe Standard Material" (Kutz, Hasan, Edmondson, 2023), section 2.
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

float D_GGX(float NdotH, float roughness) {
   float a = max(roughness * roughness, 0.002);
   float a2 = a * a;
   float denom = (NdotH * NdotH) * (a2 - 1.0) + 1.0;
   return a2 / (BRDF_PI * denom * denom);
}

// Smith Lambda for GGX (alpha^2 as input; alpha = roughness^2).
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
// (A, B) such that single-scatter spec albedo = F0*A + B and total directional
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
   float phi = 2.0 * BRDF_PI * r2;
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
//   pdf(L) = D(H) * G1(V) * max(VdotH,0) / NdotV / (4*VdotH)
//          = D(H) * G1(V) / (4*NdotV)
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
   return albedo * (lightScatter * viewScatter * energyFactor) * (1.0 / BRDF_PI);
}

// Fdez-Aguera 2019 multi-scatter / diffuse coupling at NdotV.
// Returns the single-scatter+multi-scatter total spec albedo (kS) for use as
// "1 - kS" diffuse weight, and stores the multi-scatter scaling factor for the
// single-scatter spec lobe (Turquin 2019, F0-tinted to match Adobe section 1.2).
void specEnergyTerms(vec3 F0, float NdotV, float roughness,
   out vec3 kS, out vec3 specMSFactor) {
   vec2 ab = envBRDFApprox(NdotV, roughness);
   float Ess = max(ab.x + ab.y, 0.01);
   float Ems = max(1.0 - Ess, 0.0);

   // Turquin 2019 single-scatter compensation. Multiplying by F0 gives the
   // F0^2 behaviour for the multi-scatter contribution from Adobe section 1.2.
   specMSFactor = vec3(1.0) + F0 * (Ems / Ess);

   // Fdez-Aguera total spec albedo at NdotV (used for diffuse coupling and
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
   // the full reciprocal form would require precomputed L(wi) and T tables.
   vec3 diffuseColor = albedo * (1.0 - metallic);
   vec3 diffTerm = diffuseHammon(diffuseColor, roughness, NdotV, NdotL, LdotH) * (vec3(1.0) - kS);

   return diffTerm + specTerm;
}

#endif
