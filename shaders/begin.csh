#version 460 compatibility

#define AS_VERTEX
#include "/lib/storage.glsl"

const ivec3 workGroups = ivec3(1, 1, 1);

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

void main() {
   count = 0u;

   control.data[CTRL_BOUNDS_MIN_X] = 0xFFFFFFFFu;
   control.data[CTRL_BOUNDS_MIN_Y] = 0xFFFFFFFFu;
   control.data[CTRL_BOUNDS_MIN_Z] = 0xFFFFFFFFu;
   control.data[CTRL_BOUNDS_MAX_X] = 0u;
   control.data[CTRL_BOUNDS_MAX_Y] = 0u;
   control.data[CTRL_BOUNDS_MAX_Z] = 0u;

   control.data[CTRL_BVH2_NODE_COUNT] = 0u;
   control.data[CTRL_SORT_TOTAL] = 0u;
   control.data[CTRL_SORT_ERRORS] = 0u;
   control.data[CTRL_PAIR_ERRORS] = 0u;

   control.data[CTRL_PREPARE_DISPATCH_X] = 0u;
   control.data[CTRL_PREPARE_DISPATCH_Y] = 1u;
   control.data[CTRL_PREPARE_DISPATCH_Z] = 1u;

   control.data[CTRL_SORT_DISPATCH_X] = 0u;
   control.data[CTRL_SORT_DISPATCH_Y] = 1u;
   control.data[CTRL_SORT_DISPATCH_Z] = 1u;

   control.data[CTRL_SORT_SCATTER_X] = 0u;
   control.data[CTRL_SORT_SCATTER_Y] = 1u;
   control.data[CTRL_SORT_SCATTER_Z] = 1u;

   control.data[CTRL_HPLOC_DISPATCH_X] = 0u;
   control.data[CTRL_HPLOC_DISPATCH_Y] = 1u;
   control.data[CTRL_HPLOC_DISPATCH_Z] = 1u;
}
