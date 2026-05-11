uniform sampler2D gtexture;
uniform float alphaTestRef;

in vec3 vPlayerPos;
in vec3 vWorldNormal;
in vec4 vColor;
in vec2 vTexCoord;

layout(location = 0) out vec4 positionOut;
layout(location = 1) out vec4 normalOut;
layout(location = 2) out vec4 albedoOut;

void main() {
   vec4 baseColor = texture(gtexture, vTexCoord) * vColor;

   #ifdef GBUFFERS_ALPHA_TEST
   if (baseColor.a < alphaTestRef) discard;
   #endif

   positionOut = vec4(vPlayerPos, 1.0);
   normalOut = vec4(normalize(vWorldNormal), 1.0);
   albedoOut = vec4(pow(max(baseColor.rgb, vec3(0.0)), vec3(2.2)), baseColor.a);
}
