#version 460
#define PATHTRACE

#ifdef PATHTRACE
#include "programs/pt.csh"
#else
#include "programs/rt.csh"
#endif
