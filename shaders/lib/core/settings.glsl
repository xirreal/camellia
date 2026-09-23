#ifndef SETTINGS_INCLUDE_GUARD
#define SETTINGS_INCLUDE_GUARD

// mode 1 = Reference PT, mode 2 = BVH debug, mode 3 = nothing, mode 4 = Simple RT
#define MODE 1 //[1 2 3 4]

#define BVH_WIDTH 4 //[2 4]
// -1 selects radius 1 for Simple RT and radius 2 for path tracing/debug.
#define HPLOC_SEARCH_RADIUS_SHIFT -1 //[-1 0 1 2 3]

// Stack storage: 0 = shared memory, 1 = image, 2 = invocation-local array
#define BVH_STACK_MODE 0 //[0 1 2]

#define DOF_ENABLED
#define DOF_AUTOFOCUS
#define DOF_FOCAL_LENGTH 35.0   //[17.0 24.0 35.0 50.0 85.0 105.0 135.0 200.0 250.0 300.0]
#define DOF_FSTOP 16.0           //[1.4 1.8 2.0 2.4 2.8 4.0 5.6 8.0 11.0 16.0]
#define DOF_FOCUS_DISTANCE 5.0  //[1.0 2.0 3.0 4.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 100.0]
#define DOF_SENSOR_WIDTH 36.0   //[23.5 28.7 36.0 44.0 53.0]
#define DOF_BLADES 0            //[0 3 4 5 6 7 8 9 10 11 12 13 14 15 16]

#define ENABLE_BLOOM
#define BLOOM_STRENGTH 0.65 //[0.0 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

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
