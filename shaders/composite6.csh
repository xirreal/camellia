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

bool loadSpatialSupportDomain(
      ivec2 coord,
      ivec2 extent,
      vec3 visiblePos,
      vec3 visibleNormal,
      int temporalSet,
      int candidateIndex,
      float radiusOffset,
      float angleOffset,
      out Reservoir candidate,
      out vec3 neighborWorldPos,
      out vec3 neighborNormal,
      out vec3 neighborAlbedo,
      out float confidence) {
   ivec2 offset = sampleSpatialOffset(candidateIndex, RESTIR_SPATIAL_CANDIDATE_COUNT, radiusOffset, angleOffset);
   if (all(equal(offset, ivec2(0)))) return false;

   ivec2 neighborCoord = coord + offset;
   if (any(lessThan(neighborCoord, ivec2(0))) || any(greaterThanEqual(neighborCoord, extent))) return false;

   vec3 neighborPos;
   if (!loadSurface(neighborCoord, neighborPos, neighborNormal, neighborAlbedo)) return false;
   if (!similarSurface(visiblePos, visibleNormal, neighborPos, neighborNormal)) return false;

   getTemporalReservoir(neighborCoord, temporalSet, candidate);
   if (candidate.M <= 0.0 || isnan(candidate.M) || isinf(candidate.M)) {
      return false;
   }

   candidate.M = min(candidate.M, RESTIR_SPATIAL_M_CLAMP);
   confidence = candidate.M;
   if (confidence <= RESTIR_EPS) return false;

   neighborWorldPos = neighborPos + cameraPosition;

   return true;
}

bool loadSpatialCandidate(
      ivec2 coord,
      ivec2 extent,
      vec3 visiblePos,
      vec3 visibleNormal,
      int temporalSet,
      int candidateIndex,
      float radiusOffset,
      float angleOffset,
      out Reservoir candidate,
      out vec3 neighborWorldPos,
      out vec3 neighborNormal,
      out vec3 neighborAlbedo,
      out float confidence,
      out float sourceTarget,
      out float selectionWeight) {
   if (!loadSpatialSupportDomain(coord, extent, visiblePos, visibleNormal, temporalSet, candidateIndex, radiusOffset, angleOffset,
         candidate, neighborWorldPos, neighborNormal, neighborAlbedo, confidence)) {
      return false;
   }

   if (candidate.W <= 0.0 || isnan(candidate.W) || isinf(candidate.W)) return false;

   sourceTarget = targetFunction(candidate.z, neighborWorldPos, neighborNormal, neighborAlbedo);
   selectionWeight = sourceTarget > RESTIR_EPS ? confidence * sourceTarget * candidate.W : 0.0;
   if (isnan(selectionWeight) || isinf(selectionWeight)) selectionWeight = 0.0;

   return true;
}

void gatherSpatialCandidateStats(
      ivec2 coord,
      ivec2 extent,
      vec3 visiblePos,
      vec3 visibleNormal,
      int temporalSet,
      float radiusOffset,
      float angleOffset,
      out float confidenceSum,
      out float selectionWeightSum,
      out int supportDomainCount) {
   confidenceSum = 0.0;
   selectionWeightSum = 0.0;
   supportDomainCount = 0;

   for (int i = 0; i < RESTIR_SPATIAL_CANDIDATE_COUNT; i++) {
      Reservoir candidate;
      vec3 neighborWorldPos;
      vec3 neighborNormal;
      vec3 neighborAlbedo;
      float confidence;
      float sourceTarget;
      float selectionWeight;

      if (!loadSpatialSupportDomain(coord, extent, visiblePos, visibleNormal, temporalSet, i, radiusOffset, angleOffset,
            candidate, neighborWorldPos, neighborNormal, neighborAlbedo, confidence)) {
         continue;
      }

      confidenceSum += confidence;
      supportDomainCount++;

      if (candidate.W <= 0.0 || isnan(candidate.W) || isinf(candidate.W)) continue;

      sourceTarget = targetFunction(candidate.z, neighborWorldPos, neighborNormal, neighborAlbedo);
      selectionWeight = sourceTarget > RESTIR_EPS ? confidence * sourceTarget * candidate.W : 0.0;
      if (isnan(selectionWeight) || isinf(selectionWeight)) selectionWeight = 0.0;
      selectionWeightSum += selectionWeight;
   }
}

bool getSpatialSupportDomainByRank(
      ivec2 coord,
      ivec2 extent,
      vec3 visiblePos,
      vec3 visibleNormal,
      int temporalSet,
      float radiusOffset,
      float angleOffset,
      int targetRank,
      out Reservoir selectedCandidate,
      out vec3 selectedWorldPos,
      out vec3 selectedNormal,
      out vec3 selectedAlbedo,
      out float selectedConfidence) {
   int rank = 0;

   for (int i = 0; i < RESTIR_SPATIAL_CANDIDATE_COUNT; i++) {
      Reservoir candidate;
      vec3 neighborWorldPos;
      vec3 neighborNormal;
      vec3 neighborAlbedo;
      float confidence;

      if (!loadSpatialSupportDomain(coord, extent, visiblePos, visibleNormal, temporalSet, i, radiusOffset, angleOffset,
            candidate, neighborWorldPos, neighborNormal, neighborAlbedo, confidence)) {
         continue;
      }

      if (rank == targetRank) {
         selectedCandidate = candidate;
         selectedWorldPos = neighborWorldPos;
         selectedNormal = neighborNormal;
         selectedAlbedo = neighborAlbedo;
         selectedConfidence = confidence;
         return true;
      }

      rank++;
   }

   return false;
}

bool sampleSpatialCandidateByWeight(
      ivec2 coord,
      ivec2 extent,
      vec3 visiblePos,
      vec3 visibleNormal,
      int temporalSet,
      float radiusOffset,
      float angleOffset,
      float selectionWeightSum,
      out Reservoir selectedCandidate,
      out vec3 selectedWorldPos,
      out vec3 selectedNormal,
      out vec3 selectedAlbedo,
      out float selectedConfidence,
      out float selectedSourceTarget,
      out float selectedSelectionWeight) {
   if (selectionWeightSum <= RESTIR_EPS) return false;

   float threshold = rand() * selectionWeightSum;
   float accumulated = 0.0;
   bool found = false;
   bool hasFallback = false;

   Reservoir fallbackCandidate = emptyReservoir();
   vec3 fallbackWorldPos = vec3(0.0);
   vec3 fallbackNormal = vec3(0.0);
   vec3 fallbackAlbedo = vec3(0.0);
   float fallbackConfidence = 0.0;
   float fallbackSourceTarget = 0.0;
   float fallbackSelectionWeight = 0.0;

   for (int i = 0; i < RESTIR_SPATIAL_CANDIDATE_COUNT; i++) {
      Reservoir candidate;
      vec3 neighborWorldPos;
      vec3 neighborNormal;
      vec3 neighborAlbedo;
      float confidence;
      float sourceTarget;
      float selectionWeight;

      if (!loadSpatialCandidate(coord, extent, visiblePos, visibleNormal, temporalSet, i, radiusOffset, angleOffset,
            candidate, neighborWorldPos, neighborNormal, neighborAlbedo, confidence, sourceTarget, selectionWeight)) {
         continue;
      }
      if (selectionWeight <= RESTIR_EPS) continue;

      accumulated += selectionWeight;
      fallbackCandidate = candidate;
      fallbackWorldPos = neighborWorldPos;
      fallbackNormal = neighborNormal;
      fallbackAlbedo = neighborAlbedo;
      fallbackConfidence = confidence;
      fallbackSourceTarget = sourceTarget;
      fallbackSelectionWeight = selectionWeight;
      hasFallback = true;

      if (!found && threshold <= accumulated) {
         selectedCandidate = candidate;
         selectedWorldPos = neighborWorldPos;
         selectedNormal = neighborNormal;
         selectedAlbedo = neighborAlbedo;
         selectedConfidence = confidence;
         selectedSourceTarget = sourceTarget;
         selectedSelectionWeight = selectionWeight;
         found = true;
      }
   }

   if (found) return true;
   if (!hasFallback) return false;

   selectedCandidate = fallbackCandidate;
   selectedWorldPos = fallbackWorldPos;
   selectedNormal = fallbackNormal;
   selectedAlbedo = fallbackAlbedo;
   selectedConfidence = fallbackConfidence;
   selectedSourceTarget = fallbackSourceTarget;
   selectedSelectionWeight = fallbackSelectionWeight;
   return true;
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

   if (centerReservoir.M <= 0.0 || isnan(centerReservoir.M) || isinf(centerReservoir.M)) {
      centerReservoir.M = 1.0;
   }

   centerReservoir.M = min(centerReservoir.M, RESTIR_SPATIAL_M_CLAMP);
   float pHatCenter = targetFunction(centerReservoir.z, visibleWorldPos, visibleNormal, visibleAlbedo);
   bool hasCanonical = centerReservoir.W > RESTIR_EPS && !isnan(centerReservoir.W) && !isinf(centerReservoir.W)
      && pHatCenter > RESTIR_EPS;

   float radiusOffset = rand();
   float angleOffset = rand();

   // Large-kernel candidate set: gather source-domain confidence and contribution
   // without shifting every neighbor into the current pixel.
   float confidenceSum;
   float selectionWeightSum;
   int supportDomainCount;
   gatherSpatialCandidateStats(coord, extent, visiblePos, visibleNormal, frameCounter % 2, radiusOffset, angleOffset,
      confidenceSum, selectionWeightSum, supportDomainCount);

   float centerConfidence = centerReservoir.M;
   float nonCanonicalScale = supportDomainCount > 0
      ? min(1.0, float(RESTIR_SPATIAL_PAIRWISE_SAMPLES) / float(supportDomainCount))
      : 0.0;
   float scaledConfidenceSum = confidenceSum * nonCanonicalScale;

   Reservoir spatialReservoir = emptyReservoir();
   float selectedTarget = 0.0;
   bool hasSelectedTarget = false;

   // Stochastic canonical pairwise MIS estimate, using one uniformly chosen
   // support domain by default.
   float canonicalMis = 1.0;
   if (hasCanonical && scaledConfidenceSum > RESTIR_EPS) {
      float pairConfidenceSum = scaledConfidenceSum + centerConfidence;
      canonicalMis = centerConfidence / pairConfidenceSum;

      for (int i = 0; i < RESTIR_SPATIAL_CANONICAL_SAMPLES; i++) {
         int targetRank = clamp(int(floor(rand() * float(supportDomainCount))), 0, max(supportDomainCount - 1, 0));

         Reservoir candidate;
         vec3 neighborWorldPos;
         vec3 neighborNormal;
         vec3 neighborAlbedo;
         float candidateConfidence;
         if (!getSpatialSupportDomainByRank(coord, extent, visiblePos, visibleNormal, frameCounter % 2, radiusOffset, angleOffset,
               targetRank, candidate, neighborWorldPos, neighborNormal, neighborAlbedo, candidateConfidence)) {
            continue;
         }

         float scaledCandidateConfidence = candidateConfidence * nonCanonicalScale;
         float pHatCenterToNeighbor = spatialMergeTarget(centerReservoir.z, neighborWorldPos, neighborNormal, neighborAlbedo);
         float betaDenom = scaledConfidenceSum * pHatCenterToNeighbor + centerConfidence * pHatCenter;
         if (betaDenom <= RESTIR_EPS || isnan(betaDenom) || isinf(betaDenom)) continue;

         float beta = (scaledCandidateConfidence / pairConfidenceSum)
            * ((centerConfidence * pHatCenter) / betaDenom);
         canonicalMis += beta * (float(supportDomainCount) / float(RESTIR_SPATIAL_CANONICAL_SAMPLES));
      }
   }

   if (hasCanonical && mergeReservoir(spatialReservoir, centerReservoir, canonicalMis * pHatCenter * centerReservoir.W)) {
      selectedTarget = pHatCenter;
      hasSelectedTarget = true;
   }

   // Non-canonical stochastic pairwise MIS: sample contributing source domains
   // with replacement and compensate each selected domain by 1 / (N * P_i).
   if (selectionWeightSum > RESTIR_EPS && scaledConfidenceSum > RESTIR_EPS) {
      for (int i = 0; i < RESTIR_SPATIAL_PAIRWISE_SAMPLES; i++) {
         Reservoir candidate;
         vec3 neighborWorldPos;
         vec3 neighborNormal;
         vec3 neighborAlbedo;
         float candidateConfidence;
         float candidateSourceTarget;
         float candidateSelectionWeight;
         if (!sampleSpatialCandidateByWeight(coord, extent, visiblePos, visibleNormal, frameCounter % 2, radiusOffset, angleOffset,
               selectionWeightSum, candidate, neighborWorldPos, neighborNormal, neighborAlbedo,
               candidateConfidence, candidateSourceTarget, candidateSelectionWeight)) {
            continue;
         }

         float candidateTarget = targetFunction(candidate.z, visibleWorldPos, visibleNormal, visibleAlbedo);
         if (candidateTarget <= RESTIR_EPS) continue;

         float candidateJacobian = reuseJacobian(candidate.z, visibleWorldPos);
         float shiftedTarget = candidateTarget * candidateJacobian;
         if (shiftedTarget <= RESTIR_EPS || isnan(shiftedTarget) || isinf(shiftedTarget)) continue;

         float selectionProbability = candidateSelectionWeight / selectionWeightSum;
         if (selectionProbability <= RESTIR_EPS || isnan(selectionProbability) || isinf(selectionProbability)) continue;

         float scaledCandidateConfidence = candidateConfidence * nonCanonicalScale;
         float pairDenom = scaledConfidenceSum * candidateSourceTarget + centerConfidence * shiftedTarget;
         if (pairDenom <= RESTIR_EPS || isnan(pairDenom) || isinf(pairDenom)) continue;

         float deterministicMis = (scaledConfidenceSum / (scaledConfidenceSum + centerConfidence))
            * ((scaledCandidateConfidence * candidateSourceTarget) / pairDenom);
         float stochasticMis = deterministicMis / (float(RESTIR_SPATIAL_PAIRWISE_SAMPLES) * selectionProbability);
         float candidateWeight = stochasticMis * shiftedTarget * candidate.W;

         if (mergeReservoir(spatialReservoir, candidate, candidateWeight)) {
            selectedTarget = candidateTarget;
            hasSelectedTarget = true;
         }
      }
   }

   spatialReservoir.z.visiblePointPos = visibleWorldPos;
   spatialReservoir.z.visiblePointNormal = visibleNormal;

   if (!hasSelectedTarget) {
      selectedTarget = targetFunction(spatialReservoir.z, visibleWorldPos, visibleNormal, visibleAlbedo);
   }
   // Section 4.3: the defensive scaling replaces c_Σ with c_Σ · Ñ/M everywhere,
   // including in the reservoir's emitted confidence. Using the unscaled sum
   // would over-inflate downstream M and undo the anti-pepper defense.
   spatialReservoir.M = min(centerConfidence + scaledConfidenceSum, RESTIR_SPATIAL_M_CLAMP);
   spatialReservoir.W = (spatialReservoir.M > 0.0 && spatialReservoir.w_sum > 0.0 && selectedTarget > RESTIR_EPS)
      ? clamp(spatialReservoir.w_sum / selectedTarget, 0.0, RESTIR_WEIGHT_CLAMP)
      : 0.0;
   if (isnan(spatialReservoir.W) || isinf(spatialReservoir.W)) spatialReservoir.W = 0.0;

   setSpatialReservoir(coord, spatialReservoir);
}
