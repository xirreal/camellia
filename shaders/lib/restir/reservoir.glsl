#ifndef RESTIR_RESERVOIR_INCLUDE_GUARD
#define RESTIR_RESERVOIR_INCLUDE_GUARD

#include "/lib/core/settings.glsl"
#include "/lib/core/rand.glsl"

struct Sample {
   vec3 visiblePointPos; // Xv
   vec3 visiblePointNormal; // Nv
   vec3 samplePointPos; // Xs
   vec3 samplePointNormal; // Ns
   vec3 outgoingRadiance; // Lo
   float samplePdf; // p_q
};

struct Reservoir {
   Sample z;
   float w_sum;
   float M;
   float W;
};

struct PackedReservoir {
   vec4 r0; // radiance.xyz, packHalf2x16(w_sum, W)
   vec4 r1; // samplePointPos.xyz, packed sample normal + M
   vec4 r2; // visiblePointPos.xyz, packed visible normal
};

// Merged reservoir and initial sample buffer because SSBO count is tight.
// Initial sample slots store the sample pdf in W.
layout(binding = 11, std430) restrict buffer ReservoirBuffer {
   PackedReservoir reservoirs[];
};

vec2 restirSnz(vec2 v) {
   return vec2((v.x >= 0.0) ? 1.0 : -1.0, (v.y >= 0.0) ? 1.0 : -1.0);
}

vec2 restirEncodeUnitVector(vec3 n) {
   float l1 = abs(n.x) + abs(n.y) + abs(n.z);
   if (l1 <= RESTIR_EPS) return vec2(0.0);

   vec2 p = n.xy / l1;
   if (n.z < 0.0) {
      p = (1.0 - abs(p.yx)) * restirSnz(p);
   }
   return p * 0.5 + 0.5;
}

vec3 restirDecodeUnitVector(vec2 e) {
   vec2 p = e * 2.0 - 1.0;
   vec3 n = vec3(p.x, p.y, 1.0 - abs(p.x) - abs(p.y));
   float t = max(-n.z, 0.0);
   n.x += n.x >= 0.0 ? -t : t;
   n.y += n.y >= 0.0 ? -t : t;
   return normalize(n);
}

uint restirPackNormalAge(vec3 normal, float age) {
   uint packedAge = uint(clamp(round(age), 0.0, RESTIR_M_PACK_MAX)) & 0x1ffu;
   if (dot(normal, normal) <= 0.25) return packedAge;

   vec2 encodedNormal = clamp(restirEncodeUnitVector(normal), vec2(0.0), vec2(1.0));
   uvec2 packedNormal = uvec2(floor(encodedNormal * 2046.0 + 1.0)) & 0x7ffu;
   return packedAge | (packedNormal.x << 9u) | (packedNormal.y << 20u);
}

void restirUnpackNormalAge(uint packedData, out vec3 normal, out float age) {
   age = float(packedData & 0x1ffu);

   uvec2 packedNormal = uvec2((packedData >> 9u) & 0x7ffu, (packedData >> 20u) & 0x7ffu);
   if (packedNormal.x == 0u && packedNormal.y == 0u) {
      normal = vec3(0.0);
      return;
   }

   vec2 encodedNormal = (vec2(packedNormal) - 1.0) / 2046.0;
   normal = restirDecodeUnitVector(encodedNormal);
}

vec2 restirPackableWeights(float wSum, float W) {
   return clamp(vec2(wSum, W), vec2(0.0), vec2(65504.0));
}

PackedReservoir packReservoir(Reservoir reservoir) {
   vec2 weights = restirPackableWeights(reservoir.w_sum, reservoir.W);
   return PackedReservoir(
      vec4(reservoir.z.outgoingRadiance, uintBitsToFloat(packHalf2x16(weights))),
      vec4(reservoir.z.samplePointPos, uintBitsToFloat(restirPackNormalAge(reservoir.z.samplePointNormal, reservoir.M))),
      vec4(reservoir.z.visiblePointPos, uintBitsToFloat(restirPackNormalAge(reservoir.z.visiblePointNormal, 0.0)))
   );
}

Reservoir unpackReservoir(PackedReservoir packedReservoir) {
   vec2 weights = unpackHalf2x16(floatBitsToUint(packedReservoir.r0.w));

   vec3 sampleNormal;
   float M;
   restirUnpackNormalAge(floatBitsToUint(packedReservoir.r1.w), sampleNormal, M);

   vec3 visibleNormal;
   float unusedAge;
   restirUnpackNormalAge(floatBitsToUint(packedReservoir.r2.w), visibleNormal, unusedAge);
   Sample unpackedSample = Sample(
      packedReservoir.r2.xyz,
      visibleNormal,
      packedReservoir.r1.xyz,
      sampleNormal,
      packedReservoir.r0.xyz,
      weights.y
   );

   return Reservoir(unpackedSample, weights.x, M, weights.y);
}

void updateReservoir(inout Reservoir reservoir, Sample Snew, float Wnew) {
   reservoir.M = reservoir.M + 1;
   if (Wnew <= 0.0 || isnan(Wnew) || isinf(Wnew)) return;

   float newWeightSum = reservoir.w_sum + Wnew;
   if (newWeightSum <= 0.0 || isnan(newWeightSum) || isinf(newWeightSum)) return;

   reservoir.w_sum = newWeightSum;
   if (rand() < Wnew / reservoir.w_sum) {
      reservoir.z = Snew;
   }
}

void mergeReservoirs(inout Reservoir reservoir1, inout Reservoir reservoir2, float p) {
   if (reservoir2.M <= 0.0 || reservoir2.W <= 0.0 || p < 0.0 || isnan(p) || isinf(p)) return;

   float M0 = reservoir1.M;
   updateReservoir(reservoir1, reservoir2.z, p * reservoir2.W * reservoir2.M);
   reservoir1.M = M0 + reservoir2.M;
}

bool mergeReservoir(inout Reservoir reservoir, Reservoir candidate, float weight) {
   if (candidate.M <= 0.0 || isnan(candidate.M) || isinf(candidate.M)) return false;
   reservoir.M += candidate.M;

   if (weight <= 0.0 || isnan(weight) || isinf(weight)) return false;

   float baseWeightSum = (reservoir.w_sum > 0.0 && !isnan(reservoir.w_sum) && !isinf(reservoir.w_sum)) ? reservoir.w_sum : 0.0;
   float newWeightSum = baseWeightSum + weight;
   if (newWeightSum <= 0.0 || isnan(newWeightSum) || isinf(newWeightSum)) return false;

   reservoir.w_sum = newWeightSum;
   bool selected = rand() * reservoir.w_sum <= weight;
   if (selected) {
      reservoir.z = candidate.z;
   }

   return selected;
}

Reservoir emptyReservoir() {
   return Reservoir(
      Sample(vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), 0.0),
      0.0, 0.0, 0.0
   );
}

PackedReservoir emptyPackedReservoir() {
   return packReservoir(emptyReservoir());
}

int reservoirPixelCount() {
   return int(viewWidth) * int(viewHeight);
}

int reservoirCoordIndex(ivec2 coord) {
   return coord.x + coord.y * int(viewWidth);
}

int temporalReservoirIndex(ivec2 coord, int temporalSet) {
   return reservoirPixelCount() * (1 + (temporalSet & 1)) + reservoirCoordIndex(coord);
}

void insertInitialSample(ivec2 coord, Sample Snew) {
   reservoirs[reservoirCoordIndex(coord)] = packReservoir(Reservoir(Snew, 0.0, 1.0, Snew.samplePdf));
}

void getInitialSample(ivec2 coord, out Sample S) {
   S = unpackReservoir(reservoirs[reservoirCoordIndex(coord)]).z;
}

void getSpatialReservoir(ivec2 coord, out Reservoir reservoir) {
   reservoir = unpackReservoir(reservoirs[reservoirCoordIndex(coord)]);
}

void setSpatialReservoir(ivec2 coord, Reservoir reservoir) {
   reservoirs[reservoirCoordIndex(coord)] = packReservoir(reservoir);
}

void getTemporalReservoir(ivec2 coord, int temporalSet, out Reservoir reservoir) {
   reservoir = unpackReservoir(reservoirs[temporalReservoirIndex(coord, temporalSet)]);
}

void setTemporalReservoir(ivec2 coord, int temporalSet, Reservoir reservoir) {
   reservoirs[temporalReservoirIndex(coord, temporalSet)] = packReservoir(reservoir);
}

#endif // RESTIR_RESERVOIR_INCLUDE_GUARD
