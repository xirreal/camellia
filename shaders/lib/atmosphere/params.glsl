// Atmosphere physical parameters (all units in meters)

#ifndef ATMOSPHERE_PARAMS_INCLUDE_GUARD
#define ATMOSPHERE_PARAMS_INCLUDE_GUARD

const float PI = 3.14159265358979323846;

const float ATM_GROUND_RADIUS = 6360e3;
const float ATM_TOP_RADIUS = 6460e3;

uniform vec3 cameraPosition;
#ifndef ATM_CAMERA_POSITION
#define ATM_CAMERA_POSITION cameraPosition
#endif
#define ATM_OBSERVER_POS vec3(0.0, ATM_GROUND_RADIUS + ATM_CAMERA_POSITION.y + 500.0, 0.0)

const vec3 SUN_ILLUMINANCE = vec3(20.0);
const vec3 MOON_ILLUMINANCE = vec3(0.1);

// Rayleigh
const float RAYLEIGH_SCALE_HEIGHT = 8696.45;
const vec3 RAYLEIGH_SCATTERING = vec3(6.6049e-06, 1.2345e-05, 2.9413e-05);
const float RAYLEIGH_ABSORPTION = 0.0;

// Mie
const float MIE_SCALE_HEIGHT = 1200.0;
const float MIE_SCATTERING_BASE = 3.996e-06;
const float MIE_ABSORPTION_BASE = 4.4e-06;
const float MIE_G = 0.8;

// Ozone
const float OZONE_BASE_HEIGHT = 22349.90;
const float OZONE_LAYER_THICKNESS = 35660.71;
const vec3 OZONE_ABSORPTION = vec3(2.2911e-06, 1.5404e-06, 0.0);

// Ground
const vec3 GROUND_ALBEDO = vec3(0.3);

// Airglow emission layers
// Volume Emission Rates (VER) in W/m³/sr, derived from Rayleigh intensities:
//   Column intensity (R) -> peak VER = (Column * 1e10) / (4*PI) * (h*c/lambda) / (sigma * sqrt(2*PI))
// with h*c = 1.98645e-25 J*m

// OI 557.7 nm green line: ~250 R, peak at 96 km, sigma ~4 km
const float AIRGLOW_GREEN_PEAK_HEIGHT = 96000.0;
const float AIRGLOW_GREEN_SIGMA = 4000.0;
const float AIRGLOW_GREEN_VER = 7.066e-12; // W/m³/sr
const vec3 AIRGLOW_GREEN_COLOR = vec3(0.0, 1.0, 0.0); // 557.7nm spectral green

// OI 630.0 nm red line omitted: peaks at ~250 km, above ATM_TOP_RADIUS (100 km)

// Na 589.3 nm: ~50 R, peak at 92 km, sigma ~2.5 km
const float AIRGLOW_NA_PEAK_HEIGHT = 92000.0;
const float AIRGLOW_NA_SIGMA = 2500.0;
const float AIRGLOW_NA_VER = 2.140e-12; // W/m³/sr
const vec3 AIRGLOW_NA_COLOR = vec3(1.0, 0.3515, 0.0); // 589.3nm spectral amber

// OH Meinel bands (~730 nm effective): ~1500 R, peak at 87 km, sigma ~4 km
const float AIRGLOW_OH_PEAK_HEIGHT = 87000.0;
const float AIRGLOW_OH_SIGMA = 4000.0;
const float AIRGLOW_OH_VER = 3.240e-11; // W/m³/sr
const vec3 AIRGLOW_OH_COLOR = vec3(0.8, 0.1, 0.03); // ~730nm effective deep red

#endif
