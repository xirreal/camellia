#include "/lib/atmosphere/params.glsl"
#include "/lib/atmosphere/sampling.glsl"

uniform sampler2D transmittanceLUT;
uniform sampler2D skyViewLUT;

vec3 atmosphereTransmittance(vec3 viewDir) {
   return sampleTransmittanceForView(transmittanceLUT, viewDir);
}

vec3 sampleSky(vec3 view_direction, vec3 sun_direction) {
   vec3 sky = sampleSkyViewLUT(skyViewLUT, view_direction, sun_direction);
   return sky;
}
