#ifndef CLUSTER_INDEX_BUFFER_INCLUDE_GUARD
#define CLUSTER_INDEX_BUFFER_INCLUDE_GUARD

#ifndef CLUSTER_INDEX_BUFFER_QUALIFIERS
#define CLUSTER_INDEX_BUFFER_QUALIFIERS restrict coherent
#endif

layout(std430, binding = 4) CLUSTER_INDEX_BUFFER_QUALIFIERS buffer ClusterIndexBuffer {
   uint clusterIndices[];
};

#endif
