#version 460

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba32f) uniform writeonly image2D colorimg5;

uniform sampler2D colortex6;
uniform sampler2D colortex7;
uniform sampler2D colortex8;
uniform sampler2D blockAtlas;
uniform float viewWidth;
uniform float viewHeight;

uniform int randomSeed;
uniform int frameCounter;

#include "/lib/core/storage.glsl"
#define CONTROL_BUFFER_QUALIFIERS restrict readonly
#include "/lib/restir/reservoir.glsl"
#include "/lib/restir/sampling.glsl"
#include "/lib/bvh/raytrace.glsl"

const int RESTIR_SPATIAL_SAMPLES = 5;
const float RESTIR_SPATIAL_RADIUS = 8.0;
const float RESTIR_NORMAL_THRESHOLD = 0.9063078; // cos(25 degrees)
const float RESTIR_DEPTH_THRESHOLD = 0.05;
const float RESTIR_MIN_DEPTH_DELTA = 0.25;
const float RESTIR_VISIBILITY_BIAS = 0.01;
const float RESTIR_EPS = 1e-6;

float luminance(vec3 color) {
   return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

bool validSurface(vec3 normal) {
   return dot(normal, normal) > 0.25;
}

bool loadSurface(ivec2 coord, out vec3 position, out vec3 normal) {
   position = texelFetch(colortex6, coord, 0).rgb;
   normal = texelFetch(colortex7, coord, 0).rgb;

   if (!validSurface(normal)) return false;

   normal = normalize(normal);
   return true;
}

bool similarSurface(vec3 centerPos, vec3 centerNormal, vec3 neighborPos, vec3 neighborNormal) {
   if (dot(centerNormal, neighborNormal) < RESTIR_NORMAL_THRESHOLD) return false;

   float centerDepth = length(centerPos);
   float neighborDepth = length(neighborPos);
   float maxDepthDelta = max(centerDepth * RESTIR_DEPTH_THRESHOLD, RESTIR_MIN_DEPTH_DELTA);
   return abs(centerDepth - neighborDepth) <= maxDepthDelta;
}

float reuseJacobian(Sample S, vec3 visiblePos) {
   vec3 originalVector = S.samplePointPos - S.visiblePointPos;
   vec3 reuseVector = S.samplePointPos - visiblePos;
   float originalDist2 = dot(originalVector, originalVector);
   float reuseDist2 = dot(reuseVector, reuseVector);

   if (originalDist2 <= RESTIR_EPS || reuseDist2 <= RESTIR_EPS) return 0.0;

   vec3 originalDir = originalVector * inversesqrt(originalDist2);
   vec3 reuseDir = reuseVector * inversesqrt(reuseDist2);
   float originalCos = abs(dot(S.samplePointNormal, -originalDir));
   float reuseCos = abs(dot(S.samplePointNormal, -reuseDir));

   if (originalCos <= RESTIR_EPS || reuseCos <= RESTIR_EPS) return 0.0;

   return (reuseCos / originalCos) * (originalDist2 / reuseDist2);
}

float geometricTarget(Sample S, vec3 visiblePos, vec3 visibleNormal) {
   vec3 toSample = S.samplePointPos - visiblePos;
   float dist2 = dot(toSample, toSample);
   if (dist2 <= RESTIR_EPS) return 0.0;

   vec3 wi = toSample * inversesqrt(dist2);
   float cosTheta = max(dot(visibleNormal, wi), 0.0);
   if (cosTheta <= 0.0) return 0.0;
   if (luminance(S.outgoingRadiance) <= RESTIR_EPS) return 0.0;

   return luminance(S.outgoingRadiance) * cosTheta;
}

vec3 visibilityTint(Sample S, vec3 visiblePos, vec3 visibleNormal) {
   vec3 toSample = S.samplePointPos - visiblePos;
   float dist2 = dot(toSample, toSample);
   if (dist2 <= RESTIR_EPS) return vec3(0.0);

   float dist = sqrt(dist2);
   vec3 wi = toSample / dist;
   float maxDist = max(dist - 2.0 * RESTIR_VISIBILITY_BIAS, 0.0);
   return traceShadowTinted(visiblePos + visibleNormal * RESTIR_VISIBILITY_BIAS, wi, maxDist);
}

float targetFunction(Sample S, vec3 visiblePos, vec3 visibleNormal, vec3 visibleAlbedo, vec3 tint) {
   vec3 toSample = S.samplePointPos - visiblePos;
   float dist2 = dot(toSample, toSample);
   if (dist2 <= RESTIR_EPS) return 0.0;

   vec3 wi = toSample * inversesqrt(dist2);
   float cosTheta = max(dot(visibleNormal, wi), 0.0);
   if (cosTheta <= 0.0) return 0.0;

   return max(luminance(S.outgoingRadiance * tint * visibleAlbedo), 0.0) * cosTheta;
}

float visibleTarget(Sample S, vec3 visiblePos, vec3 visibleNormal, vec3 visibleAlbedo, out vec3 tint) {
   float target = geometricTarget(S, visiblePos, visibleNormal);
   if (target <= 0.0) {
      tint = vec3(0.0);
      return 0.0;
   }

   tint = visibilityTint(S, visiblePos, visibleNormal);
   float visibility = luminance(tint);
   if (visibility <= RESTIR_EPS) return 0.0;

   return targetFunction(S, visiblePos, visibleNormal, visibleAlbedo, tint);
}

float spatialMergeTarget(Sample S, vec3 visiblePos, vec3 visibleNormal, vec3 visibleAlbedo) {
   vec3 tint;
   float target = visibleTarget(S, visiblePos, visibleNormal, visibleAlbedo, tint);
   if (target <= RESTIR_EPS) return 0.0;

   float jacobian = reuseJacobian(S, visiblePos);
   if (jacobian <= RESTIR_EPS) return 0.0;

   return target / jacobian;
}

ivec2 sampleSpatialNeighbor(ivec2 coord, ivec2 extent) {
   float angle = 2.0 * RESTIR_PI * rand();
   float radius = sqrt(rand()) * RESTIR_SPATIAL_RADIUS;
   ivec2 offset = ivec2(round(vec2(cos(angle), sin(angle)) * radius));

   if (all(equal(offset, ivec2(0)))) {
      offset = ivec2(1, 0);
   }

   return clamp(coord + offset, ivec2(0), extent - ivec2(1));
}

vec3 estimateContribution(Reservoir reservoir, vec3 visiblePos, vec3 visibleNormal, vec3 visibleAlbedo, vec3 tint) {
   vec3 toSample = reservoir.z.samplePointPos - visiblePos;
   float dist2 = dot(toSample, toSample);
   if (dist2 <= RESTIR_EPS || reservoir.W <= 0.0) return vec3(0.0);

   vec3 wi = toSample * inversesqrt(dist2);
   float cosTheta = max(dot(visibleNormal, wi), 0.0);
   return reservoir.z.outgoingRadiance * tint * visibleAlbedo * (cosTheta / RESTIR_PI) * reservoir.W;
}

void main() {
   ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
   ivec2 extent = ivec2(int(viewWidth), int(viewHeight));

   if (coord.x >= extent.x || coord.y >= extent.y) return;

   vec3 visiblePos;
   vec3 visibleNormal;
   if (!loadSurface(coord, visiblePos, visibleNormal)) {
      imageStore(colorimg5, coord, vec4(0.0, 0.0, 0.0, 1.0));
      return;
   }
   vec3 visibleAlbedo = max(texelFetch(colortex8, coord, 0).rgb, vec3(0.0));

   initRNG(coord, frameCounter, randomSeed);

   int temporalSet = frameCounter % 2;
   Reservoir spatialReservoir = emptyReservoir();

   ivec2 acceptedCoords[RESTIR_SPATIAL_SAMPLES + 1];
   float acceptedM[RESTIR_SPATIAL_SAMPLES + 1];
   int acceptedCount = 0;

   Reservoir centerReservoir;
   getTemporalReservoir(coord, temporalSet, centerReservoir);

   if (centerReservoir.M > 0.0 && centerReservoir.W > 0.0) {
      Reservoir candidate = centerReservoir;
      float target = spatialMergeTarget(candidate.z, visiblePos, visibleNormal, visibleAlbedo);
      if (target > RESTIR_EPS) {
         mergeReservoirs(spatialReservoir, candidate, target);

         acceptedCoords[acceptedCount] = coord;
         acceptedM[acceptedCount] = candidate.M;
         acceptedCount++;
      }
   }

   for (int i = 0; i < RESTIR_SPATIAL_SAMPLES; i++) {
      ivec2 neighborCoord = sampleSpatialNeighbor(coord, extent);

      vec3 neighborPos;
      vec3 neighborNormal;
      if (!loadSurface(neighborCoord, neighborPos, neighborNormal)) continue;
      if (!similarSurface(visiblePos, visibleNormal, neighborPos, neighborNormal)) continue;

      Reservoir neighborReservoir;
      getTemporalReservoir(neighborCoord, temporalSet, neighborReservoir);
      if (neighborReservoir.M <= 0.0 || neighborReservoir.W <= 0.0) continue;

      Reservoir candidate = neighborReservoir;
      float target = spatialMergeTarget(candidate.z, visiblePos, visibleNormal, visibleAlbedo);
      if (target <= RESTIR_EPS) continue;
      mergeReservoirs(spatialReservoir, candidate, target);

      acceptedCoords[acceptedCount] = neighborCoord;
      acceptedM[acceptedCount] = candidate.M;
      acceptedCount++;
   }

   vec3 selectedTint;
   float selectedTarget = visibleTarget(spatialReservoir.z, visiblePos, visibleNormal, visibleAlbedo, selectedTint);

   if (spatialReservoir.M <= 0.0 || spatialReservoir.w <= 0.0 || selectedTarget <= RESTIR_EPS) {
      imageStore(colorimg5, coord, vec4(0.0, 0.0, 0.0, 1.0));
      return;
   }

   float z = 0.0;
   for (int i = 0; i < acceptedCount; i++) {
      vec3 supportPos;
      vec3 supportNormal;
      if (!loadSurface(acceptedCoords[i], supportPos, supportNormal)) continue;
      vec3 supportAlbedo = max(texelFetch(colortex8, acceptedCoords[i], 0).rgb, vec3(0.0));

      if (targetFunction(spatialReservoir.z, supportPos, supportNormal, supportAlbedo, vec3(1.0)) > RESTIR_EPS) {
         z += acceptedM[i];
      }
   }

   if (z <= 0.0) {
      imageStore(colorimg5, coord, vec4(0.0, 0.0, 0.0, 1.0));
      return;
   }

   spatialReservoir.W = spatialReservoir.w / (z * selectedTarget);

   vec3 estimate = estimateContribution(spatialReservoir, visiblePos, visibleNormal, visibleAlbedo, selectedTint);
   imageStore(colorimg5, coord, vec4(max(estimate, vec3(0.0)), 1.0));
}
