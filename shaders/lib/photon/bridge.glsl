#ifndef PHOTON_BRIDGE_INCLUDE_GUARD
#define PHOTON_BRIDGE_INCLUDE_GUARD

#include "/lib/photon/utility/global_math.glsl"
#include "/lib/photon/utility/fast_math.glsl"
#include "/lib/photon/utility/random.glsl"

uniform sampler2D photonCloudNoise;
uniform sampler3D colortex9;
uniform sampler3D colortex10;
uniform float photonWorldAge;
uniform float photonBiomeTemperature;
uniform float photonBiomeHumidity;
uniform float photonBiomeSnow;
uniform float photonBiomeSandstorm;
uniform float photonLightning;
uniform float wetness;
uniform int worldDay;

const float planet_radius = ATM_GROUND_RADIUS;
const vec3 sunlight_color = vec3(1.0);
const vec3 sun_color = SUN_ILLUMINANCE;
const vec3 moon_color = MOON_ILLUMINANCE;

vec3 photonCameraPosition;
float photonRainStrength;
float photonWetness;
int photonWorldDay;
float world_age;
float biome_temperature;
float biome_humidity;
float biome_may_snow;
float biome_may_sandstorm;
float cloudLightning;
vec3 sun_dir;
vec3 moon_dir;
vec3 sky_color;
float day_factor;
float time_sunrise;
float time_sunset;
float time_noon;
float time_midnight;

vec3 atmosphere_transmittance(vec3 position, vec3 direction) {
    return sampleTransmittanceLUT(transmittanceLUT, position, direction);
}

vec3 atmosphere_post_processing(vec3 radiance) {
    return radiance;
}

#endif
