#ifndef QUAD_DATA_BUFFER_INCLUDE_GUARD
#define QUAD_DATA_BUFFER_INCLUDE_GUARD

#ifndef QUAD_DATA_BUFFER_QUALIFIERS
#define QUAD_DATA_BUFFER_QUALIFIERS restrict readonly
#endif

layout(std430, binding = 0) QUAD_DATA_BUFFER_QUALIFIERS buffer QuadDataBuffer {
   uint quadCount;
   QuadData quadData[];
};

#endif
