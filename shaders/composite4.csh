#version 460

#define SORT_PASS 0
#define SORT_PHASE 2

#include "/lib/core/storage.glsl"
#include "/lib/bvh/hploc.glsl"
#include "/lib/bvh/sort.glsl"

layout(local_size_x = 256) in;

void main() {
   sortDownsweep();
}
