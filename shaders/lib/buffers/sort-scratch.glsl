#ifndef SORT_SCRATCH_BUFFER_INCLUDE_GUARD
#define SORT_SCRATCH_BUFFER_INCLUDE_GUARD

#ifndef SORT_SCRATCH_BUFFER_QUALIFIERS
#define SORT_SCRATCH_BUFFER_QUALIFIERS restrict
#endif

layout(std430, binding = 7) SORT_SCRATCH_BUFFER_QUALIFIERS buffer SortScratchBuffer {
   uint sortScratch[];
};

#endif
