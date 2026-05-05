#ifndef AABB_BUFFER_INCLUDE_GUARD
#define AABB_BUFFER_INCLUDE_GUARD

#ifndef AABB_BUFFER_QUALIFIERS
#define AABB_BUFFER_QUALIFIERS restrict readonly
#endif

layout(std430, binding = 2) AABB_BUFFER_QUALIFIERS buffer AABBBuffer {
   AABB aabbs[];
};

#endif
