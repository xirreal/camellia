#ifndef QUAD_GEOMETRY_BUFFER_INCLUDE_GUARD
#define QUAD_GEOMETRY_BUFFER_INCLUDE_GUARD

#ifndef QUAD_GEOMETRY_BUFFER_QUALIFIERS
#define QUAD_GEOMETRY_BUFFER_QUALIFIERS restrict readonly
#endif

layout(std430, binding = 10) QUAD_GEOMETRY_BUFFER_QUALIFIERS buffer QuadGeometryBuffer {
#ifdef QUAD_WRITE
   uvec2 quadGeometryWords[];
#else
   QuadGeometry quadGeometry[];
#endif
};

#endif
