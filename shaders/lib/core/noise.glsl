#ifndef NOISE_INCLUDE_GUARD
#define NOISE_INCLUDE_GUARD

float noiseHash(vec2 p) {
   vec3 p3 = fract(vec3(p.xyx) * 0.1031);
   p3 += dot(p3, p3.yzx + 33.33);
   return fract((p3.x + p3.y) * p3.z);
}

float valueNoise(vec2 p) {
   vec2 i = floor(p);
   vec2 f = fract(p);
   vec2 u = f * f * (3.0 - 2.0 * f);

   float a = noiseHash(i);
   float b = noiseHash(i + vec2(1.0, 0.0));
   float c = noiseHash(i + vec2(0.0, 1.0));
   float d = noiseHash(i + vec2(1.0, 1.0));

   return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float waterFBM(vec2 p) {
   float v = 0.0;
   v += valueNoise(p) * 0.5;
   v += valueNoise(p * 2.3 + 1.7) * 0.25;
   return v;
}

vec3 waterWaveNormal(vec3 worldPos, float time, float strength) {
   vec2 p = worldPos.xz;

   vec2 p1 = p * 1.2 + vec2(time * 0.4, time * 0.3);
   vec2 p2 = p * 0.7 + vec2(-time * 0.25, time * 0.35);

   float eps = 0.05;
   float h = waterFBM(p1) + waterFBM(p2);
   float hx = waterFBM(p1 + vec2(eps, 0.0)) + waterFBM(p2 + vec2(eps, 0.0));
   float hz = waterFBM(p1 + vec2(0.0, eps)) + waterFBM(p2 + vec2(0.0, eps));

   float dx = (hx - h) / eps;
   float dz = (hz - h) / eps;

   return normalize(vec3(-dx * strength, 1.0, -dz * strength));
}

#endif
