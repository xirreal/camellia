#version 460 compatibility

/*
const int colortex6Format = RGBA32F;
const int colortex7Format = RGBA32F;
const int colortex8Format = RGBA32F;
*/

uniform sampler2D gtexture;

in vec3 vPlayerPos;
in vec3 vWorldNormal;
in vec4 vColor;
in vec2 vTexCoord;

/* RENDERTARGETS: 6,7,8 */

layout(location = 0) out vec4 positionOut;
layout(location = 1) out vec4 normalOut;
layout(location = 2) out vec4 albedoOut;

void main() {
   vec4 baseColor = texture(gtexture, vTexCoord) * vColor;

   positionOut = vec4(vPlayerPos, 1.0);
   normalOut = vec4(normalize(vWorldNormal), 1.0);
   albedoOut = vec4(pow(max(baseColor.rgb, vec3(0.0)), vec3(2.2)), baseColor.a);
}
