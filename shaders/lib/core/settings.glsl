#ifndef SETTINGS_INCLUDE_GUARD
#define SETTINGS_INCLUDE_GUARD

// mode 0 = ReSTIR, mode 1 = Reference PT, mode 2 = BVH debug, mode 3 = nothing
#define MODE 0 //[0 1 2 3]

//#define ENABLE_DEBUG_OVERLAY
//#define ENABLE_SORT_VALIDATION
//#define ENABLE_QUAD_VALIDATION
//#define ENTITY_TEXTURES_DEBUG

const float VALIDATION_MAX_QUAD_EXTENT = 64.0; // max player-space span on any axis
const float VALIDATION_COPLANAR_THRESHOLD = 0.15; // max normal deviation (dot < 1-thresh)
const float VALIDATION_DEGEN_AREA_THRESHOLD = 1e-8; // minimum triangle area squared

#endif
