#version 460 compatibility

layout(triangles) in;
layout(triangle_strip, max_vertices = 6) out;

in vec3 vPlayerPos[];
in vec3 vWorldNormal[];
in vec4 vWorldTangent[];
in float vVertexEmission[];
in vec4 vColor[];
in vec2 vTexCoord[];
flat in uint vBlockID[];
flat in uvec4 vTextureCopy[];
in vec4 vTextureCopyPosition[];

out vec3 gPlayerPos;
out vec3 gWorldNormal;
out vec4 gWorldTangent;
out float gVertexEmission;
out vec4 gColor;
out vec2 gTexCoord;
flat out uint gBlockID;
flat out uvec4 gTextureCopy;

void main() {
   // Layer capture still needs its original surface for the raster G-buffer.
   for (int i = 0; i < 3; ++i) {
      gl_Position = gl_in[i].gl_Position;
      gPlayerPos = vPlayerPos[i];
      gWorldNormal = vWorldNormal[i];
      gWorldTangent = vWorldTangent[i];
      gVertexEmission = vVertexEmission[i];
      gColor = vColor[i];
      gTexCoord = vTexCoord[i];
      gBlockID = vBlockID[i];
      gTextureCopy = uvec4(0u);
      EmitVertex();
   }
   EndPrimitive();
   if (vTextureCopy[0].w == 0u) return;
   for (int i = 0; i < 3; ++i) {
      gl_Position = vTextureCopyPosition[i];
      gTextureCopy = vTextureCopy[i];
      EmitVertex();
   }
   EndPrimitive();
}
