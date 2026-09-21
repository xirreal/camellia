#include "/lib/core/settings.glsl"

#ifdef GBUFFERS_LAYER_CAPTURE
#include "/lib/scene/textures-copy.glsl"
uniform float viewWidth;
uniform float viewHeight;
flat in uvec4 gTextureCopy;
#endif

uniform sampler2D gtexture;
uniform float alphaTestRef;

#if defined(GBUFFERS_LABPBR_ATLAS)
#define GBUFFERS_HAS_LABPBR
uniform sampler2D normalAtlas;
uniform sampler2D specularAtlas;
#elif defined(GBUFFERS_TEXTURE_PBR) && defined(ENTITY_PBR)
#define GBUFFERS_HAS_LABPBR
#endif
#if (defined(GBUFFERS_TEXTURE_PBR) && defined(ENTITY_PBR)) || defined(GBUFFERS_LAYER_CAPTURE)
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
flat in uint vBlockID;

layout(location = 0) out vec4 positionOut;
layout(location = 1) out vec4 normalOut;
layout(location = 2) out vec4 albedoOut;

#ifdef GBUFFERS_HAS_LABPBR
#include "/lib/core/normal-map.glsl"

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
   vec3 tangentNormal = decodeMinecraftNormalMap(normalSample);

   vec3 normal = normalize(geomNormal);
   vec3 tangent = safeTangent(normal, tangentSample.xyz);
   // Opposite Iris's raw-map bitangent because tangentNormal has DirectX Y converted.
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
   #ifdef GBUFFERS_LAYER_CAPTURE
   if (gTextureCopy.w != 0u) {
      copyEntityTexture(gTextureCopy, ivec2(viewWidth, viewHeight), gtexture, normals, specular);
      discard;
   }
   #endif
   vec4 baseColor = texture(gtexture, vTexCoord) * vec4(vColor.rgb, 1.0);

   #ifdef GBUFFERS_ALPHA_TEST
   if (vBlockID == 4u ? baseColor.a == 0.0 : baseColor.a < alphaTestRef) discard;
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
   normalOut = vec4(normal, vBlockID == 1u ? 2.0 : 1.0);
   albedoOut = vec4(linearAlbedo, baseColor.a);
}
