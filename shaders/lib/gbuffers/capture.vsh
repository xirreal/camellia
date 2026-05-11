uniform mat4 gbufferModelViewInverse;

out vec3 vPlayerPos;
out vec3 vWorldNormal;
out vec4 vColor;
out vec2 vTexCoord;

void main() {
   vec4 viewSpacePos = gl_ModelViewMatrix * gl_Vertex;

   gl_Position = gl_ProjectionMatrix * viewSpacePos;
   vPlayerPos = (gbufferModelViewInverse * viewSpacePos).xyz;
   vWorldNormal = normalize(mat3(gbufferModelViewInverse) * gl_NormalMatrix * gl_Normal);
   vColor = gl_Color;
   vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}
