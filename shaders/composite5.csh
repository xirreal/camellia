#version 460

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

uniform sampler2D colortex6;
uniform sampler2D colortex7;
uniform sampler2D colortex8;
uniform float viewWidth;
uniform float viewHeight;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

uniform int randomSeed;
uniform int frameCounter;

#include "/lib/restir/reservoir.glsl"
#include "/lib/restir/sampling.glsl"

const float RESTIR_TEMPORAL_NORMAL_THRESHOLD = 0.9063078; // cos(25 degrees)
const float RESTIR_TEMPORAL_DEPTH_THRESHOLD = 0.05;
const float RESTIR_TEMPORAL_MIN_DEPTH_DELTA = 0.25;
const float RESTIR_TEMPORAL_SURFACE_BIAS = 0.01;
const float RESTIR_TEMPORAL_M_CLAMP = 30.0;
const float RESTIR_EPS = 1e-6;

// linear srgb luminance
float luminance(vec3 color) {
   return dot(color, vec3(0.2126, 0.7152, 0.0722));
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

float targetFunction(Sample S, vec3 visiblePos, vec3 visibleNormal, vec3 visibleAlbedo) {
   vec3 toSample = S.samplePointPos - visiblePos;
   float dist2 = dot(toSample, toSample);
   if (dist2 <= RESTIR_EPS) return 0.0;

   vec3 wi = toSample * inversesqrt(dist2);
   float cosTheta = max(dot(visibleNormal, wi), 0.0);
   if (cosTheta <= 0.0) return 0.0;

   return max(luminance(S.outgoingRadiance * visibleAlbedo), 0.0) * cosTheta;
}

bool reprojectToPreviousCoord(vec3 playerPos, ivec2 extent, out ivec2 previousCoord) {
   vec3 previousPlayerPos = playerPos + cameraPosition - previousCameraPosition;
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

void rebaseReservoirToCurrentFrame(inout Reservoir reservoir) {
   vec3 delta = previousCameraPosition - cameraPosition;
   reservoir.z.visiblePointPos += delta;
   reservoir.z.samplePointPos += delta;
}

bool validReprojectedReservoir(Reservoir reservoir, vec3 visiblePos, vec3 visibleNormal, vec3 visibleAlbedo) {
   if (reservoir.M <= 0.0 || reservoir.W <= 0.0) return false;
   if (dot(reservoir.z.visiblePointNormal, visibleNormal) < RESTIR_TEMPORAL_NORMAL_THRESHOLD) return false;

   float currentDepth = length(visiblePos);
   float historyDepth = length(reservoir.z.visiblePointPos);
   float maxDepthDelta = max(currentDepth * RESTIR_TEMPORAL_DEPTH_THRESHOLD, RESTIR_TEMPORAL_MIN_DEPTH_DELTA);
   if (abs(currentDepth - historyDepth) > maxDepthDelta) return false;
   if (length(reservoir.z.visiblePointPos - visiblePos) > maxDepthDelta) return false;

   return targetFunction(reservoir.z, visiblePos, visibleNormal, visibleAlbedo) > RESTIR_EPS;
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

   vec3 visiblePos = surfacePos + visibleNormal * RESTIR_TEMPORAL_SURFACE_BIAS;

   initRNG(coord, frameCounter, randomSeed);

   int temporalSet = frameCounter % 2;
   int previousTemporalSet = 1 - temporalSet;

   Reservoir R;
   R = emptyReservoir();

   ivec2 previousCoord;
   if (frameCounter > 0 && reprojectToPreviousCoord(surfacePos, extent, previousCoord)) {
      Reservoir history;
      getTemporalReservoir(previousCoord, previousTemporalSet, history);
      rebaseReservoirToCurrentFrame(history);

      if (validReprojectedReservoir(history, visiblePos, visibleNormal, visibleAlbedo)) {
         history.M = min(history.M, RESTIR_TEMPORAL_M_CLAMP);
         history.z.visiblePointPos = visiblePos;
         history.z.visiblePointNormal = visibleNormal;
         float historyTarget = targetFunction(history.z, visiblePos, visibleNormal, visibleAlbedo);
         mergeReservoirs(R, history, historyTarget);
      }
   }

   Sample S;
   getInitialSample(coord, S);
   S.visiblePointPos = visiblePos;
   S.visiblePointNormal = visibleNormal;
   float w = targetFunction(S, visiblePos, visibleNormal, visibleAlbedo) / uniformHemispherePdf();
   updateReservoir(R, S, w);

   float selectedTarget = targetFunction(R.z, visiblePos, visibleNormal, visibleAlbedo);
   R.W = (R.M > 0.0 && selectedTarget > 0.0)
      ? R.w / (R.M * selectedTarget)
      : 0.0;

   setTemporalReservoir(coord, temporalSet, R);
}
