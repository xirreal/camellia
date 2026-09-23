#version 460
#define BLOOM_PASS -1
const ivec3 workGroups = ivec3(1024, 1, 1);
#include "/lib/post/bloom-fft.glsl"
