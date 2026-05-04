#include "/lib/atmosphere/params.glsl"
#include "/lib/atmosphere/density.glsl"
#include "/lib/atmosphere/sampling.glsl"

const ivec3 workGroups = ivec3(50, 50, 1);
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

uniform sampler2D transmittanceLUT;
uniform sampler2D multiScatteringLUT;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform mat4 gbufferModelViewInverse;

layout(rgba32f) uniform writeonly image2D skyViewImg;
const vec2 lut_resolution = vec2(400.0, 400.0);

const int numScatteringSteps = 64;

struct ScatterResult {
   vec3 luminance;
   vec3 transmittance;
};

ScatterResult raymarchScattering(vec3 pos, vec3 rayDir, vec3 sunDir, vec3 moonDir, vec3 sunIntensity, vec3 moonIntensity, float tMax, float numSteps) {
   float cosThetaSun = dot(rayDir, sunDir);
   float miePhaseSun = getMiePhase(cosThetaSun);
   float rayleighPhaseSun = getRayleighPhase(-cosThetaSun);

   float cosThetaMoon = dot(rayDir, moonDir);
   float miePhaseMoon = getMiePhase(cosThetaMoon);
   float rayleighPhaseMoon = getRayleighPhase(-cosThetaMoon);

   vec3 lum = vec3(0.0);
   vec3 transmittance = vec3(1.0);
   float t = 0.0;

   for (float i = 0.0; i < numSteps; i += 1.0) {
      float newT = ((i + 0.3) / numSteps) * tMax;
      float dt = newT - t;
      t = newT;

      vec3 newPos = pos + t * rayDir;

      vec3 rayleighScattering, extinction;
      float mieScattering;
      getScatteringValues(newPos, rayleighScattering, mieScattering, extinction);

      vec3 sampleTransmittance = exp(-dt * extinction);

      vec3 sunTrans = sampleTransmittanceLUT(transmittanceLUT, newPos, sunDir);
      vec3 psiMS_Sun = sampleMultiScatteringLUT(multiScatteringLUT, newPos, sunDir);
      vec3 inScatteringSun = rayleighScattering * (rayleighPhaseSun * sunTrans + psiMS_Sun)
            + mieScattering * (miePhaseSun * sunTrans + psiMS_Sun);

      vec3 moonTrans = sampleTransmittanceLUT(transmittanceLUT, newPos, moonDir);
      vec3 psiMS_Moon = sampleMultiScatteringLUT(multiScatteringLUT, newPos, moonDir);
      vec3 inScatteringMoon = rayleighScattering * (rayleighPhaseMoon * moonTrans + psiMS_Moon)
            + mieScattering * (miePhaseMoon * moonTrans + psiMS_Moon);

      vec3 totalInScattering = (inScatteringSun * sunIntensity) + (inScatteringMoon * moonIntensity);
      vec3 scatteringIntegral = (totalInScattering - totalInScattering * sampleTransmittance) / max(extinction, vec3(1e-10));

      vec3 airglowEmission = getAirglowEmission(newPos);
      vec3 emissionIntegral = (airglowEmission - airglowEmission * sampleTransmittance) / max(extinction, vec3(1e-10));

      lum += (scatteringIntegral + emissionIntegral) * transmittance;
      transmittance *= sampleTransmittance;
   }

   return ScatterResult(lum, transmittance);
}

void main() {
   ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
   ivec2 res = ivec2(lut_resolution);

   if (pixel.x >= res.x || pixel.y >= res.y) return;

   // Convert Iris view-space sun/moon positions to world (Y-up) directions.
   mat3 mvInv = mat3(gbufferModelViewInverse);
   vec3 sun_direction = normalize(mvInv * vec3(0.01 * sunPosition));
   vec3 moon_direction = normalize(mvInv * vec3(0.01 * moonPosition));

   float u = float(pixel.x) / float(res.x);
   float v = float(pixel.y) / float(res.y);

   float azimuthAngle = (u - 0.5) * 2.0 * PI;

   float adjV;
   if (v < 0.5) {
      float coord = 1.0 - 2.0 * v;
      adjV = -coord * coord;
   } else {
      float coord = v * 2.0 - 1.0;
      adjV = coord * coord;
   }

   float height = length(ATM_OBSERVER_POS);
   vec3 up = ATM_OBSERVER_POS / height;

   float effectiveHeight = min(height, ATM_TOP_RADIUS);
   float horizonAngle = safeacos(sqrt(effectiveHeight * effectiveHeight - ATM_GROUND_RADIUS * ATM_GROUND_RADIUS) / effectiveHeight) - 0.5 * PI;
   float altitudeAngle = adjV * 0.5 * PI - horizonAngle;

   float cosAltitude = cos(altitudeAngle);
   vec3 rayDir = vec3(cosAltitude * sin(azimuthAngle), sin(altitudeAngle), -cosAltitude * cos(azimuthAngle));

   vec3 sunProj = sun_direction - up * dot(sun_direction, up);
   float projLen = length(sunProj);

   vec3 localZ, localX;
   if (projLen > 0.0001) {
      localZ = -sunProj / projLen;
      localX = normalize(cross(up, localZ));
   } else {
      localZ = vec3(0.0, 0.0, 1.0);
      localX = vec3(1.0, 0.0, 0.0);
   }

   vec3 localMoonDir = vec3(
         dot(moon_direction, localX),
         dot(moon_direction, up),
         dot(moon_direction, localZ)
      );

   float sunAltitude = asin(clamp(dot(sun_direction, up), -1.0, 1.0));
   vec3 localSunDir = vec3(0.0, sin(sunAltitude), -cos(sunAltitude));

   vec3 marchOrigin = ATM_OBSERVER_POS;
   float tMax;
   if (height > ATM_TOP_RADIUS) {
      float b = dot(ATM_OBSERVER_POS, rayDir);
      float c = dot(ATM_OBSERVER_POS, ATM_OBSERVER_POS) - ATM_TOP_RADIUS * ATM_TOP_RADIUS;
      float discr = b * b - c;
      if (discr < 0.0) {
         imageStore(skyViewImg, pixel, vec4(0.0));
         return;
      }
      float sqrtDiscr = sqrt(discr);
      float tEntry = -b - sqrtDiscr;
      float tExit = -b + sqrtDiscr;
      if (tExit < 0.0) {
         imageStore(skyViewImg, pixel, vec4(0.0));
         return;
      }
      tEntry = max(tEntry, 0.0);
      marchOrigin = ATM_OBSERVER_POS + tEntry * rayDir;
      float segmentLen = tExit - tEntry;
      float groundDist = rayIntersectSphere(marchOrigin, rayDir, ATM_GROUND_RADIUS);
      tMax = (groundDist > 0.0 && groundDist < segmentLen) ? groundDist : segmentLen;
   } else {
      float atmoDist = rayIntersectSphere(ATM_OBSERVER_POS, rayDir, ATM_TOP_RADIUS);
      float groundDist = rayIntersectSphere(ATM_OBSERVER_POS, rayDir, ATM_GROUND_RADIUS);
      tMax = (groundDist < 0.0) ? atmoDist : groundDist;
   }

   ScatterResult result = raymarchScattering(
         marchOrigin, rayDir, localSunDir, localMoonDir,
         SUN_ILLUMINANCE, MOON_ILLUMINANCE,
         tMax, float(numScatteringSteps)
      );

   imageStore(skyViewImg, pixel, vec4(result.luminance, 1.0));
}
