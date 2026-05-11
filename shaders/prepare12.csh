#version 460

const ivec3 workGroups = ivec3(256, 1, 1);

#define SORT_PASS 3
#define SORT_PHASE 1

#include "/lib/core/storage.glsl"
#include "/lib/bvh/hploc.glsl"
#include "/lib/bvh/sort.glsl"

layout(local_size_x = 128) in;

void main() {
   sortScan();
}
