#version 460

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba32f) uniform writeonly image2D colorimg5;

uniform sampler2D colortex6;
uniform sampler2D colortex7;
uniform sampler2D colortex8;
uniform sampler2D blockAtlas;
uniform sampler2D normalAtlas;
uniform sampler2D specularAtlas;
uniform float viewWidth;
uniform float viewHeight;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform vec3 sunPosition;

uniform int randomSeed;
uniform int frameCounter;

#include "/lib/core/storage.glsl"
#include "/lib/restir/reservoir.glsl"
#include "/lib/restir/sampling.glsl"
#include "/lib/bvh/raytrace.glsl"
#include "/lib/atmosphere/atmosphere.glsl"

vec3 viewRayDirection(ivec2 coord) {
   vec2 uv = (vec2(coord) + 0.5) / vec2(viewWidth, viewHeight);
   vec2 ndc = uv * 2.0 - 1.0;
   vec4 clipDir = vec4(ndc, 1.0, 1.0);
   vec4 viewDir = gbufferProjectionInverse * clipDir;
   viewDir.xyz /= viewDir.w;
   return normalize(mat3(gbufferModelViewInverse) * viewDir.xyz);
}

vec3 sampleSunCap(vec3 sunDirection, float cosThreshold) {
   vec3 up = abs(sunDirection.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
   vec3 tangent = normalize(cross(up, sunDirection));
   vec3 bitangent = cross(sunDirection, tangent);

   float phi = 2.0 * RESTIR_PI * rand();
   float cosTheta = mix(cosThreshold, 1.0, rand());
   float sinTheta = sqrt(max(0.0, 1.0 - cosTheta * cosTheta));

   return normalize(tangent * cos(phi) * sinTheta + bitangent * sin(phi) * sinTheta + sunDirection * cosTheta);
}

vec3 estimateDirectSun(vec3 visiblePos, vec3 visibleNormal, vec3 visibleAlbedo, vec3 sunDirection) {
   if (sunDirection.y <= 0.0) return vec3(0.0);

   float sunCosThreshold = cos(RESTIR_SUN_HALF_ANGLE);
   vec3 sunSampleDir = sampleSunCap(sunDirection, sunCosThreshold);
   float nDotL = dot(visibleNormal, sunSampleDir);
   if (nDotL <= 0.0) return vec3(0.0);

   vec3 shadowTint = traceShadowTinted(visiblePos + visibleNormal * RESTIR_VISIBILITY_BIAS, sunSampleDir, RESTIR_SHADOW_MAX_DIST);
   if (shadowTint == vec3(0.0)) return vec3(0.0);

   vec3 brdf = visibleAlbedo / RESTIR_PI;
   return brdf * nDotL
      * SUN_ILLUMINANCE * atmosphereTransmittance(sunSampleDir)
      * shadowTint;
}

vec3 estimatePrimaryEmission(vec3 visibleAlbedo, float visibleEmission) {
   return visibleAlbedo * visibleEmission;
}

float luminance(vec3 color) {
   return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

bool validSurface(vec3 normal) {
   return dot(normal, normal) > 0.25;
}

bool loadSurface(ivec2 coord, out vec3 position, out vec3 normal, out vec3 albedo, out float emission) {
   vec4 positionEmission = texelFetch(colortex6, coord, 0);
   position = positionEmission.rgb;
   emission = positionEmission.a;
   normal = texelFetch(colortex7, coord, 0).rgb;
   albedo = max(texelFetch(colortex8, coord, 0).rgb, vec3(0.0));

   if (!validSurface(normal)) return false;

   normal = normalize(normal);
   return true;
}

vec3 visibilityTint(Sample S, vec3 visibleWorldPos, vec3 visibleNormal) {
   vec3 toSample = S.samplePointPos - visibleWorldPos;
   float dist2 = dot(toSample, toSample);
   if (dist2 <= RESTIR_EPS) return vec3(0.0);

   float dist = sqrt(dist2);
   vec3 wi = toSample / dist;
   if (dot(visibleNormal, wi) <= 0.0) return vec3(0.0);

   float maxDist = max(dist - 2.0 * RESTIR_VISIBILITY_BIAS, 0.0);
   vec3 visiblePlayerPos = visibleWorldPos - cameraPosition;
   return traceShadowTinted(visiblePlayerPos + visibleNormal * RESTIR_VISIBILITY_BIAS, wi, maxDist);
}

vec3 estimateContribution(Reservoir reservoir, vec3 visibleWorldPos, vec3 visibleNormal, vec3 visibleAlbedo, vec3 tint) {
   vec3 toSample = reservoir.z.samplePointPos - visibleWorldPos;
   float dist2 = dot(toSample, toSample);
   if (dist2 <= RESTIR_EPS || reservoir.W <= 0.0) return vec3(0.0);

   vec3 wi = toSample * inversesqrt(dist2);
   float cosTheta = max(dot(visibleNormal, wi), 0.0);
   if (cosTheta <= 0.0) return vec3(0.0);

   vec3 contribution = reservoir.z.outgoingRadiance * tint * visibleAlbedo * (cosTheta / RESTIR_PI) * reservoir.W;
   if (any(isnan(contribution)) || any(isinf(contribution))) return vec3(0.0);
   return contribution;
}

void main() {
   ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
   ivec2 extent = ivec2(int(viewWidth), int(viewHeight));

   if (coord.x >= extent.x || coord.y >= extent.y) return;

   initRNG(coord, frameCounter, randomSeed);

   vec3 viewDir = viewRayDirection(coord);
   vec3 sunDirection = normalize((mat3(gbufferModelViewInverse) * sunPosition).xyz);

   vec3 visiblePos;
   vec3 visibleNormal;
   vec3 visibleAlbedo;
   float visibleEmission;
   if (!loadSurface(coord, visiblePos, visibleNormal, visibleAlbedo, visibleEmission)) {
      imageStore(colorimg5, coord, vec4(sampleSky(viewDir, sunDirection), 1.0));
      return;
   }

   vec3 visibleWorldPos = visiblePos + cameraPosition;
   vec3 appliedRadiance = estimateDirectSun(visiblePos, visibleNormal, visibleAlbedo, sunDirection)
         + estimatePrimaryEmission(visibleAlbedo, visibleEmission);

   Reservoir reservoir;
   getSpatialReservoir(coord, reservoir);
   if (reservoir.M <= 0.0 || reservoir.W <= 0.0) {
      imageStore(colorimg5, coord, vec4(max(appliedRadiance, vec3(0.0)), 1.0));
      return;
   }

   vec3 tint = visibilityTint(reservoir.z, visibleWorldPos, visibleNormal);
   if (luminance(tint) <= RESTIR_EPS) {
      imageStore(colorimg5, coord, vec4(max(appliedRadiance, vec3(0.0)), 1.0));
      return;
   }

   // Feed the accepted spatial reuse result into temporal history after the
   // spatial pass has finished reading the temporal buffers.
   setTemporalReservoir(coord, frameCounter % 2, reservoir);

   vec3 estimate = appliedRadiance + estimateContribution(reservoir, visibleWorldPos, visibleNormal, visibleAlbedo, tint);
   imageStore(colorimg5, coord, vec4(max(estimate, vec3(0.0)), 1.0));
}
