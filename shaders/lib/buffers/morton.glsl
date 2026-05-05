#ifndef MORTON_CODE_BUFFER_INCLUDE_GUARD
#define MORTON_CODE_BUFFER_INCLUDE_GUARD

#ifndef MORTON_CODE_BUFFER_QUALIFIERS
#define MORTON_CODE_BUFFER_QUALIFIERS restrict readonly
#endif

layout(std430, binding = 3) MORTON_CODE_BUFFER_QUALIFIERS buffer MortonCodeBuffer {
   uint mortonCodes[];
};

#endif
