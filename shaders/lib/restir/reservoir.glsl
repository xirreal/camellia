#ifndef RESTIR_RESERVOIR_INCLUDE_GUARD
#define RESTIR_RESERVOIR_INCLUDE_GUARD

#include "/lib/core/rand.glsl"

struct Sample {
   vec3 visiblePointPos; // Xv
   vec3 visiblePointNormal; // Nv
   vec3 samplePointPos; // Xs
   vec3 samplePointNormal; // Ns
   vec3 outgoingRadiance; // Lo
   uint rngState; // paper uses float3 Random
};

struct Reservoir {
   Sample z;
   float w;
   float M;
   float W;
};

// merged reservoir and initial sample buffer
layout(binding = 11, std430) restrict buffer ReservoirBuffer {
   Reservoir reservoirs[];
};

void updateReservoir(inout Reservoir reservoir, Sample Snew, float Wnew) {
   reservoir.M = reservoir.M + 1;
   if (Wnew <= 0.0 || isnan(Wnew) || isinf(Wnew)) return;

   reservoir.w += Wnew;
   if (rand() < Wnew / reservoir.w) {
      reservoir.z = Snew;
   }
}

void mergeReservoirs(inout Reservoir reservoir1, inout Reservoir reservoir2, float p) {
   float M0 = reservoir1.M;
   updateReservoir(reservoir1, reservoir2.z, p * reservoir2.W * reservoir2.M);
   reservoir1.M = M0 + reservoir2.M;
}

Reservoir emptyReservoir() {
   return Reservoir(
      Sample(vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), 0u),
      0.0, 0.0, 0.0
   );
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
   reservoirs[reservoirCoordIndex(coord)].z = Snew;
}

void getInitialSample(ivec2 coord, out Sample S) {
   S = reservoirs[reservoirCoordIndex(coord)].z;
}

void getTemporalReservoir(ivec2 coord, int temporalSet, out Reservoir reservoir) {
   reservoir = reservoirs[temporalReservoirIndex(coord, temporalSet)];
}

void setTemporalReservoir(ivec2 coord, int temporalSet, Reservoir reservoir) {
   reservoirs[temporalReservoirIndex(coord, temporalSet)] = reservoir;
}

#endif // RESTIR_RESERVOIR_INCLUDE_GUARD
