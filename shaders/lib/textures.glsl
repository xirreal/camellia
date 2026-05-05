#ifndef TEXTURES_INCLUDE_GUARD
#define TEXTURES_INCLUDE_GUARD

#ifdef QUAD_WRITE
#include "/lib/textures-write.glsl"
#else
#include "/lib/textures-read.glsl"
#endif

#endif
