#version 460

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f) uniform writeonly image2D colorimg1;

uniform float viewWidth;
uniform float viewHeight;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform vec3 shadowLightPosition;

uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D depthtex0;
uniform sampler2D blockAtlas;

uniform float near;

#include "/lib/storage.glsl"
#include "/lib/hploc.glsl"
#include "/lib/encoding.glsl"
#include "/lib/raytrace.glsl"

const float SHADOW_BIAS_NEAR = 0.005;
const float SHADOW_BIAS_FAR = 0.1;
const float SHADOW_MAX_DIST = 64.0;

float linearizeDepth(float depth) {
   return (near * far) / (depth * (near - far) + far);
}

void main() {
   ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
   if (coord.x >= int(viewWidth) || coord.y >= int(viewHeight)) return;

   vec2 uv = (vec2(coord) + 0.5) / vec2(viewWidth, viewHeight);

   // Read gbuffer data
   vec4 albedo = texture(colortex1, uv);
   vec3 normal = texture(colortex2, uv).rgb * 2.0 - 1.0;
   float depth = texture(depthtex0, uv).r;

   // Skip sky pixels
   if (depth >= 1.0) {
      imageStore(colorimg1, coord, vec4(0.0));
      return;
   }

   // Reconstruct world-space position from depth
   vec2 ndc = uv * 2.0 - 1.0;
   vec4 clipPos = vec4(ndc, depth * 2.0 - 1.0, 1.0);
   vec4 viewPos = gbufferProjectionInverse * clipPos;
   viewPos /= viewPos.w;
   vec3 worldPos = (gbufferModelViewInverse * viewPos).xyz;

   // Sun/moon direction in player space
   vec3 lightDir = normalize((gbufferModelViewInverse * vec4(0.01 * shadowLightPosition, 0.0)).xyz);

   float shadowBias = mix(SHADOW_BIAS_NEAR, SHADOW_BIAS_FAR, linearizeDepth(depth) / far);

   // Shadow ray
   float NdotL = max(dot(normal, lightDir), 0.0);
   float shadow = 1.0;

   if (NdotL > 0.0) {
      vec3 shadowOrigin = worldPos + normal * shadowBias;
      shadow = traceShadow(shadowOrigin, lightDir, SHADOW_MAX_DIST) ? 0.0 : 1.0;
   }

   float lighting = max(NdotL * shadow, 0.05) + 0.2;
   imageStore(colorimg1, coord, vec4(albedo.rgb * lighting, albedo.a));
}
