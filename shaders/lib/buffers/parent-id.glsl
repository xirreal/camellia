#ifndef PARENT_ID_BUFFER_INCLUDE_GUARD
#define PARENT_ID_BUFFER_INCLUDE_GUARD

#ifndef PARENT_ID_BUFFER_QUALIFIERS
#define PARENT_ID_BUFFER_QUALIFIERS restrict
#endif

layout(std430, binding = 5) PARENT_ID_BUFFER_QUALIFIERS buffer ParentIDBuffer {
   uint parentIDs[];
};

#endif
