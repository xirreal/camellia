# Camellia: third-party notices and research credits

Camellia's original contributions are covered by [LICENSE](LICENSE). The
restrictions in that license do not replace or limit upstream rights. Preserve
this file and the applicable files in `licenses/` in release archives and any
authorized derivative. These notices document the sources identified during the
14 September 2026 review; unresolved provenance is listed explicitly below.

## H-PLOC research

Carsten Benthin, Daniel Meister, Joshua Barczak, Rohan Mehalwal, John Tsakok,
and Andrew Kensler (2024). **H-PLOC: Hierarchical Parallel Locally-Ordered
Clustering for Bounding Volume Hierarchy Construction.** Proceedings of the
ACM on Computer Graphics and Interactive Techniques 7(3), 14 pages.
[DOI: 10.1145/3675377](https://doi.org/10.1145/3675377).
[Author paper](https://gpuopen.com/download/HPLOC.pdf).

Used as the algorithmic reference for `shaders/composite16.csh` and
`shaders/lib/bvh/hploc*.glsl` and `wide-build.glsl`. The paper is credited,
not relicensed or bundled. Its authors retain their rights; credit does not
imply their endorsement of Camellia.

## H-PLOC Slang implementation

Copyright (c) 2024 Nathan V. Morrical (natevm).
[Source](https://gist.github.com/natevm/6618402427ad6466bf555d67602adfa8),
reviewed revision `dd14f493416b80fce09a086fc9e770cb8dbbe688`.
[MIT license](licenses/HPLOC-MIT.txt).

Camellia's H-PLOC code is a modified GLSL port with changes to storage,
subgroup processing, dispatch, and wide-node construction. The upstream
implementation remains MIT-licensed; Camellia's license does not withdraw
those permissions.

## GPUSorting

Copyright (c) 2024 Thomas Smith (b0nes164).
[Source](https://github.com/b0nes164/GPUSorting).
Camellia's `shaders/lib/bvh/sort.glsl` is an adapted GLSL implementation.
[Upstream license and third-party notices](licenses/GPUSorting.txt), copied
unchanged from revision `09a6081d964b682bbb58838b83ab75aebe7f4e05`.

GPUSorting's own code is MIT-licensed. Its complete upstream notices are
retained because it also credits other implementations; this does not assert
that every component named in that upstream bundle is present in Camellia.
