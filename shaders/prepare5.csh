#version 460

#define SORT_PASS 1
#define SORT_PHASE 0

#include "/lib/storage.glsl"
#include "/lib/hploc.glsl"
#include "/lib/sort.glsl"

layout(local_size_x = 128) in;

void main() {
   sortUpsweep();
}
