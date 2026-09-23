#version 460
#define BLOOM_PASS 2
const ivec3 workGroups = ivec3(1, 2049, 1);
#include "/lib/post/bloom-fft.glsl"
