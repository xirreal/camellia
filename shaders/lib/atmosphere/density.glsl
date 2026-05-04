// Atmospheric density and scattering value computation

float getMiePhase(float cosTheta) {
   const float g = MIE_G;
   const float scale = 3.0 / (8.0 * PI);
   float num = (1.0 - g * g) * (1.0 + cosTheta * cosTheta);
   float denom = (2.0 + g * g) * pow((1.0 + g * g - 2.0 * g * cosTheta), 1.5);
   return scale * num / denom;
}

float getRayleighPhase(float cosTheta) {
   const float k = 3.0 / (16.0 * PI);
   return k * (1.0 + cosTheta * cosTheta);
}

void getScatteringValues(vec3 pos,
   out vec3 rayleighScattering,
   out float mieScattering,
   out vec3 extinction) {
   float altitudeM = length(pos) - ATM_GROUND_RADIUS;

   float rayleighDensity = exp(-altitudeM / RAYLEIGH_SCALE_HEIGHT);
   float mieDensity = exp(-altitudeM / MIE_SCALE_HEIGHT);

   rayleighScattering = RAYLEIGH_SCATTERING * rayleighDensity;
   float rayleighAbsorption = RAYLEIGH_ABSORPTION * rayleighDensity;

   mieScattering = MIE_SCATTERING_BASE * mieDensity;
   float mieAbsorption = MIE_ABSORPTION_BASE * mieDensity;

   // Ozone: triangular/tent profile centered in the ozone layer
   float ozoneCenter = OZONE_BASE_HEIGHT + OZONE_LAYER_THICKNESS * 0.5;
   float ozoneHalfWidth = OZONE_LAYER_THICKNESS * 0.5;
   vec3 ozoneAbsorption = OZONE_ABSORPTION * max(0.0, 1.0 - abs(altitudeM - ozoneCenter) / ozoneHalfWidth);

   extinction = rayleighScattering + rayleighAbsorption + mieScattering + mieAbsorption + ozoneAbsorption;
}

// Airglow: self-emission from chemiluminescent layers
// Returns spectral radiance contribution (W/m³/sr) as RGB
vec3 getAirglowEmission(vec3 pos) {
   float altitudeM = length(pos) - ATM_GROUND_RADIUS;

   float dGreen = (altitudeM - AIRGLOW_GREEN_PEAK_HEIGHT) / AIRGLOW_GREEN_SIGMA;
   float dNa = (altitudeM - AIRGLOW_NA_PEAK_HEIGHT) / AIRGLOW_NA_SIGMA;
   float dOH = (altitudeM - AIRGLOW_OH_PEAK_HEIGHT) / AIRGLOW_OH_SIGMA;

   vec3 emission = AIRGLOW_GREEN_VER * exp(-0.5 * dGreen * dGreen) * AIRGLOW_GREEN_COLOR
         + AIRGLOW_NA_VER * exp(-0.5 * dNa * dNa) * AIRGLOW_NA_COLOR
         + AIRGLOW_OH_VER * exp(-0.5 * dOH * dOH) * AIRGLOW_OH_COLOR;

   // The base VER values are physical (W/m^3/sr) and very small relative to
   // the SUN_ILLUMINANCE-driven scattering in the LUT. A modest boost keeps
   // airglow faintly visible at night without letting the deep-red OH band
   // dominate moon-lit Rayleigh scattering and turn the entire night sky red.
   return emission * 50.0;
}
