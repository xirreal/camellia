#version 460

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba8) uniform writeonly image2D colorimg0;

uniform sampler2D colortex5;
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

void main() {
   ivec2 coord = ivec2(gl_GlobalInvocationID.xy);

   if (coord.x >= int(viewWidth) || coord.y >= int(viewHeight)) return;

   #if MODE == 2 || MODE == 4
   vec3 color = texture(colortex5, vec2(coord + 0.5) / vec2(viewWidth, viewHeight)).rgb;
   #else
   vec3 hdr = texture(colortex5, vec2(coord + 0.5) / vec2(viewWidth, viewHeight)).rgb;
   vec3 color = agxComplete(hdr, agxLut);
   #endif

   color += tpdfDither(coord, frameCounter);

   imageStore(colorimg0, coord, vec4(color, 1.0));
}
