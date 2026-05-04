#version 460
#define MODE 1 //[0 1 2 3]
#define PATHTRACE 0
#define RAYTRACE 1
#define DEBUG 2

#if MODE == PATHTRACE
#include "programs/pt.csh"
#elif MODE == RAYTRACE
#include "programs/rt.csh"
#elif MODE == DEBUG
#include "programs/debug.csh"
#else

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

void main() {
   return;
}
#endif
