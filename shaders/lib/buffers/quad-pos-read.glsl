#ifndef QUAD_POS_READ_BUFFER_INCLUDE_GUARD
#define QUAD_POS_READ_BUFFER_INCLUDE_GUARD

#ifndef QUAD_POS_READ_BUFFER_QUALIFIERS
#define QUAD_POS_READ_BUFFER_QUALIFIERS restrict readonly
#endif

layout(std430, binding = 10) QUAD_POS_READ_BUFFER_QUALIFIERS buffer QuadPosBuffer {
   QuadPositions quadPositions[];
};

#endif
