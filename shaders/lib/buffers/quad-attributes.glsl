#ifndef QUAD_ATTRIBUTES_BUFFER_INCLUDE_GUARD
#define QUAD_ATTRIBUTES_BUFFER_INCLUDE_GUARD

#ifndef QUAD_ATTRIBUTES_BUFFER_QUALIFIERS
#define QUAD_ATTRIBUTES_BUFFER_QUALIFIERS restrict readonly
#endif

layout(std430, binding = 11) QUAD_ATTRIBUTES_BUFFER_QUALIFIERS buffer QuadAttributesBuffer {
#ifdef QUAD_WRITE
   uint quadAttributeWords[];
#else
   QuadAttributes quadAttributes[];
#endif
};

#endif
