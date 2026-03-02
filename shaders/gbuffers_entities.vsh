#version 150 compatibility

in vec4 at_midBlock;

out vec2 texcoord;
out vec3 tint;
out vec3 normal;
out float emission;

void main() {
   gl_Position = ftransform();

   texcoord = gl_MultiTexCoord0.xy;
   tint = gl_Color.rgb;
   normal = gl_NormalMatrix * normalize(gl_Normal);
   emission = at_midBlock.w;
}
