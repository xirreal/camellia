#version 460
#define BLOOM_PASS 4
const ivec3 workGroups = ivec3(2048, 1, 1);
#include "/lib/post/bloom-fft.glsl"
