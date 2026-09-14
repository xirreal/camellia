#version 460

#include "/lib/core/settings.glsl"
#include "/lib/core/storage.glsl"

#if BVH_WIDTH == 4
#define BVH4_NODE_BUFFER_QUALIFIERS restrict writeonly
#define BVH4_WRITE
#include "/lib/bvh/wide-build.glsl"
#endif

layout(local_size_x = 128) in;

void main() {
#if BVH_WIDTH == 4
   bvhWideBuild();
#endif
}
