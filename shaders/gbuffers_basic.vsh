#version 150 compatibility

out vec2 texcoord;
out vec3 tint;
out vec3 normal;
out vec3 position;

void main() {
   gl_Position = ftransform();

   texcoord = gl_MultiTexCoord0.xy;
   tint = gl_Color.rgb;
   normal = gl_NormalMatrix * normalize(gl_Normal);
}
