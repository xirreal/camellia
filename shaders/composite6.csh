#version 460

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

uniform sampler2D colortex6;
uniform sampler2D colortex7;
uniform sampler2D colortex8;
uniform float viewWidth;
uniform float viewHeight;
uniform vec3 cameraPosition;

uniform int randomSeed;
uniform int frameCounter;

#include "/lib/core/storage.glsl"
#include "/lib/restir/reservoir.glsl"

float luminance(vec3 color) {
   return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

float pHatRadiance(vec3 radiance) {
   vec3 finiteRadiance = (any(isnan(radiance)) || any(isinf(radiance))) ? vec3(0.0) : max(radiance, vec3(0.0));
   return luminance(finiteRadiance);
}

float balanceHeuristic(float p_i, float n_i, float p_k, float n_k) {
   float wi = max(p_i * n_i, 0.0);
   float wk = max(p_k * n_k, 0.0);
   float denom = wi + wk;
   return denom > RESTIR_EPS ? wi / denom : 0.0;
}

bool validSurface(vec3 normal) {
   return dot(normal, normal) > 0.25;
}

bool loadSurface(ivec2 coord, out vec3 position, out vec3 normal, out vec3 albedo) {
   position = texelFetch(colortex6, coord, 0).rgb;
   normal = texelFetch(colortex7, coord, 0).rgb;
   albedo = max(texelFetch(colortex8, coord, 0).rgb, vec3(0.0));

   if (!validSurface(normal)) return false;

   normal = normalize(normal);
   return true;
}

bool similarSurface(vec3 centerPos, vec3 centerNormal, vec3 neighborPos, vec3 neighborNormal) {
   if (dot(centerNormal, neighborNormal) < RESTIR_NORMAL_THRESHOLD) return false;

   float centerDepth = length(centerPos);
   float neighborDepth = length(neighborPos);
   float maxDepthDelta = max(max(centerDepth, neighborDepth) * RESTIR_DEPTH_THRESHOLD, RESTIR_MIN_DEPTH_DELTA);
   return abs(centerDepth - neighborDepth) <= maxDepthDelta;
}

float reuseJacobian(Sample S, vec3 visibleWorldPos) {
   if (dot(S.samplePointNormal, S.samplePointNormal) <= 0.25) return 1.0;

   vec3 originalVector = S.samplePointPos - S.visiblePointPos;
   vec3 reuseVector = S.samplePointPos - visibleWorldPos;
   float originalDist2 = dot(originalVector, originalVector);
   float reuseDist2 = dot(reuseVector, reuseVector);

   if (originalDist2 <= RESTIR_EPS || reuseDist2 <= RESTIR_EPS) return 0.0;

   vec3 originalDir = originalVector * inversesqrt(originalDist2);
   vec3 reuseDir = reuseVector * inversesqrt(reuseDist2);
   float originalCos = abs(dot(S.samplePointNormal, -originalDir));
   float reuseCos = abs(dot(S.samplePointNormal, -reuseDir));

   if (originalCos <= RESTIR_EPS || reuseCos <= RESTIR_EPS) return 0.0;

   float jacobian = (reuseCos / originalCos) * (originalDist2 / reuseDist2);
   if (isnan(jacobian) || isinf(jacobian)) return 0.0;
   return clamp(jacobian, 0.0, RESTIR_SPATIAL_JACOBIAN_CLAMP);
}

float targetFunction(Sample S, vec3 visibleWorldPos, vec3 visibleNormal, vec3 visibleAlbedo) {
   vec3 toSample = S.samplePointPos - visibleWorldPos;
   float dist2 = dot(toSample, toSample);
   if (dist2 <= RESTIR_EPS) return 0.0;

   vec3 wi = toSample * inversesqrt(dist2);
   float cosTheta = max(dot(visibleNormal, wi), 0.0);
   if (cosTheta <= 0.0) return 0.0;

   return pHatRadiance(S.outgoingRadiance * visibleAlbedo * (cosTheta / RESTIR_PI));
}

float spatialMergeTarget(Sample S, vec3 visibleWorldPos, vec3 visibleNormal, vec3 visibleAlbedo) {
   float target = targetFunction(S, visibleWorldPos, visibleNormal, visibleAlbedo);
   if (target <= RESTIR_EPS) return 0.0;

   float jacobian = reuseJacobian(S, visibleWorldPos);
   if (jacobian <= RESTIR_EPS) return 0.0;

   return target * jacobian;
}

ivec2 sampleSpatialOffset(int sampleIndex, int sampleCount, float radiusOffset, float angleOffset) {
   const float goldenAngle = 2.39996322972865332;
   float invCount = 1.0 / float(max(sampleCount, 1));
   float radius = sqrt((float(sampleIndex) + radiusOffset) * invCount) * RESTIR_SPATIAL_RADIUS;
   float angle = (float(sampleIndex) + angleOffset) * goldenAngle;
   return ivec2(round(vec2(cos(angle), sin(angle)) * radius));
}

void main() {
   ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
   ivec2 extent = ivec2(int(viewWidth), int(viewHeight));

   if (coord.x >= extent.x || coord.y >= extent.y) return;

   initRNG(coord, frameCounter, randomSeed);

   vec3 visiblePos;
   vec3 visibleNormal;
   vec3 visibleAlbedo;
   if (!loadSurface(coord, visiblePos, visibleNormal, visibleAlbedo)) {
      setSpatialReservoir(coord, emptyReservoir());
      return;
   }

   vec3 visibleWorldPos = visiblePos + cameraPosition;

   Reservoir centerReservoir;
   getTemporalReservoir(coord, frameCounter % 2, centerReservoir);

   if (centerReservoir.M <= 0.0 || centerReservoir.W <= 0.0) {
      setSpatialReservoir(coord, emptyReservoir());
      return;
   }

   centerReservoir.M = min(centerReservoir.M, RESTIR_SPATIAL_M_CLAMP);
   float pHatCenter = targetFunction(centerReservoir.z, visibleWorldPos, visibleNormal, visibleAlbedo);
   if (pHatCenter <= RESTIR_EPS) {
      setSpatialReservoir(coord, emptyReservoir());
      return;
   }

   Reservoir spatialReservoir = emptyReservoir();
   float weightCenter = 1.0;
   int validSampleCount = 1;
   int spatialSampleCount = centerReservoir.M >= RESTIR_SPATIAL_M_CLAMP_HALF
      ? RESTIR_SPATIAL_SAMPLES_LOW
      : RESTIR_SPATIAL_SAMPLES_HIGH;
   float radiusOffset = rand();
   float angleOffset = rand();

   for (int i = 0; i < spatialSampleCount; i++) {
      ivec2 offset = sampleSpatialOffset(i, spatialSampleCount, radiusOffset, angleOffset);
      if (all(equal(offset, ivec2(0)))) continue;

      ivec2 neighborCoord = coord + offset;
      if (any(lessThan(neighborCoord, ivec2(0))) || any(greaterThanEqual(neighborCoord, extent))) continue;

      vec3 neighborPos;
      vec3 neighborNormal;
      vec3 neighborAlbedo;
      if (!loadSurface(neighborCoord, neighborPos, neighborNormal, neighborAlbedo)) continue;
      if (!similarSurface(visiblePos, visibleNormal, neighborPos, neighborNormal)) continue;

      Reservoir neighborReservoir;
      getTemporalReservoir(neighborCoord, frameCounter % 2, neighborReservoir);
      if (neighborReservoir.M <= 0.0 || neighborReservoir.W <= 0.0) continue;

      Reservoir candidate = neighborReservoir;
      candidate.M = min(candidate.M, RESTIR_SPATIAL_M_CLAMP);
      vec3 neighborWorldPos = neighborPos + cameraPosition;

      float pHatNeighbor = targetFunction(candidate.z, neighborWorldPos, neighborNormal, neighborAlbedo);
      float pHatNeighborToCenter = spatialMergeTarget(candidate.z, visibleWorldPos, visibleNormal, visibleAlbedo);
      float pHatCenterToNeighbor = spatialMergeTarget(centerReservoir.z, neighborWorldPos, neighborNormal, neighborAlbedo);

      float n_k = candidate.M * float(spatialSampleCount);
      float weightNeighbor = balanceHeuristic(pHatNeighbor, n_k, pHatNeighborToCenter, centerReservoir.M);
      float centerHeuristic = balanceHeuristic(pHatCenterToNeighbor, n_k, pHatCenter, centerReservoir.M);
      weightCenter += 1.0 - centerHeuristic;

      mergeReservoir(spatialReservoir, candidate, pHatNeighborToCenter * candidate.W * weightNeighbor);
      validSampleCount++;
   }

   mergeReservoir(spatialReservoir, centerReservoir, pHatCenter * centerReservoir.W * weightCenter);

   spatialReservoir.z.visiblePointPos = visibleWorldPos;
   spatialReservoir.z.visiblePointNormal = visibleNormal;

   float selectedTarget = targetFunction(spatialReservoir.z, visibleWorldPos, visibleNormal, visibleAlbedo);
   spatialReservoir.W = (spatialReservoir.M > 0.0 && spatialReservoir.w_sum > 0.0 && selectedTarget > RESTIR_EPS)
      ? clamp(spatialReservoir.w_sum / (float(validSampleCount) * selectedTarget), 0.0, RESTIR_WEIGHT_CLAMP)
      : 0.0;
   if (isnan(spatialReservoir.W) || isinf(spatialReservoir.W)) spatialReservoir.W = 0.0;

   setSpatialReservoir(coord, spatialReservoir);
}
