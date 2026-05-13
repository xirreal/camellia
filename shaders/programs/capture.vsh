uniform mat4 gbufferModelViewInverse;

in vec4 at_tangent;
#ifdef GBUFFERS_VERTEX_EMISSION
in vec4 at_midBlock;
#endif

out vec3 vPlayerPos;
out vec3 vWorldNormal;
out vec4 vWorldTangent;
#ifdef GBUFFERS_VERTEX_EMISSION
out float vVertexEmission;
#endif
out vec4 vColor;
out vec2 vTexCoord;

void main() {
   vec4 viewSpacePos = gl_ModelViewMatrix * gl_Vertex;
   mat3 normalToPlayer = mat3(gbufferModelViewInverse) * gl_NormalMatrix;

   gl_Position = gl_ProjectionMatrix * viewSpacePos;
   vPlayerPos = (gbufferModelViewInverse * viewSpacePos).xyz;
   vWorldNormal = normalize(normalToPlayer * gl_Normal);
   vWorldTangent = vec4(normalize(normalToPlayer * at_tangent.xyz), at_tangent.w);
   #ifdef GBUFFERS_VERTEX_EMISSION
   vVertexEmission = at_midBlock.w;
   #endif
   vColor = gl_Color;
   vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}
