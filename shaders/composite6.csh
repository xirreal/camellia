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
#include "/lib/restir/reuse_cells.glsl"

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

ivec2 sampleSearchCoord(ivec2 coord, ivec2 extent, float radius) {
   float angle = rand() * (2.0 * RESTIR_PI);
   float distance = sqrt(rand()) * radius;
   ivec2 offset = ivec2(round(vec2(cos(angle), sin(angle)) * distance));
   return clamp(coord + offset, ivec2(0), extent - ivec2(1));
}

bool sampleNeighborCell(
      ivec2 coord,
      ivec2 extent,
      vec3 visiblePos,
      vec3 visibleNormal,
      out uint selectedCell) {
   selectedCell = INVALID_ID;
   float radius = RESTIR_REUSE_CELL_SEARCH_RADIUS;
   float weightSum = 0.0;
   bool found = false;

   for (int i = 0; i < RESTIR_REUSE_CELL_SEARCH_SAMPLES; i++) {
      ivec2 sampleCoord = sampleSearchCoord(coord, extent, radius);

      vec3 samplePos;
      vec3 sampleNormal;
      vec3 sampleAlbedo;
      if (!loadSurface(sampleCoord, samplePos, sampleNormal, sampleAlbedo)) {
         radius *= RESTIR_REUSE_CELL_RADIUS_GROWTH;
         continue;
      }
      if (!similarSurface(visiblePos, visibleNormal, samplePos, sampleNormal)) {
         radius *= RESTIR_REUSE_CELL_RADIUS_GROWTH;
         continue;
      }

      uint samplePixelIndex = reuseCellCoordIndex(sampleCoord, extent);
      uvec4 samplePixelRecord = loadReusePixelRecord(samplePixelIndex);
      if (samplePixelRecord.z == INVALID_ID) {
         radius *= RESTIR_REUSE_CELL_RADIUS_GROWTH;
         continue;
      }

      uvec4 cellRecord = loadReuseCellRecord(samplePixelRecord.z, extent);
      float cellWeight = reuseCellConfidenceSum(cellRecord);
      if (cellWeight <= RESTIR_EPS) {
         radius *= RESTIR_REUSE_CELL_RADIUS_GROWTH;
         continue;
      }

      weightSum += cellWeight;
      if (rand() * weightSum <= cellWeight) {
         selectedCell = samplePixelRecord.z;
         found = true;
      }

      radius *= RESTIR_REUSE_CELL_RADIUS_GROWTH;
   }

   return found;
}

void mergePairwiseChoice(
      bool hasCandidate,
      uint candidatePixelIndex,
      float candidateConfidence,
      float candidateSourceTarget,
      float candidateSelectionWeight,
      float selectionWeightSum,
      float scaledConfidenceSum,
      float centerConfidence,
      float nonCanonicalScale,
      ivec2 extent,
      int temporalSet,
      vec3 visibleWorldPos,
      vec3 visibleNormal,
      vec3 visibleAlbedo,
      inout Reservoir spatialReservoir,
      inout float selectedTarget,
      inout bool hasSelectedTarget) {
   if (!hasCandidate) return;

   Reservoir candidate;
   getTemporalReservoir(reuseCellIndexToCoord(candidatePixelIndex, extent), temporalSet, candidate);
   if (candidate.M <= 0.0 || isnan(candidate.M) || isinf(candidate.M)) return;
   candidate.M = min(candidate.M, RESTIR_SPATIAL_M_CLAMP);

   float candidateTarget = targetFunction(candidate.z, visibleWorldPos, visibleNormal, visibleAlbedo);
   if (candidateTarget <= RESTIR_EPS) return;

   float candidateJacobian = reuseJacobian(candidate.z, visibleWorldPos);
   float shiftedTarget = candidateTarget * candidateJacobian;
   if (shiftedTarget <= RESTIR_EPS || isnan(shiftedTarget) || isinf(shiftedTarget)) return;

   float selectionProbability = candidateSelectionWeight / selectionWeightSum;
   if (selectionProbability <= RESTIR_EPS || isnan(selectionProbability) || isinf(selectionProbability)) return;

   float scaledCandidateConfidence = candidateConfidence * nonCanonicalScale;
   float pairDenom = scaledConfidenceSum * candidateSourceTarget + centerConfidence * shiftedTarget;
   if (pairDenom <= RESTIR_EPS || isnan(pairDenom) || isinf(pairDenom)) return;

   float deterministicMis = (scaledConfidenceSum / (scaledConfidenceSum + centerConfidence))
      * ((scaledCandidateConfidence * candidateSourceTarget) / pairDenom);
   float stochasticMis = deterministicMis / (float(RESTIR_SPATIAL_PAIRWISE_SAMPLES) * selectionProbability);
   float candidateWeight = stochasticMis * shiftedTarget * candidate.W;

   if (mergeReservoir(spatialReservoir, candidate, candidateWeight)) {
      selectedTarget = candidateTarget;
      hasSelectedTarget = true;
   }
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

   int temporalSet = frameCounter % 2;
   Reservoir centerReservoir;
   getTemporalReservoir(coord, temporalSet, centerReservoir);

   if (centerReservoir.M <= 0.0 || isnan(centerReservoir.M) || isinf(centerReservoir.M)) {
      centerReservoir.M = 1.0;
   }

   centerReservoir.M = min(centerReservoir.M, RESTIR_SPATIAL_M_CLAMP);
   float pHatCenter = targetFunction(centerReservoir.z, visibleWorldPos, visibleNormal, visibleAlbedo);
   bool hasCanonical = centerReservoir.W > RESTIR_EPS && !isnan(centerReservoir.W) && !isinf(centerReservoir.W)
      && pHatCenter > RESTIR_EPS;

   uint selectedCell;
   bool hasSelectedCell = sampleNeighborCell(coord, extent, visiblePos, visibleNormal, selectedCell);

   float confidenceSum = 0.0;
   float selectionWeightSum = 0.0;
   int supportDomainCount = 0;
   bool hasCanonicalDomain = false;
   vec3 canonicalWorldPos = vec3(0.0);
   vec3 canonicalNormal = vec3(0.0);
   vec3 canonicalAlbedo = vec3(0.0);
   float canonicalConfidence = 0.0;

   uint pairwisePixel0 = INVALID_ID;
   uint pairwisePixel1 = INVALID_ID;
   uint pairwisePixel2 = INVALID_ID;
   float pairwiseConfidence0 = 0.0;
   float pairwiseConfidence1 = 0.0;
   float pairwiseConfidence2 = 0.0;
   float pairwiseSourceTarget0 = 0.0;
   float pairwiseSourceTarget1 = 0.0;
   float pairwiseSourceTarget2 = 0.0;
   float pairwiseSelectionWeight0 = 0.0;
   float pairwiseSelectionWeight1 = 0.0;
   float pairwiseSelectionWeight2 = 0.0;
   bool hasPairwiseCandidate0 = false;
   bool hasPairwiseCandidate1 = false;
   bool hasPairwiseCandidate2 = false;

   if (hasSelectedCell) {
      uvec4 cellRecord = loadReuseCellRecord(selectedCell, extent);
      ivec2 tileOrigin = reuseCellTileOrigin(selectedCell, extent);
      uint maskLo = cellRecord.x;
      uint maskHi = cellRecord.y;

      for (int visited = 0; visited < RESTIR_REUSE_CELL_MAX_PIXELS && (maskLo != 0u || maskHi != 0u); visited++) {
         int localIndex;
         if (maskLo != 0u) {
            localIndex = findLSB(maskLo);
            maskLo &= maskLo - 1u;
         } else {
            localIndex = findLSB(maskHi) + 32;
            maskHi &= maskHi - 1u;
         }

         int x = localIndex & (RESTIR_REUSE_TILE_SIZE - 1);
         int y = localIndex >> 3;
         ivec2 neighborCoord = tileOrigin + ivec2(x, y);
         if (neighborCoord.x >= extent.x || neighborCoord.y >= extent.y) continue;
         if (all(equal(neighborCoord, coord))) continue;

         uint currentPixelIndex = reuseCellCoordIndex(neighborCoord, extent);
         uvec4 pixelRecord = loadReusePixelRecord(currentPixelIndex);
         if (pixelRecord.z != selectedCell) continue;

         vec3 neighborPos;
         vec3 neighborNormal;
         vec3 neighborAlbedo;
         if (!loadSurface(neighborCoord, neighborPos, neighborNormal, neighborAlbedo)) continue;
         if (!similarSurface(visiblePos, visibleNormal, neighborPos, neighborNormal)) continue;

         Reservoir candidate;
         getTemporalReservoir(neighborCoord, temporalSet, candidate);
         if (candidate.M <= 0.0 || isnan(candidate.M) || isinf(candidate.M)) continue;

         candidate.M = min(candidate.M, RESTIR_SPATIAL_M_CLAMP);
         float confidence = candidate.M;
         if (confidence <= RESTIR_EPS) continue;

         vec3 neighborWorldPos = neighborPos + cameraPosition;
         confidenceSum += confidence;
         supportDomainCount++;

         if (rand() * float(supportDomainCount) < 1.0) {
            canonicalWorldPos = neighborWorldPos;
            canonicalNormal = neighborNormal;
            canonicalAlbedo = neighborAlbedo;
            canonicalConfidence = confidence;
            hasCanonicalDomain = true;
         }

         float sourceTarget = uintBitsToFloat(pixelRecord.w);
         if (sourceTarget <= RESTIR_EPS || isnan(sourceTarget) || isinf(sourceTarget)) continue;
         if (candidate.W <= RESTIR_EPS || isnan(candidate.W) || isinf(candidate.W)) continue;

         float selectionWeight = confidence * sourceTarget * candidate.W;
         if (selectionWeight <= RESTIR_EPS || isnan(selectionWeight) || isinf(selectionWeight)) continue;

         selectionWeightSum += selectionWeight;
         if (rand() * selectionWeightSum <= selectionWeight) {
            pairwisePixel0 = currentPixelIndex;
            pairwiseConfidence0 = confidence;
            pairwiseSourceTarget0 = sourceTarget;
            pairwiseSelectionWeight0 = selectionWeight;
            hasPairwiseCandidate0 = true;
         }
         if (rand() * selectionWeightSum <= selectionWeight) {
            pairwisePixel1 = currentPixelIndex;
            pairwiseConfidence1 = confidence;
            pairwiseSourceTarget1 = sourceTarget;
            pairwiseSelectionWeight1 = selectionWeight;
            hasPairwiseCandidate1 = true;
         }
         if (rand() * selectionWeightSum <= selectionWeight) {
            pairwisePixel2 = currentPixelIndex;
            pairwiseConfidence2 = confidence;
            pairwiseSourceTarget2 = sourceTarget;
            pairwiseSelectionWeight2 = selectionWeight;
            hasPairwiseCandidate2 = true;
         }
      }
   }

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

      if (hasCanonicalDomain) {
         float scaledCandidateConfidence = canonicalConfidence * nonCanonicalScale;
         float pHatCenterToNeighbor = spatialMergeTarget(centerReservoir.z, canonicalWorldPos, canonicalNormal, canonicalAlbedo);
         float betaDenom = scaledConfidenceSum * pHatCenterToNeighbor + centerConfidence * pHatCenter;
         if (betaDenom > RESTIR_EPS && !isnan(betaDenom) && !isinf(betaDenom)) {
            float beta = (scaledCandidateConfidence / pairConfidenceSum)
               * ((centerConfidence * pHatCenter) / betaDenom);
            canonicalMis += beta * (float(supportDomainCount) / float(RESTIR_SPATIAL_CANONICAL_SAMPLES));
         }
      }
   }

   if (hasCanonical && mergeReservoir(spatialReservoir, centerReservoir, canonicalMis * pHatCenter * centerReservoir.W)) {
      selectedTarget = pHatCenter;
      hasSelectedTarget = true;
   }

   // Non-canonical stochastic pairwise MIS: sample contributing source domains
   // with replacement and compensate each selected domain by 1 / (N * P_i).
   if (selectionWeightSum > RESTIR_EPS && scaledConfidenceSum > RESTIR_EPS) {
      mergePairwiseChoice(hasPairwiseCandidate0, pairwisePixel0, pairwiseConfidence0, pairwiseSourceTarget0,
         pairwiseSelectionWeight0, selectionWeightSum, scaledConfidenceSum, centerConfidence, nonCanonicalScale,
         extent, temporalSet, visibleWorldPos, visibleNormal, visibleAlbedo,
         spatialReservoir, selectedTarget, hasSelectedTarget);
      mergePairwiseChoice(hasPairwiseCandidate1, pairwisePixel1, pairwiseConfidence1, pairwiseSourceTarget1,
         pairwiseSelectionWeight1, selectionWeightSum, scaledConfidenceSum, centerConfidence, nonCanonicalScale,
         extent, temporalSet, visibleWorldPos, visibleNormal, visibleAlbedo,
         spatialReservoir, selectedTarget, hasSelectedTarget);
      mergePairwiseChoice(hasPairwiseCandidate2, pairwisePixel2, pairwiseConfidence2, pairwiseSourceTarget2,
         pairwiseSelectionWeight2, selectionWeightSum, scaledConfidenceSum, centerConfidence, nonCanonicalScale,
         extent, temporalSet, visibleWorldPos, visibleNormal, visibleAlbedo,
         spatialReservoir, selectedTarget, hasSelectedTarget);
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
