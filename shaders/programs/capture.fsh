uniform sampler2D gtexture;
uniform float alphaTestRef;

#if defined(GBUFFERS_LABPBR_ATLAS)
#define GBUFFERS_HAS_LABPBR
uniform sampler2D normalAtlas;
uniform sampler2D specularAtlas;
#elif defined(GBUFFERS_TEXTURE_PBR) && defined(ENTITY_PBR)
#define GBUFFERS_HAS_LABPBR
uniform sampler2D normals;
uniform sampler2D specular;
#endif

in vec3 vPlayerPos;
in vec3 vWorldNormal;
in vec4 vWorldTangent;
#ifdef GBUFFERS_VERTEX_EMISSION
in float vVertexEmission;
#endif
in vec4 vColor;
in vec2 vTexCoord;

layout(location = 0) out vec4 positionOut;
layout(location = 1) out vec4 normalOut;
layout(location = 2) out vec4 albedoOut;

#ifdef GBUFFERS_HAS_LABPBR
float labPBREmission(vec4 specularSample) {
   return (specularSample.a >= (254.5 / 255.0)) ? 0.0 : specularSample.a;
}

vec3 safeTangent(vec3 normal, vec3 tangent) {
   tangent -= normal * dot(normal, tangent);
   if (dot(tangent, tangent) <= 1e-8) {
      vec3 up = abs(normal.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
      tangent = cross(up, normal);
   }
   return normalize(tangent);
}

vec3 decodeLabPBRNormal(vec4 normalSample, vec3 geomNormal, vec4 tangentSample) {
   vec2 nxy = normalSample.rg * 2.0 - 1.0;
   vec3 tangentNormal = normalize(vec3(nxy, sqrt(max(1.0 - dot(nxy, nxy), 0.00001))));

   vec3 normal = normalize(geomNormal);
   vec3 tangent = safeTangent(normal, tangentSample.xyz);
   vec3 bitangent = normalize(cross(normal, tangent)) * (tangentSample.w < 0.0 ? -1.0 : 1.0);

   return normalize(tangent * tangentNormal.x + bitangent * tangentNormal.y + normal * tangentNormal.z);
}
#endif

float fallbackVertexEmission(vec3 linearAlbedo) {
   #ifdef GBUFFERS_VERTEX_EMISSION
   return pow(length(linearAlbedo * 1.5), 2.2) * vVertexEmission * 0.2;
   #else
   return 0.0;
   #endif
}

void main() {
   vec4 baseColor = texture(gtexture, vTexCoord) * vColor;

   #ifdef GBUFFERS_ALPHA_TEST
   if (baseColor.a < alphaTestRef) discard;
   #endif

   vec3 linearAlbedo = pow(max(baseColor.rgb, vec3(0.0)), vec3(2.2));
   vec3 normal = normalize(vWorldNormal);
   #ifdef MC_TEXTURE_FORMAT_LAB_PBR_1_3
   float emission = 0.0;
   #else
   float emission = fallbackVertexEmission(linearAlbedo);
   #endif
   #ifdef GBUFFERS_HAS_LABPBR
   #ifdef GBUFFERS_LABPBR_ATLAS
   vec4 normalSample = texture(normalAtlas, vTexCoord);
   vec4 specularSample = texture(specularAtlas, vTexCoord);
   #else
   vec4 normalSample = texture(normals, vTexCoord);
   vec4 specularSample = texture(specular, vTexCoord);
   #endif
   normal = decodeLabPBRNormal(normalSample, normal, vWorldTangent);
   #ifdef MC_TEXTURE_FORMAT_LAB_PBR_1_3
   emission = labPBREmission(specularSample) * 20.0;
   #endif
   #endif

   positionOut = vec4(vPlayerPos, emission);
   normalOut = vec4(normal, 1.0);
   albedoOut = vec4(linearAlbedo, baseColor.a);
}
