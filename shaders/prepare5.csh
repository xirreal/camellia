#version 460

#define SORT_PASS 1
#define SORT_PHASE 0

#include "/lib/core/storage.glsl"
#include "/lib/bvh/hploc.glsl"
#include "/lib/bvh/sort.glsl"

layout(local_size_x = 128) in;

void main() {
   sortUpsweep();
}
