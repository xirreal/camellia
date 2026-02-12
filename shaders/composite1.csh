#version 460

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba8) uniform writeonly image2D colorimg1;

uniform float viewWidth;
uniform float viewHeight;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;

#include "/lib/storage.glsl"
#include "/lib/hploc.glsl"
#include "/lib/encoding.glsl"
#include "/lib/raytrace.glsl"

// 0 = normal shading, 1 = BVH depth heatmap, 2 = BVH box wireframes
#define RT_DEBUG_MODE 0 // [0 1 2]

void main() {
   ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
   if (coord.x >= int(viewWidth) || coord.y >= int(viewHeight)) return;

   vec2 uv = (vec2(coord) + 0.5) / vec2(viewWidth, viewHeight);
   vec2 ndc = uv * 2.0 - 1.0;

   vec4 clipPos = vec4(ndc, -1.0, 1.0);
   vec4 viewPos = gbufferProjectionInverse * clipPos;
   viewPos /= viewPos.w;

   vec3 viewDir = normalize(viewPos.xyz);
   vec3 worldDir = normalize((gbufferModelViewInverse * vec4(viewDir, 0.0)).xyz);
   vec3 worldOrigin = (gbufferModelViewInverse * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

   vec4 outColor;

   #if RT_DEBUG_MODE == 1
   TraceResult result = traceBVH(worldOrigin, worldDir);
   if (result.hit) {
      float costNorm = clamp(float(result.depth) / 64.0, 0.0, 1.0);
      vec3 heatmap;
      if (costNorm < 0.33) {
         heatmap = mix(vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), costNorm * 3.0);
      } else if (costNorm < 0.66) {
         heatmap = mix(vec3(0.0, 1.0, 0.0), vec3(1.0, 1.0, 0.0), (costNorm - 0.33) * 3.0);
      } else {
         heatmap = mix(vec3(1.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), (costNorm - 0.66) * 3.0);
      }
      outColor = vec4(heatmap, 1.0);
   } else {
      outColor = vec4(0.0, 0.0, 0.0, 0.0);
   }

   #elif RT_DEBUG_MODE == 2
   vec4 boxColor = traceBVHDebugBoxes(worldOrigin, worldDir);
   TraceResult result = traceBVH(worldOrigin, worldDir);
   if (result.hit) {
      vec3 normal = result.normal * 0.5 + 0.5;
      outColor = vec4(mix(normal, boxColor.rgb, boxColor.a), 1.0);
   } else if (boxColor.a > 0.0) {
      outColor = vec4(boxColor.rgb * 0.5, boxColor.a);
   } else {
      outColor = vec4(0.0, 0.0, 0.0, 0.0);
   }

   #else
   TraceResult result = traceBVH(worldOrigin, worldDir);
   if (result.hit) {
      vec3 normal = result.normal * 0.5 + 0.5;
      outColor = vec4(normal, 1.0);
   } else {
      outColor = vec4(0.0, 0.0, 0.0, 0.0);
   }
   #endif

   imageStore(colorimg1, coord, outColor);
}
