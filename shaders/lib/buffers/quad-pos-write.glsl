#ifndef QUAD_POS_WRITE_BUFFER_INCLUDE_GUARD
#define QUAD_POS_WRITE_BUFFER_INCLUDE_GUARD

#ifndef QUAD_POS_WRITE_BUFFER_QUALIFIERS
#define QUAD_POS_WRITE_BUFFER_QUALIFIERS restrict writeonly
#endif

layout(std430, binding = 10) QUAD_POS_WRITE_BUFFER_QUALIFIERS buffer QuadPosBuffer {
   float quadPosData[];
};

#endif
