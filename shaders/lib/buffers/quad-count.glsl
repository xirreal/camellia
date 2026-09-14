#ifndef QUAD_COUNT_BUFFER_INCLUDE_GUARD
#define QUAD_COUNT_BUFFER_INCLUDE_GUARD

#ifndef QUAD_COUNT_BUFFER_QUALIFIERS
#define QUAD_COUNT_BUFFER_QUALIFIERS restrict
#endif

layout(std430, binding = 0) QUAD_COUNT_BUFFER_QUALIFIERS buffer QuadCountBuffer {
   uint quadCount;
};

#endif
