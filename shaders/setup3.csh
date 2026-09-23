#version 460
#define BLOOM_PASS -2
const ivec3 workGroups = ivec3(1, 1024, 1);
#include "/lib/post/bloom-fft.glsl"
