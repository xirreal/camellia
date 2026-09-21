#ifndef SETTINGS_INCLUDE_GUARD
#define SETTINGS_INCLUDE_GUARD

// mode 1 = Reference PT, mode 2 = BVH debug, mode 3 = nothing, mode 4 = Simple RT
#define MODE 1 //[1 2 3 4]

#define BVH_WIDTH 4 //[2 4]
// -1 selects radius 1 for Simple RT and radius 2 for path tracing/debug.
#define HPLOC_SEARCH_RADIUS_SHIFT -1 //[-1 0 1 2 3]

// Stack storage: 0 = shared memory, 1 = image, 2 = invocation-local array
#define BVH_STACK_MODE 0 //[0 1 2]

#define ENTITY_TEXTURES
//#define ENTITY_PBR

#define ENABLE_GBUFFER_CAPTURE
#define SHADOW_CAPTURE_DISTANCE 128 //[128 256 512 1024]

const int shadowMapResolution = 256;

//#define ENABLE_DEBUG_OVERLAY
//#define ENABLE_SORT_VALIDATION
//#define ENABLE_QUAD_VALIDATION
//#define ENABLE_SUBGROUP_VALIDATION
//#define ENTITY_TEXTURES_DEBUG

const float VALIDATION_MAX_QUAD_EXTENT = 64.0; // max player-space span on any axis
const float VALIDATION_COPLANAR_THRESHOLD = 0.15; // max normal deviation (dot < 1-thresh)
const float VALIDATION_DEGEN_AREA_THRESHOLD = 1e-8; // minimum triangle area squared

#endif
