#version 460 compatibility

#include "/lib/core/settings.glsl"

#if SHADOW_CAPTURE_DISTANCE == 128
const float shadowDistance = 128.0;
#elif SHADOW_CAPTURE_DISTANCE == 256
const float shadowDistance = 256.0;
#elif SHADOW_CAPTURE_DISTANCE == 512
const float shadowDistance = 512.0;
#else
const float shadowDistance = 1024.0;
#endif

#ifdef ENABLE_GBUFFER_CAPTURE
#pragma just_fucking_make_this_an_option
#endif

const float shadowDistanceRenderMul = 1.0;
const float sunPathRotation = -40.0;
/*
const int colortex5Format = RGBA32F;
const int colortex8Format = RGBA32F;
const int colortex9Format = RGBA32F;
const int colortex10Format = RGBA32F;
const int colortex11Format = RGBA32F;
*/
const bool colortex5Clear = false;

void main() {
   discard;
}
