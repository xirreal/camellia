#ifndef TEXTURES_INCLUDE_GUARD
#define TEXTURES_INCLUDE_GUARD

#ifdef QUAD_WRITE
#include "/lib/scene/textures-write.glsl"
#else
#include "/lib/scene/textures-read.glsl"
#endif

#endif
