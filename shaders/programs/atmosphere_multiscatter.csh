// Multi-scattering LUT builder.
// Included from a top-level pass file (e.g. setup2.csh) which provides #version.

#include "/lib/atmosphere/params.glsl"
#include "/lib/atmosphere/density.glsl"
#include "/lib/atmosphere/sampling.glsl"

// Output LUT: 64x64, see image.multiScatteringImg in shaders.properties.
const ivec3 workGroups = ivec3(8, 8, 1);
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

uniform sampler2D transmittanceLUT;
layout(rgba32f) uniform writeonly image2D multiScatteringImg;
const vec2 lut_resolution = vec2(64.0, 64.0);

const float mulScattSteps = 20.0;
const int sqrtSamples = 8;

vec3 getSphericalDir(float theta, float phi) {
   float cosPhi = cos(phi);
   float sinPhi = sin(phi);
   float cosTheta = cos(theta);
   float sinTheta = sin(theta);
   return vec3(sinPhi * sinTheta, cosPhi, sinPhi * cosTheta);
}

void getMulScattValues(vec3 pos, vec3 sunDir, out vec3 lumTotal, out vec3 fms) {
   lumTotal = vec3(0.0);
   fms = vec3(0.0);

   float invSamples = 1.0 / float(sqrtSamples * sqrtSamples);
   for (int i = 0; i < sqrtSamples; i++) {
      for (int j = 0; j < sqrtSamples; j++) {
         float theta = PI * (float(i) + 0.5) / float(sqrtSamples);
         float phi = safeacos(1.0 - 2.0 * (float(j) + 0.5) / float(sqrtSamples));
         vec3 rayDir = getSphericalDir(theta, phi);

         float atmoDist = rayIntersectSphere(pos, rayDir, ATM_TOP_RADIUS);
         float groundDist = rayIntersectSphere(pos, rayDir, ATM_GROUND_RADIUS);
         float tMax = atmoDist;
         if (groundDist > 0.0) {
            tMax = groundDist;
         }

         float cosTheta = dot(rayDir, sunDir);

         float miePhaseValue = getMiePhase(cosTheta);
         float rayleighPhaseValue = getRayleighPhase(-cosTheta);

         vec3 lum = vec3(0.0), lumFactor = vec3(0.0), transmittance = vec3(1.0);
         float t = 0.0;
         for (float stepI = 0.0; stepI < mulScattSteps; stepI += 1.0) {
            float newT = ((stepI + 0.3) / mulScattSteps) * tMax;
            float dt = newT - t;
            t = newT;

            vec3 newPos = pos + t * rayDir;

            vec3 rayleighScattering, extinction;
            float mieScattering;
            getScatteringValues(newPos, rayleighScattering, mieScattering, extinction);

            vec3 sampleTransmittance = exp(-dt * extinction);

            vec3 scatteringNoPhase = rayleighScattering + mieScattering;
            vec3 scatteringF = (scatteringNoPhase - scatteringNoPhase * sampleTransmittance) / extinction;
            lumFactor += transmittance * scatteringF;

            vec3 sunTransmittance = sampleTransmittanceLUT(transmittanceLUT, newPos, sunDir);

            vec3 rayleighInScattering = rayleighScattering * rayleighPhaseValue;
            float mieInScattering = mieScattering * miePhaseValue;
            vec3 inScattering = (rayleighInScattering + mieInScattering) * sunTransmittance;

            vec3 scatteringIntegral = (inScattering - inScattering * sampleTransmittance) / extinction;

            lum += scatteringIntegral * transmittance;
            transmittance *= sampleTransmittance;
         }

         if (groundDist > 0.0) {
            vec3 hitPos = pos + groundDist * rayDir;
            if (dot(pos, sunDir) > 0.0) {
               hitPos = normalize(hitPos) * ATM_GROUND_RADIUS;
               lum += transmittance * GROUND_ALBEDO * sampleTransmittanceLUT(transmittanceLUT, hitPos, sunDir);
            }
         }

         fms += lumFactor * invSamples;
         lumTotal += lum * invSamples;
      }
   }
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

   vec3 lum, f_ms;
   getMulScattValues(pos, sunDir, lum, f_ms);

   vec3 psi = lum / (1.0 - f_ms);
   imageStore(multiScatteringImg, pixel, vec4(max(psi, vec3(0.0)), 1.0));
}
