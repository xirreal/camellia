#ifndef RAND_INCLUDE_GUARD
#define RAND_INCLUDE_GUARD

uint rngState;

uint pcgHash() {
   uint state = rngState;
   rngState = rngState * 747796405u + 2891336453u;
   uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
   return (word >> 22u) ^ word;
}

uint hash_u32(uint x) {
   // Murmur3 finalizer
   x ^= x >> 16u;
   x *= 0x45d9f3bu;
   x ^= x >> 16u;
   return x;
}

void initRNG(ivec2 coord, int frame, int _seed) {
   rngState = hash_u32(uint(coord.x))
         ^ hash_u32(uint(coord.y) + 1000003u)
         ^ hash_u32(uint(frame) + 2000003u)
         ^ hash_u32(uint(_seed));
   pcgHash();
}

float rand() {
   return float(pcgHash()) / 4294967295.0;
}

#endif
