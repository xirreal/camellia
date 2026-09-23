// Packed real FFT adapted from atmosphera2/shaders/bloom_fft.comp.
#ifndef BLOOM_FFT_INCLUDE_GUARD
#define BLOOM_FFT_INCLUDE_GUARD

#include "/lib/core/settings.glsl"

layout(rg32f) uniform image2D bloomWorkImg;
layout(rg32f) uniform image2D bloomKernelImg;
layout(rg32f) uniform image2D bloomPupilWorkImg;
layout(rg32f) uniform image2D bloomPupilSpectrumImg;
layout(rgba32f) uniform image2D colorimg6;
uniform sampler2D colortex5;
uniform float viewWidth;
uniform float viewHeight;

layout(local_size_x = 512, local_size_y = 1, local_size_z = 1) in;

const int PASS_SOURCE          = 0;
const int PASS_KERNEL_SOURCE   = 1;
const int PASS_KERNEL_SPECTRUM = 2;
const int PASS_CONVOLVE        = 3;
const int PASS_OUTPUT          = 4;
const int PASS_PUPIL_ROWS      = -2;
const int PASS_PUPIL_COLUMNS   = -1;

// ponytail: 4096 FFT supports full resolution through 3841 pixels per axis;
// raise the FFT and image limits if larger targets must remain full resolution.
const int KERNEL_SIZE = 256;
const int PUPIL_SIZE = 256;
const uint PUPIL_FFT_SIZE = 1024u;
int resolutionScale() {
    return max(1, max(int(ceil(viewWidth / 3841.0)), int(ceil(viewHeight / 3841.0))));
}
ivec2 sourceSize() {
    int scale = resolutionScale();
    return (ivec2(viewWidth, viewHeight) + scale - 1) / scale;
}
ivec2 fftSize() {
    ivec2 needed = sourceSize() + KERNEL_SIZE - 1;
    return ivec2(needed.x <= 2048 ? 2048 : 4096, needed.y <= 2048 ? 2048 : 4096);
}
ivec2 spectrumSize() { return ivec2(fftSize().x, fftSize().y / 2 + 1); }
ivec2 inputSize() { return BLOOM_PASS == PASS_KERNEL_SOURCE || BLOOM_PASS == PASS_KERNEL_SPECTRUM ? fftSize() : sourceSize(); }
ivec2 outputSize() { return sourceSize(); }
const int axis = BLOOM_PASS == PASS_SOURCE || BLOOM_PASS == PASS_KERNEL_SOURCE || BLOOM_PASS == PASS_OUTPUT ? 0 : 1;
const int passMode = BLOOM_PASS;

const uint LOCAL_SIZE   = 512u;
const uint MAX_FFT_SIZE = 4096u;
const float PI          = 3.14159265358979323846;

shared vec2 fftData[MAX_FFT_SIZE];

uint reverseIndex(uint index, uint length) {
    const uint bitCount = uint(findMSB(int(length)));
    return bitfieldReverse(index) >> (32u - bitCount);
}

vec2 complexMultiply(vec2 left, vec2 right) {
    return vec2(left.x * right.x - left.y * right.y, left.x * right.y + left.y * right.x);
}

ivec2 transformCoord(uint line, uint index) {
    return axis == 0 ? ivec2(int(line), int(index)) : ivec2(int(index), int(line));
}

int axisLength(ivec2 size, int selectedAxis) {
    return selectedAxis == 0 ? size.y : size.x;
}

ivec2 planeCoord(ivec2 logicalCoord, uint channel, ivec2 logicalSize) {
    logicalCoord.y += int(channel) * logicalSize.y;
    return logicalCoord;
}

vec2 loadWork(ivec2 coord, uint channel) {
    return imageLoad(bloomWorkImg, planeCoord(coord, channel, spectrumSize())).rg;
}

void storeWork(ivec2 coord, uint channel, vec2 value) {
    imageStore(bloomWorkImg, planeCoord(coord, channel, spectrumSize()), vec4(value, 0.0, 0.0));
}

vec3 prefilterSource(vec3 value) {
    if (any(isnan(value)) || any(isinf(value))) return vec3(0.0);

    float luminance = dot(value, vec3(0.2126, 0.7152, 0.0722));
    return value * smoothstep(1.0, 3.0, luminance) * min(1.0, 5000.0 / max(luminance, 1e-5));
}

float pupilAmplitude(ivec2 coord) {
    ivec2 signedCoord = ivec2(coord.x < int(PUPIL_FFT_SIZE / 2u) ? coord.x : coord.x - int(PUPIL_FFT_SIZE),
                              coord.y < int(PUPIL_FFT_SIZE / 2u) ? coord.y : coord.y - int(PUPIL_FFT_SIZE));
    vec2 position = vec2(signedCoord) + 0.5;
    float radius = 0.5 * float(PUPIL_SIZE - 1);
    #if DOF_BLADES > 2
    float sector = 2.0 * PI / float(DOF_BLADES);
    float angle = atan(position.y, position.x);
    float delta = mod(angle + 0.5 * sector, sector) - 0.5 * sector;
    radius *= cos(0.5 * sector) / cos(delta);
    #endif
    return clamp(0.5 + radius - length(position), 0.0, 1.0);
}

float pupilArea() {
    float radius = 0.5 * float(PUPIL_SIZE - 1);
    #if DOF_BLADES > 2
    return 0.5 * float(DOF_BLADES) * radius * radius * sin(2.0 * PI / float(DOF_BLADES));
    #else
    return PI * radius * radius;
    #endif
}

float pupilIntensityAt(ivec2 signedFrequency) {
    ivec2 coord = (signedFrequency + ivec2(PUPIL_FFT_SIZE)) % ivec2(PUPIL_FFT_SIZE);
    vec2 field = imageLoad(bloomPupilSpectrumImg, coord).rg;
    return dot(field, field);
}

float diffractionAt(vec2 pixel, float wavelengthUm) {
    // Pixel pitch / (f-number * wavelength) converts sensor pixels to lambda/D.
    float pixelPitchUm = 1000.0 * DOF_SENSOR_WIDTH / viewWidth * float(resolutionScale());
    float frequencyScale = float(PUPIL_FFT_SIZE) / float(PUPIL_SIZE)
                         * pixelPitchUm / (DOF_FSTOP * wavelengthUm);
    vec2 frequency = pixel * frequencyScale;
    if (any(greaterThanEqual(abs(frequency), vec2(0.5 * float(PUPIL_FFT_SIZE) - 2.0)))) return 0.0;
    ivec2 lo = ivec2(floor(frequency));
    vec2 t = fract(frequency);
    float a = pupilIntensityAt(lo);
    float b = pupilIntensityAt(lo + ivec2(1, 0));
    float c = pupilIntensityAt(lo + ivec2(0, 1));
    float d = pupilIntensityAt(lo + ivec2(1, 1));
    return mix(mix(a, b, t.x), mix(c, d, t.x), t.y)
         * frequencyScale * frequencyScale / (float(PUPIL_FFT_SIZE * PUPIL_FFT_SIZE) * pupilArea());
}

float cameraPSF(vec2 pixel, uint channel) {
    // Sparse spectral and pixel-area integration of the ideal pupil diffraction.
    float wavelength = channel == 0u ? 0.610 : channel == 1u ? 0.540 : 0.460;
    const int grid = 4;
    float diffraction = 0.0;
    for (int spectral = -1; spectral <= 1; ++spectral) {
        float spectralWeight = spectral == 0 ? 0.5 : 0.25;
        for (int y = 0; y < grid; ++y) {
            for (int x = 0; x < grid; ++x) {
                vec2 subpixel = pixel + (vec2(x, y) + 0.5) / float(grid) - 0.5;
                diffraction += spectralWeight * diffractionAt(subpixel, wavelength + 0.035 * float(spectral))
                             / float(grid * grid);
            }
        }
    }
    float haloRadius = 16.0;
    float halo = pow(1.0 + dot(pixel, pixel) / (haloRadius * haloRadius), -1.5)
               / (2.0 * PI * haloRadius * haloRadius);
    return 0.99 * diffraction + 0.01 * halo;
}

float loadSource(ivec2 coord, bool kernelSource, uint channel) {
    if (kernelSource) {
        ivec2 shifted = ivec2(coord.x < KERNEL_SIZE / 2 ? coord.x : coord.x - fftSize().x,
                              coord.y < KERNEL_SIZE / 2 ? coord.y : coord.y - fftSize().y);
        if (any(greaterThanEqual(abs(shifted), ivec2(KERNEL_SIZE / 2)))) return 0.0;
        return cameraPSF(vec2(shifted), channel);
    }

    if (any(greaterThanEqual(coord, inputSize()))) return 0.0;
    const int scale      = resolutionScale();
    const ivec2 fullSize = textureSize(colortex5, 0);
    const ivec2 origin   = coord * scale;
    vec3 value = vec3(0.0);
    float count = 0.0;
    for (int y = 0; y < scale; ++y)
        for (int x = 0; x < scale; ++x) {
            ivec2 sourceCoord = origin + ivec2(x, y);
            if (all(lessThan(sourceCoord, fullSize))) {
                value += prefilterSource(texelFetch(colortex5, sourceCoord, 0).rgb);
                count += 1.0;
            }
        }
    return value[channel] / max(count, 1.0);
}

void forwardDIF(uint length) {
    barrier();
    for (uint span = length; span >= 2u; span >>= 1u) {
        const uint halfSpan = span >> 1u;
        for (uint butterfly = gl_LocalInvocationID.x; butterfly < length / 2u; butterfly += LOCAL_SIZE) {
            const uint offset = butterfly & (halfSpan - 1u);
            const uint low    = (butterfly << 1u) - offset;
            const uint high   = low + halfSpan;
            const vec2 lowValue  = fftData[low];
            const vec2 highValue = fftData[high];
            const float angle    = -2.0 * PI * float(offset) / float(span);
            const vec2 twiddle   = vec2(cos(angle), sin(angle));

            fftData[low]  = lowValue + highValue;
            fftData[high] = complexMultiply(lowValue - highValue, twiddle);
        }
        barrier();
    }
}

void inverseDIT(uint length) {
    barrier();
    for (uint span = 2u; span <= length; span <<= 1u) {
        const uint halfSpan = span >> 1u;
        for (uint butterfly = gl_LocalInvocationID.x; butterfly < length / 2u; butterfly += LOCAL_SIZE) {
            const uint offset = butterfly & (halfSpan - 1u);
            const uint low    = (butterfly << 1u) - offset;
            const uint high   = low + halfSpan;
            const float angle = 2.0 * PI * float(offset) / float(span);
            const vec2 twiddle = vec2(cos(angle), sin(angle));
            const vec2 lowValue = fftData[low];
            const vec2 rotated  = complexMultiply(fftData[high], twiddle);

            fftData[low]  = lowValue + rotated;
            fftData[high] = lowValue - rotated;
        }
        barrier();
    }
}

void packedForward(uint channel, uint length, uint line) {
    const uint firstLine  = line * 2u;
    const uint secondLine = firstLine + 1u;
    const bool kernelSource = passMode == PASS_KERNEL_SOURCE;

    for (uint index = gl_LocalInvocationID.x; index < length; index += LOCAL_SIZE) {
        const ivec2 firstCoord  = transformCoord(firstLine, index);
        const ivec2 secondCoord = transformCoord(secondLine, index);
        fftData[index] = vec2(loadSource(firstCoord, kernelSource, channel), loadSource(secondCoord, kernelSource, channel));
    }
    forwardDIF(length);

    const uint halfLength = length / 2u;
    const int lineCount   = axisLength(inputSize(), 1 - axis);
    for (uint frequency = gl_LocalInvocationID.x; frequency <= halfLength; frequency += LOCAL_SIZE) {
        const vec2 packedValue     = fftData[reverseIndex(frequency, length)];
        const uint mirrorFrequency = (length - frequency) & (length - 1u);
        const vec2 mirrored        = fftData[reverseIndex(mirrorFrequency, length)] * vec2(1.0, -1.0);
        const vec2 firstSpectrum   = 0.5 * (packedValue + mirrored);
        const vec2 difference      = packedValue - mirrored;
        const vec2 secondSpectrum  = 0.5 * vec2(difference.y, -difference.x);

        storeWork(transformCoord(firstLine, frequency), channel, firstSpectrum);
        if (int(secondLine) < lineCount) storeWork(transformCoord(secondLine, frequency), channel, secondSpectrum);
    }
    if (channel < 2u) barrier();
}

vec2 sampleKernel(ivec2 sceneFrequency, uint channel) {
    vec2 value = imageLoad(bloomKernelImg, planeCoord(sceneFrequency, channel, spectrumSize())).rg;
    float energy = imageLoad(bloomKernelImg, planeCoord(ivec2(0), channel, spectrumSize())).r;
    return value / max(energy, 1e-8);
}

void secondAxisPass(uint channel, uint length, uint line) {
    const int validLength = axisLength(inputSize(), axis);
    for (uint index = gl_LocalInvocationID.x; index < length; index += LOCAL_SIZE) {
        const ivec2 coord = transformCoord(line, index);
        fftData[index]    = int(index) < validLength ? loadWork(coord, channel) : vec2(0.0);
    }
    forwardDIF(length);

    if (passMode == PASS_KERNEL_SPECTRUM) {
        for (uint frequency = gl_LocalInvocationID.x; frequency < length; frequency += LOCAL_SIZE) {
            const ivec2 coord = transformCoord(line, frequency);
            const vec2 value  = fftData[reverseIndex(frequency, length)];
            imageStore(bloomKernelImg, planeCoord(coord, channel, spectrumSize()), vec4(value, 0.0, 0.0));
        }
        if (channel < 2u) barrier();
        return;
    }

    for (uint storageIndex = gl_LocalInvocationID.x; storageIndex < length; storageIndex += LOCAL_SIZE) {
        const uint frequency = reverseIndex(storageIndex, length);
        const ivec2 coord     = transformCoord(line, frequency);
        fftData[storageIndex] = complexMultiply(fftData[storageIndex], sampleKernel(coord, channel));
    }
    inverseDIT(length);

    const float scale = 1.0 / float(length);
    for (uint index = gl_LocalInvocationID.x; index < length; index += LOCAL_SIZE) {
        storeWork(transformCoord(line, index), channel, fftData[index] * scale);
    }
    if (channel < 2u) barrier();
}

vec2 loadHermitian(ivec2 coord, uint channel, bool conjugateValue) {
    vec2 value = loadWork(coord, channel);
    if (conjugateValue) value.y = -value.y;
    return value;
}

void packedInverse(uint channel, uint length, uint line) {
    const uint firstLine  = line * 2u;
    const uint secondLine = firstLine + 1u;
    const uint halfLength = length / 2u;
    const int lineCount   = axisLength(outputSize(), 1 - axis);

    for (uint frequency = gl_LocalInvocationID.x; frequency < length; frequency += LOCAL_SIZE) {
        const bool mirrored = frequency > halfLength;
        const uint storedFrequency = mirrored ? length - frequency : frequency;
        const vec2 firstSpectrum = loadHermitian(transformCoord(firstLine, storedFrequency), channel, mirrored);
        const vec2 secondSpectrum = int(secondLine) < lineCount
                                        ? loadHermitian(transformCoord(secondLine, storedFrequency), channel, mirrored)
                                        : vec2(0.0);
        const vec2 packedValue = vec2(firstSpectrum.x - secondSpectrum.y, firstSpectrum.y + secondSpectrum.x);
        fftData[reverseIndex(frequency, length)] = packedValue;
    }
    inverseDIT(length);

    const float scale = 1.0 / float(length);
    const int outputLength = axisLength(outputSize(), axis);
    for (uint index = gl_LocalInvocationID.x; index < length; index += LOCAL_SIZE) {
        if (int(index) >= outputLength) continue;

        const ivec2 firstCoord = transformCoord(firstLine, index);
        vec4 firstValue = channel == 0u ? vec4(0.0) : imageLoad(colorimg6, firstCoord);
        firstValue[channel] = fftData[index].x * scale;
        imageStore(colorimg6, firstCoord, firstValue);

        if (int(secondLine) < lineCount) {
            const ivec2 secondCoord = transformCoord(secondLine, index);
            vec4 secondValue = channel == 0u ? vec4(0.0) : imageLoad(colorimg6, secondCoord);
            secondValue[channel] = fftData[index].y * scale;
            imageStore(colorimg6, secondCoord, secondValue);
        }
    }
    if (channel < 2u) {
        memoryBarrierImage();
        barrier();
    }
}

void pupilForward() {
    uint line = passMode == PASS_PUPIL_ROWS ? gl_WorkGroupID.y : gl_WorkGroupID.x;
    for (uint index = gl_LocalInvocationID.x; index < PUPIL_FFT_SIZE; index += LOCAL_SIZE) {
        fftData[index] = passMode == PASS_PUPIL_ROWS
            ? vec2(pupilAmplitude(ivec2(index, line)), 0.0)
            : imageLoad(bloomPupilWorkImg, ivec2(line, index)).rg;
    }
    forwardDIF(PUPIL_FFT_SIZE);
    for (uint frequency = gl_LocalInvocationID.x; frequency < PUPIL_FFT_SIZE; frequency += LOCAL_SIZE) {
        vec2 value = fftData[reverseIndex(frequency, PUPIL_FFT_SIZE)];
        if (passMode == PASS_PUPIL_ROWS)
            imageStore(bloomPupilWorkImg, ivec2(frequency, line), vec4(value, 0.0, 0.0));
        else
            imageStore(bloomPupilSpectrumImg, ivec2(line, frequency), vec4(value, 0.0, 0.0));
    }
}

void main() {
    if (passMode == PASS_PUPIL_ROWS || passMode == PASS_PUPIL_COLUMNS) {
        pupilForward();
        return;
    }
    const uint length = uint(axisLength(fftSize(), axis));
    const uint line   = axis == 0 ? gl_WorkGroupID.x : gl_WorkGroupID.y;

    if (axis == 0 && int(line * 2u) >= axisLength(passMode == PASS_KERNEL_SOURCE ? fftSize() : sourceSize(), 1)) return;
    if (axis == 1 && int(line) >= spectrumSize().y) return;

    for (uint channel = 0u; channel < 3u; ++channel) {
        if (passMode == PASS_SOURCE || passMode == PASS_KERNEL_SOURCE)
            packedForward(channel, length, line);
        else if (passMode == PASS_KERNEL_SPECTRUM || passMode == PASS_CONVOLVE)
            secondAxisPass(channel, length, line);
        else
            packedInverse(channel, length, line);
    }
}

#endif
