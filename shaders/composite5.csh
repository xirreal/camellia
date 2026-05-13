#version 460

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

uniform sampler2D colortex6;
uniform sampler2D colortex7;
uniform sampler2D colortex8;
uniform sampler2D blockAtlas;
uniform float viewWidth;
uniform float viewHeight;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

uniform int randomSeed;
uniform int frameCounter;

#include "/lib/core/storage.glsl"
#define CONTROL_BUFFER_QUALIFIERS restrict readonly
#include "/lib/bvh/raytrace.glsl"
#include "/lib/restir/reservoir.glsl"
#include "/lib/restir/sampling.glsl"

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

bool finiteVec3(vec3 v) {
   return !any(isnan(v)) && !any(isinf(v));
}

bool loadSurface(ivec2 coord, out vec3 position, out vec3 normal, out vec3 albedo) {
   position = texelFetch(colortex6, coord, 0).rgb;
   normal = texelFetch(colortex7, coord, 0).rgb;
   albedo = max(texelFetch(colortex8, coord, 0).rgb, vec3(0.0));

   if (!validSurface(normal)) return false;

   normal = normalize(normal);
   return true;
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

bool visibleSample(Sample S, vec3 visibleWorldPos, vec3 visibleNormal) {
   vec3 toSample = S.samplePointPos - visibleWorldPos;
   float dist2 = dot(toSample, toSample);
   if (dist2 <= RESTIR_EPS) return false;

   float dist = sqrt(dist2);
   vec3 wi = toSample / dist;
   if (dot(visibleNormal, wi) <= 0.0) return false;

   float maxDist = max(dist - 2.0 * RESTIR_TEMPORAL_VISIBILITY_BIAS, 0.0);
   vec3 visiblePlayerPos = visibleWorldPos - cameraPosition;
   vec3 tint = traceShadowTinted(visiblePlayerPos + visibleNormal * RESTIR_TEMPORAL_VISIBILITY_BIAS, wi, maxDist);
   return luminance(tint) > RESTIR_EPS;
}

ivec2 temporalSearchOffset(int sampleIndex) {
   if (sampleIndex == 1) return ivec2(1, 0);
   if (sampleIndex == 2) return ivec2(-1, 0);
   if (sampleIndex == 3) return ivec2(0, 1);
   if (sampleIndex == 4) return ivec2(0, -1);
   return ivec2(0);
}

float temporalReuseJacobian(Sample S, vec3 visibleWorldPos) {
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
   return max(jacobian, 0.0);
}

bool reprojectToPreviousCoord(vec3 worldPos, ivec2 extent, out ivec2 previousCoord) {
   vec3 previousPlayerPos = worldPos - previousCameraPosition;
   vec4 previousView = gbufferPreviousModelView * vec4(previousPlayerPos, 1.0);
   vec4 previousClip = gbufferPreviousProjection * previousView;

   if (previousClip.w <= 0.0) return false;

   vec3 previousNdc = previousClip.xyz / previousClip.w;
   if (previousNdc.x < -1.0 || previousNdc.x > 1.0 ||
         previousNdc.y < -1.0 || previousNdc.y > 1.0 ||
         previousNdc.z < -1.0 || previousNdc.z > 1.0) {
      return false;
   }

   vec2 previousUv = previousNdc.xy * 0.5 + 0.5;
   previousCoord = ivec2(clamp(floor(previousUv * vec2(extent)), vec2(0.0), vec2(extent - ivec2(1))));
   return true;
}

bool validReprojectedReservoir(Reservoir reservoir, vec3 visibleWorldPos, vec3 visibleNormal) {
   if (reservoir.M <= 0.0 || reservoir.W <= 0.0) return false;
   if (!finiteVec3(reservoir.z.visiblePointPos) || !finiteVec3(reservoir.z.visiblePointNormal) ||
         !finiteVec3(reservoir.z.samplePointPos) || !finiteVec3(reservoir.z.samplePointNormal)) {
      return false;
   }
   if (dot(reservoir.z.visiblePointNormal, visibleNormal) < RESTIR_TEMPORAL_NORMAL_THRESHOLD) return false;

   float currentDepth = length(visibleWorldPos - cameraPosition);
   float historyDepth = length(reservoir.z.visiblePointPos - cameraPosition);
   float maxDepthDelta = max(max(currentDepth, historyDepth) * RESTIR_TEMPORAL_DEPTH_THRESHOLD, RESTIR_TEMPORAL_MIN_DEPTH_DELTA);
   if (abs(currentDepth - historyDepth) > maxDepthDelta) return false;

   return true;
}

void main() {
   ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
   ivec2 extent = ivec2(int(viewWidth), int(viewHeight));
   if (coord.x >= extent.x || coord.y >= extent.y) return;

   vec3 surfacePos;
   vec3 visibleNormal;
   vec3 visibleAlbedo;
   if (!loadSurface(coord, surfacePos, visibleNormal, visibleAlbedo)) {
      setTemporalReservoir(coord, frameCounter % 2, emptyReservoir());
      return;
   }

   vec3 visibleWorldPos = surfacePos + cameraPosition;

   initRNG(coord, frameCounter, randomSeed);

   int temporalSet = frameCounter % 2;
   int previousTemporalSet = 1 - temporalSet;

   Reservoir R;
   R = emptyReservoir();
   float selectedTarget = 0.0;
   bool hasSelectedTarget = false;

   int temporalResetInterval = max(RESTIR_TEMPORAL_RESET_INTERVAL, 1);
   bool temporalResetFrame = RESTIR_TEMPORAL_RESET_INTERVAL > 0
         && ((frameCounter % temporalResetInterval) == 0);
   bool canReuseHistory = frameCounter > 0
         && control.textureReloadDelay == 0u
         && !temporalResetFrame;

   ivec2 previousCoord;
   if (canReuseHistory && reprojectToPreviousCoord(visibleWorldPos, extent, previousCoord)) {
      Reservoir history;
      bool foundHistory = false;

      for (int i = 0; i < RESTIR_TEMPORAL_SEARCH_SAMPLES; i++) {
         ivec2 historyCoord = clamp(previousCoord + temporalSearchOffset(i), ivec2(0), extent - ivec2(1));
         Reservoir candidate;
         getTemporalReservoir(historyCoord, previousTemporalSet, candidate);

         if (validReprojectedReservoir(candidate, visibleWorldPos, visibleNormal)) {
            history = candidate;
            foundHistory = true;
            break;
         }
      }

      if (foundHistory) {
         float historyJacobian = temporalReuseJacobian(history.z, visibleWorldPos);
         history.M = min(history.M, RESTIR_TEMPORAL_M_CLAMP);
         float historyTarget = targetFunction(history.z, visibleWorldPos, visibleNormal, visibleAlbedo);
         float historyShiftedTarget = historyTarget * historyJacobian;
         float historyWeight = historyShiftedTarget > RESTIR_EPS && visibleSample(history.z, visibleWorldPos, visibleNormal)
            ? historyShiftedTarget * history.W * history.M : 0.0;
         if (mergeReservoir(R, history, historyWeight)) {
            selectedTarget = historyTarget; // selectedTarget = historyShiftedTarget;
            hasSelectedTarget = true;
         }
      }
   }

   Sample S;
   getInitialSample(coord, S);
   S.visiblePointPos = visibleWorldPos;
   S.visiblePointNormal = visibleNormal;
   float initialTarget = targetFunction(S, visibleWorldPos, visibleNormal, visibleAlbedo);
   float w = S.samplePdf > RESTIR_EPS ? initialTarget / S.samplePdf : 0.0;
   if (mergeReservoir(R, Reservoir(S, 0.0, 1.0, 0.0), w)) {
      selectedTarget = initialTarget;
      hasSelectedTarget = true;
   }

   R.z.visiblePointPos = visibleWorldPos;
   R.z.visiblePointNormal = visibleNormal;
   if (!hasSelectedTarget) {
      selectedTarget = targetFunction(R.z, visibleWorldPos, visibleNormal, visibleAlbedo);
   }
   R.W = (R.M > 0.0 && R.w_sum > 0.0 && selectedTarget > RESTIR_EPS)
      ? clamp(R.w_sum / (R.M * selectedTarget), 0.0, RESTIR_WEIGHT_CLAMP) : 0.0;
   if (isnan(R.W) || isinf(R.W)) R.W = 0.0;

   setTemporalReservoir(coord, temporalSet, R);
}
