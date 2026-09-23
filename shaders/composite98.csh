#version 460

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba8) uniform writeonly image2D colorimg0;

uniform sampler2D colortex5;
uniform sampler2D colortex6;
uniform sampler2D agxLut;
uniform float viewWidth;
uniform float viewHeight;
uniform int frameCounter;

#include "/lib/core/settings.glsl"
#include "/lib/post/agx.glsl"

float _ditherHash(vec3 p) {
   p = fract(p * 0.1031);
   p += dot(p, p.zyx + 31.32);
   return fract((p.x + p.y) * p.z);
}

vec3 tpdfDither(ivec2 coord, int frame) {
   vec3 c = vec3(coord, frame);
   float r0 = _ditherHash(c + vec3(0.0, 0.0, 0.0));
   float r1 = _ditherHash(c + vec3(0.0, 0.0, 1.0));
   float r2 = _ditherHash(c + vec3(0.0, 1.0, 0.0));
   float r3 = _ditherHash(c + vec3(0.0, 1.0, 1.0));
   float r4 = _ditherHash(c + vec3(1.0, 0.0, 0.0));
   float r5 = _ditherHash(c + vec3(1.0, 0.0, 1.0));
   return vec3(r0 - r1, r2 - r3, r4 - r5) / 255.0;
}

#if MODE == 1
#ifdef ENABLE_BLOOM
vec3 sampleBloom(ivec2 coord) {
   float scale = max(1.0, max(ceil(viewWidth / 3841.0), ceil(viewHeight / 3841.0)));
   if (scale == 1.0) return texelFetch(colortex6, coord, 0).rgb;
   vec2 position = (vec2(coord) + 0.5) / scale - 0.5;
   ivec2 lo = ivec2(floor(position));
   ivec2 hi = lo + 1;
   ivec2 last = ivec2(ceil(vec2(viewWidth, viewHeight) / scale)) - 1;
   vec2 t = fract(position);
   vec3 a = texelFetch(colortex6, clamp(lo, ivec2(0), last), 0).rgb;
   vec3 b = texelFetch(colortex6, clamp(ivec2(hi.x, lo.y), ivec2(0), last), 0).rgb;
   vec3 c = texelFetch(colortex6, clamp(ivec2(lo.x, hi.y), ivec2(0), last), 0).rgb;
   vec3 d = texelFetch(colortex6, clamp(hi, ivec2(0), last), 0).rgb;
   return mix(mix(a, b, t.x), mix(c, d, t.x), t.y);
}
#endif
#endif

void main() {
   ivec2 coord = ivec2(gl_GlobalInvocationID.xy);

   if (coord.x >= int(viewWidth) || coord.y >= int(viewHeight)) return;

   #if MODE == 2 || MODE == 4
   vec3 color = texture(colortex5, vec2(coord + 0.5) / vec2(viewWidth, viewHeight)).rgb;
   #else
   vec3 hdr = texture(colortex5, vec2(coord + 0.5) / vec2(viewWidth, viewHeight)).rgb;
   #if MODE == 1
   #ifdef ENABLE_BLOOM
   hdr += BLOOM_STRENGTH * sampleBloom(coord);
   #endif
   #endif
   vec3 color = agxComplete(hdr, agxLut);
   #endif

   color += tpdfDither(coord, frameCounter);

   imageStore(colorimg0, coord, vec4(color, 1.0));
}
