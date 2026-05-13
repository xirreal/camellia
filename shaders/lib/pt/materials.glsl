#ifndef MATERIALS_INCLUDE_GUARD
#define MATERIALS_INCLUDE_GUARD

#include "/lib/bvh/raytrace.glsl"

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

// Adobe Standard Material parameter values for F0 ("Base Color") and F82 tint
// ("Specular Edge Color"), calculated using measured spectral data and the full
// Fresnel equations. Values are linear Rec. 709 from Table 1 of the Adobe
// Standard Material Technical Documentation (May 2023).
//
//   230 iron      -> Fe
//   231 gold      -> Au
//   232 aluminum  -> Al
//   233 chrome    -> Cr
//   234 copper    -> Cu
//   235 lead      -> Hg (close enough)
//   236 platinum  -> Pt
//   237 silver    -> Ag
const vec3 METAL_F0[8] = vec3[8](
      vec3(0.8951, 0.8755, 0.8154), // 230: Fe (iron)
      vec3(1.0000, 0.7099, 0.3148), // 231: Au (gold)
      vec3(0.9157, 0.9226, 0.9236), // 232: Al (aluminum)
      vec3(0.5496, 0.5561, 0.5531), // 233: Cr (chrome)
      vec3(1.0000, 0.6504, 0.5274), // 234: Cu (copper)
      vec3(0.7815, 0.7795, 0.7783), // 235: Hg (mercury/lead)
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
      F0 = baseColor;
      F82tint = vec3(1.0);
   }
}

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

#endif
