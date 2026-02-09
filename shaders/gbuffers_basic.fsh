#version 150 compatibility

in vec2 texcoord;
in vec3 tint;
in vec3 normal;

uniform sampler2D gtexture;
uniform mat4 gbufferModelViewInverse;

/* RENDERTARGETS: 0 */
out vec4 fragColor;

void main() {
   vec4 alberto = texture(gtexture, texcoord);
   // if (alberto.a < 0.1) {
   //    discard;
   // }

   fragColor = alberto * vec4(tint, 1.0);
   fragColor = vec4((mat3(gbufferModelViewInverse) * normal) * 0.5 + 0.5, 1.0);
}
