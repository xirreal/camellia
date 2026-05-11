#version 460 compatibility

uniform int viewWidth;
uniform int viewHeight;
const vec2 workGroupsRender = vec2(1.0, 3.0);

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

#include "lib/restir/reservoir.glsl"

void main() {
   uint gID = gl_GlobalInvocationID.x;
   reservoirs[gID] = Reservoir(
         Sample(vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), 0u),
         0.0, 0.0, 0.0
      );
}
