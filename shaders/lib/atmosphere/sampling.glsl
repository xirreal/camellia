// Atmosphere LUT sampling helpers for fragment shaders

float safeacos(float x) {
   return acos(clamp(x, -1.0, 1.0));
}

float rayIntersectSphere(vec3 ro, vec3 rd, float rad) {
   float b = dot(ro, rd);
   float c = dot(ro, ro) - rad * rad;
   if (c > 0.0 && b > 0.0) return -1.0;
   float discr = b * b - c;
   if (discr < 0.0) return -1.0;
   if (discr > b * b) return (-b + sqrt(discr));
   return -b - sqrt(discr);
}

int _wrapIndex(int p, int size) {
   if (p < 0) return p + size;
   if (p >= size) return p - size;
   return p;
}

vec3 _bilinearSample(sampler2D lut, vec2 uv, bool wrapU) {
   ivec2 size = textureSize(lut, 0);
   vec2 texPos = uv * vec2(size) - 0.5;
   vec2 texFloor = floor(texPos);
   vec2 f = texPos - texFloor;

   ivec2 p00 = ivec2(texFloor);
   ivec2 p10 = p00 + ivec2(1, 0);
   ivec2 p01 = p00 + ivec2(0, 1);
   ivec2 p11 = p00 + ivec2(1, 1);

   if (wrapU) {
      p00.x = _wrapIndex(p00.x, size.x);
      p10.x = _wrapIndex(p10.x, size.x);
      p01.x = _wrapIndex(p01.x, size.x);
      p11.x = _wrapIndex(p11.x, size.x);
   } else {
      p00.x = clamp(p00.x, 0, size.x - 1);
      p10.x = clamp(p10.x, 0, size.x - 1);
      p01.x = clamp(p01.x, 0, size.x - 1);
      p11.x = clamp(p11.x, 0, size.x - 1);
   }
   p00.y = clamp(p00.y, 0, size.y - 1);
   p10.y = clamp(p10.y, 0, size.y - 1);
   p01.y = clamp(p01.y, 0, size.y - 1);
   p11.y = clamp(p11.y, 0, size.y - 1);

   vec3 c00 = texelFetch(lut, p00, 0).rgb;
   vec3 c10 = texelFetch(lut, p10, 0).rgb;
   vec3 c01 = texelFetch(lut, p01, 0).rgb;
   vec3 c11 = texelFetch(lut, p11, 0).rgb;

   vec3 c0 = mix(c00, c10, f.x);
   vec3 c1 = mix(c01, c11, f.x);
   return mix(c0, c1, f.y);
}

vec3 _sampleTransmittanceLUTInner(sampler2D lut, float height, float sunCosZenithAngle) {
   vec2 uv = vec2(
         clamp(0.5 + 0.5 * sunCosZenithAngle, 0.0, 1.0),
         max(0.0, min(1.0, (height - ATM_GROUND_RADIUS) / (ATM_TOP_RADIUS - ATM_GROUND_RADIUS)))
      );
   return _bilinearSample(lut, uv, false);
}

vec3 sampleTransmittanceLUT(sampler2D lut, vec3 pos, vec3 sunDir) {
   float height = length(pos);
   vec3 up = pos / height;
   float sunCosZenithAngle = dot(sunDir, up);

   if (height > ATM_TOP_RADIUS) {
      float t = rayIntersectSphere(pos, sunDir, ATM_TOP_RADIUS);
      if (t < 0.0) return vec3(1.0);
      vec3 entryPos = pos + t * sunDir;
      float entryHeight = length(entryPos);
      vec3 entryUp = entryPos / entryHeight;
      return _sampleTransmittanceLUTInner(lut, entryHeight, dot(sunDir, entryUp));
   }

   return _sampleTransmittanceLUTInner(lut, height, sunCosZenithAngle);
}

vec3 sampleTransmittanceForView(sampler2D lut, vec3 viewDir) {
   float height = length(ATM_OBSERVER_POS);

   if (height > ATM_TOP_RADIUS) {
      float t = rayIntersectSphere(ATM_OBSERVER_POS, viewDir, ATM_TOP_RADIUS);
      if (t < 0.0) return vec3(1.0);
      vec3 entryPos = ATM_OBSERVER_POS + t * viewDir;
      float entryHeight = length(entryPos);
      vec3 entryUp = entryPos / entryHeight;
      return _sampleTransmittanceLUTInner(lut, entryHeight, dot(viewDir, entryUp));
   }

   vec3 up = ATM_OBSERVER_POS / height;
   float cosAngle = dot(viewDir, up);
   return _sampleTransmittanceLUTInner(lut, height, cosAngle);
}

vec3 sampleMultiScatteringLUT(sampler2D lut, vec3 pos, vec3 sunDir) {
   float height = length(pos);
   vec3 up = pos / height;
   float sunCosZenithAngle = dot(sunDir, up);

   if (height > ATM_TOP_RADIUS) {
      float t = rayIntersectSphere(pos, sunDir, ATM_TOP_RADIUS);
      if (t < 0.0) return vec3(0.0);
      vec3 entryPos = pos + t * sunDir;
      float entryHeight = length(entryPos);
      vec3 entryUp = entryPos / entryHeight;
      sunCosZenithAngle = dot(sunDir, entryUp);
      height = entryHeight;
   }

   vec2 uv = vec2(
         clamp(0.5 + 0.5 * sunCosZenithAngle, 0.0, 1.0),
         max(0.0, min(1.0, (height - ATM_GROUND_RADIUS) / (ATM_TOP_RADIUS - ATM_GROUND_RADIUS)))
      );
   return _bilinearSample(lut, uv, false);
}

// Sample sky-view LUT
// rayDir: normalized worldspace view direction
// sunDir: normalized worldspace sun direction
vec3 sampleSkyViewLUT(sampler2D lut, vec3 rayDir, vec3 sunDir) {
   float height = length(ATM_OBSERVER_POS);
   vec3 up = ATM_OBSERVER_POS / height;

   float effectiveHeight = min(height, ATM_TOP_RADIUS);
   float horizonAngle = safeacos(sqrt(effectiveHeight * effectiveHeight - ATM_GROUND_RADIUS * ATM_GROUND_RADIUS) / effectiveHeight);
   float altitudeAngle = horizonAngle - acos(dot(rayDir, up));

   float azimuthAngle;
   if (abs(altitudeAngle) > (0.5 * PI - 0.0001) || abs(dot(rayDir, up)) > 0.9999) {
      azimuthAngle = 0.0;
   } else {
      vec3 right = cross(sunDir, up);
      vec3 forward = cross(up, right);

      vec3 projectedDir = normalize(rayDir - up * dot(rayDir, up));
      float sinTheta = dot(projectedDir, right);
      float cosTheta = dot(projectedDir, forward);
      azimuthAngle = atan(sinTheta, cosTheta) + PI;
   }

   // Non-linear mapping of altitude angle (Section 5.3 of Hillaire paper)
   float v = 0.5 + 0.5 * sign(altitudeAngle) * sqrt(abs(altitudeAngle) * 2.0 / PI);
   vec2 uv = vec2(azimuthAngle / (2.0 * PI), v);

   // Azimuth wraps around (sun's azimuth is periodic), altitude clamps.
   return _bilinearSample(lut, uv, true);
}
