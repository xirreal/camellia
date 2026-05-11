#ifndef RESTIR_SAMPLING_INCLUDE_GUARD
#define RESTIR_SAMPLING_INCLUDE_GUARD

#include "/lib/core/rand.glsl"

#define RESTIR_PI 3.14159265358979323846

vec3 sampleUniformHemisphere(vec3 normal) {
   float r1 = rand();
   float r2 = rand();

   float phi = 2.0 * RESTIR_PI * r1;
   float cosTheta = r2;
   float sinTheta = sqrt(max(0.0, 1.0 - cosTheta * cosTheta));

   vec3 up = abs(normal.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
   vec3 tangent = normalize(cross(up, normal));
   vec3 bitangent = cross(normal, tangent);

   return normalize(
      tangent * cos(phi) * sinTheta +
         bitangent * sin(phi) * sinTheta +
         normal * cosTheta
   );
}

float uniformHemispherePdf() {
   return 1.0 / (2.0 * RESTIR_PI);
}

#endif
