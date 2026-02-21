#version 150 compatibility

in vec2 texcoord;
in vec3 tint;
in vec3 normal;

uniform sampler2D gtexture;
uniform mat4 gbufferModelViewInverse;
uniform float alphaTestRef;

/* RENDERTARGETS: 1,2 */
layout(location = 0) out vec4 albedoOut;
layout(location = 1) out vec4 normalsOut;

void main() {
   vec4 albedo = texture(gtexture, texcoord) * vec4(tint, 1.0);
   if (albedo.a < alphaTestRef) {
      discard;
   }

   albedoOut = albedo;
   normalsOut = vec4((mat3(gbufferModelViewInverse) * normal) * 0.5 + 0.5, 1.0);
}
