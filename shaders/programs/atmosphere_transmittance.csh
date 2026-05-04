#include "/lib/atmosphere/params.glsl"
#include "/lib/atmosphere/density.glsl"
#include "/lib/atmosphere/sampling.glsl"

const ivec3 workGroups = ivec3(64, 16, 1);
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba32f) uniform writeonly image2D transmittanceImg;
const vec2 lut_resolution = vec2(512.0, 128.0);

const float sunTransmittanceSteps = 40.0;

vec3 getSunTransmittance(vec3 pos, vec3 sunDir) {
   if (rayIntersectSphere(pos, sunDir, ATM_GROUND_RADIUS) > 0.0) {
      return vec3(0.0);
   }

   float atmoDist = rayIntersectSphere(pos, sunDir, ATM_TOP_RADIUS);
   float t = 0.0;

   vec3 transmittance = vec3(1.0);
   for (float i = 0.0; i < sunTransmittanceSteps; i += 1.0) {
      float newT = ((i + 0.3) / sunTransmittanceSteps) * atmoDist;
      float dt = newT - t;
      t = newT;

      vec3 newPos = pos + t * sunDir;

      vec3 rayleighScattering, extinction;
      float mieScattering;
      getScatteringValues(newPos, rayleighScattering, mieScattering, extinction);

      transmittance *= exp(-dt * extinction);
   }
   return transmittance;
}

void main() {
   ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
   ivec2 res = ivec2(lut_resolution);

   if (pixel.x >= res.x || pixel.y >= res.y) return;

   float u = float(pixel.x) / float(res.x);
   float v = float(pixel.y) / float(res.y);

   float sunCosTheta = 2.0 * u - 1.0;
   float sunTheta = safeacos(sunCosTheta);
   float height = mix(ATM_GROUND_RADIUS, ATM_TOP_RADIUS, v);

   vec3 pos = vec3(0.0, height, 0.0);
   vec3 sunDir = normalize(vec3(0.0, sunCosTheta, -sin(sunTheta)));

   vec3 transmittance = getSunTransmittance(pos, sunDir);
   imageStore(transmittanceImg, pixel, vec4(transmittance, 1.0));
}
