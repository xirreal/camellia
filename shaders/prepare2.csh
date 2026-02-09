#version 460

const ivec3 workGroups = ivec3(16, 1, 1);

#define SORT_PASS 0
#define SORT_PHASE 1

#include "/lib/storage.glsl"
#include "/lib/hploc.glsl"
#include "/lib/sort.glsl"

layout(local_size_x = 256) in;

void main() {
   sortScan();
}
