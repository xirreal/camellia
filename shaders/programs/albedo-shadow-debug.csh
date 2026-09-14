layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba32f) uniform writeonly image2D colorimg5;

uniform float viewWidth;
uniform float viewHeight;
uniform mat4 gbufferModelViewInverse;
uniform vec3 shadowLightPosition;
uniform vec3 sunPosition;
uniform sampler2D colortex6;
uniform sampler2D colortex7;
uniform sampler2D colortex8;
uniform sampler2D blockAtlas;

#include "/lib/core/storage.glsl"
#include "/lib/bvh/raytrace.glsl"
#include "/lib/atmosphere/atmosphere.glsl"

const float HARD_SHADOW_MAX_DIST = 256.0;
const float WATER_F0 = 0.02037;

vec3 shadeSimpleSurface(vec3 position, vec3 normal, vec3 albedo, vec3 lightDir) {
   float nDotL = max(dot(normal, lightDir), 0.0);
   float visibility = 0.0;
   if (nDotL > 0.0) {
      visibility = traceHardShadowVisible(
         position + normal * 1e-3, lightDir, HARD_SHADOW_MAX_DIST
      ) ? 1.0 : 0.0;
   }
   return albedo * (0.15 + 0.85 * nDotL * visibility);
}

void main() {
   ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
   if (coord.x >= int(viewWidth) || coord.y >= int(viewHeight)) return;

   vec4 position = texelFetch(colortex6, coord, 0);
   vec4 normal = texelFetch(colortex7, coord, 0);
   vec3 albedo = texelFetch(colortex8, coord, 0).rgb;

   vec3 color = vec3(0.0);
   if (normal.a > 0.0) {
      vec3 lightDir = normalize((gbufferModelViewInverse * vec4(shadowLightPosition, 0.0)).xyz);
      vec3 surfaceNormal = normalize(normal.xyz);
      color = shadeSimpleSurface(position.xyz, surfaceNormal, albedo, lightDir);

      if (normal.a > 1.5) {
         vec3 incidentDir = normalize(position.xyz - (gbufferModelViewInverse[3]).xyz);
         vec3 waterNormal = dot(surfaceNormal, incidentDir) < 0.0 ? surfaceNormal : -surfaceNormal;
         vec3 reflectedDir = reflect(incidentDir, waterNormal);
         vec3 reflectedOrigin = position.xyz + waterNormal * 1e-3;
         TraceResult reflectedHit = traceBVH(reflectedOrigin, reflectedDir, true);

         vec3 reflectedColor;
         if (reflectedHit.hit) {
            QuadAttributes qa = quadAttributes[reflectedHit.quadID];
            vec3 reflectedAlbedo = pow(max(
               sampleQuadTexture(qa, reflectedHit.uv).rgb * reflectedHit.vertexData.rgb,
               vec3(0.0)
            ), vec3(2.2));
            vec3 hitPosition = reflectedOrigin + reflectedDir * reflectedHit.t;
            reflectedColor = shadeSimpleSurface(
               hitPosition, reflectedHit.normal, reflectedAlbedo, lightDir
            );
         } else {
            vec3 sunDir = normalize((gbufferModelViewInverse * vec4(sunPosition, 0.0)).xyz);
            vec3 sky = max(sampleSky(reflectedDir, sunDir), vec3(0.0));
            reflectedColor = sky / (vec3(1.0) + sky);
         }

         float oneMinusCos = 1.0 - clamp(dot(-incidentDir, waterNormal), 0.0, 1.0);
         float oneMinusCos2 = oneMinusCos * oneMinusCos;
         float fresnel = WATER_F0 + (1.0 - WATER_F0) * oneMinusCos2 * oneMinusCos2 * oneMinusCos;
         color = mix(color, reflectedColor, fresnel);
      }
   }

   imageStore(colorimg5, coord, vec4(pow(clamp(color, 0.0, 1.0), vec3(1.0 / 2.2)), 1.0));
}
