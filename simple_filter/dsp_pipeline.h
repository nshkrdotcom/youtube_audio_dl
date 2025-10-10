#pragma once

#include <vector>
#include <memory>
#include <functional>
#include <cmath>
#include <algorithm>
#include <stdexcept>
#include <string>

namespace DSP {

// ============================================================================
// Base Types
// ============================================================================

using Sample = float;
using Buffer = std::vector<Sample>;
using SampleRate = float;

// ============================================================================
// Abstract Base Classes for Pipeline Composition
// ============================================================================

// Base class for all processing nodes
class AudioProcessor {
public:
    virtual ~AudioProcessor() = default;
    virtual void prepare(SampleRate sampleRate, int maxBlockSize) = 0;
    virtual void process(Buffer& buffer) = 0;
    virtual void reset() = 0;
};

// Base class for filters
class Filter : public AudioProcessor {
public:
    virtual ~Filter() = default;
};

// Base class for analysis modules
class Analyzer {
public:
    virtual ~Analyzer() = default;
    virtual void prepare(SampleRate sampleRate, int frameSize) = 0;
    virtual void analyze(const Buffer& buffer) = 0;
    virtual void reset() = 0;
};

// ============================================================================
// Biquad Filter Building Block
// ============================================================================

class Biquad : public Filter {
public:
    Biquad() : x1(0), x2(0), y1(0), y2(0), b0(1), b1(0), b2(0), a1(0), a2(0) {}

    void setCoefficients(Sample b0, Sample b1, Sample b2, Sample a1, Sample a2) {
        this->b0 = b0;
        this->b1 = b1;
        this->b2 = b2;
        this->a1 = a1;
        this->a2 = a2;
    }

    void prepare(SampleRate sampleRate, int maxBlockSize) override {
        reset();
    }

    void process(Buffer& buffer) override {
        for (auto& sample : buffer) {
            sample = processSample(sample);
        }
    }

    Sample processSample(Sample x0) {
        Sample y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
        x2 = x1;
        x1 = x0;
        y2 = y1;
        y1 = y0;
        return y0;
    }

    void reset() override {
        x1 = x2 = y1 = y2 = 0;
    }

private:
    Sample b0, b1, b2, a1, a2;
    Sample x1, x2, y1, y2;
};

// ============================================================================
// Filter Designers (Calculate Coefficients)
// ============================================================================

namespace FilterDesign {

struct BiquadCoeffs {
    Sample b0, b1, b2, a1, a2;
};

// Butterworth 2nd-order lowpass
inline BiquadCoeffs butterworthLowpass2(Sample cutoffHz, SampleRate sampleRate, Sample q) {
    Sample w0 = 2.0f * M_PI * cutoffHz / sampleRate;
    Sample cosw0 = std::cos(w0);
    Sample sinw0 = std::sin(w0);
    Sample alpha = sinw0 / (2.0f * q);

    Sample a0 = 1.0f + alpha;
    Sample a1 = -2.0f * cosw0;
    Sample a2 = 1.0f - alpha;
    Sample b0 = (1.0f - cosw0) / 2.0f;
    Sample b1 = 1.0f - cosw0;
    Sample b2 = (1.0f - cosw0) / 2.0f;

    return {b0/a0, b1/a0, b2/a0, a1/a0, a2/a0};
}

// Butterworth 2nd-order highpass
inline BiquadCoeffs butterworthHighpass2(Sample cutoffHz, SampleRate sampleRate, Sample q) {
    Sample w0 = 2.0f * M_PI * cutoffHz / sampleRate;
    Sample cosw0 = std::cos(w0);
    Sample sinw0 = std::sin(w0);
    Sample alpha = sinw0 / (2.0f * q);

    Sample a0 = 1.0f + alpha;
    Sample a1 = -2.0f * cosw0;
    Sample a2 = 1.0f - alpha;
    Sample b0 = (1.0f + cosw0) / 2.0f;
    Sample b1 = -(1.0f + cosw0);
    Sample b2 = (1.0f + cosw0) / 2.0f;

    return {b0/a0, b1/a0, b2/a0, a1/a0, a2/a0};
}

// Bandpass filter
inline BiquadCoeffs bandpass(Sample centerHz, Sample q, SampleRate sampleRate) {
    Sample w0 = 2.0f * M_PI * centerHz / sampleRate;
    Sample cosw0 = std::cos(w0);
    Sample sinw0 = std::sin(w0);
    Sample alpha = sinw0 / (2.0f * q);

    Sample a0 = 1.0f + alpha;
    Sample a1 = -2.0f * cosw0;
    Sample a2 = 1.0f - alpha;
    Sample b0 = alpha;
    Sample b1 = 0.0f;
    Sample b2 = -alpha;

    return {b0/a0, b1/a0, b2/a0, a1/a0, a2/a0};
}

} // namespace FilterDesign

// ============================================================================
// Cascaded Multi-Pole Filters
// ============================================================================

class Butterworth4PoleLowpass : public Filter {
public:
    Butterworth4PoleLowpass(Sample cutoffHz, SampleRate sampleRate) {
        // Q values for 4-pole Butterworth (maximally flat)
        auto coeffs1 = FilterDesign::butterworthLowpass2(cutoffHz, sampleRate, 0.54119610f);
        auto coeffs2 = FilterDesign::butterworthLowpass2(cutoffHz, sampleRate, 1.3065630f);

        biquad1.setCoefficients(coeffs1.b0, coeffs1.b1, coeffs1.b2, coeffs1.a1, coeffs1.a2);
        biquad2.setCoefficients(coeffs2.b0, coeffs2.b1, coeffs2.b2, coeffs2.a1, coeffs2.a2);
    }

    void prepare(SampleRate sampleRate, int maxBlockSize) override {
        biquad1.prepare(sampleRate, maxBlockSize);
        biquad2.prepare(sampleRate, maxBlockSize);
    }

    void process(Buffer& buffer) override {
        biquad1.process(buffer);
        biquad2.process(buffer);
    }

    void reset() override {
        biquad1.reset();
        biquad2.reset();
    }

private:
    Biquad biquad1, biquad2;
};

class Butterworth4PoleHighpass : public Filter {
public:
    Butterworth4PoleHighpass(Sample cutoffHz, SampleRate sampleRate) {
        auto coeffs1 = FilterDesign::butterworthHighpass2(cutoffHz, sampleRate, 0.54119610f);
        auto coeffs2 = FilterDesign::butterworthHighpass2(cutoffHz, sampleRate, 1.3065630f);

        biquad1.setCoefficients(coeffs1.b0, coeffs1.b1, coeffs1.b2, coeffs1.a1, coeffs1.a2);
        biquad2.setCoefficients(coeffs2.b0, coeffs2.b1, coeffs2.b2, coeffs2.a1, coeffs2.a2);
    }

    void prepare(SampleRate sampleRate, int maxBlockSize) override {
        biquad1.prepare(sampleRate, maxBlockSize);
        biquad2.prepare(sampleRate, maxBlockSize);
    }

    void process(Buffer& buffer) override {
        biquad1.process(buffer);
        biquad2.process(buffer);
    }

    void reset() override {
        biquad1.reset();
        biquad2.reset();
    }

private:
    Biquad biquad1, biquad2;
};

class BandpassFilter : public Filter {
public:
    BandpassFilter(Sample lowHz, Sample highHz, SampleRate sampleRate) {
        Sample centerHz = std::sqrt(lowHz * highHz);
        Sample bandwidth = highHz - lowHz;
        Sample q = centerHz / bandwidth;

        auto coeffs = FilterDesign::bandpass(centerHz, q, sampleRate);
        biquad.setCoefficients(coeffs.b0, coeffs.b1, coeffs.b2, coeffs.a1, coeffs.a2);
    }

    void prepare(SampleRate sampleRate, int maxBlockSize) override {
        biquad.prepare(sampleRate, maxBlockSize);
    }

    void process(Buffer& buffer) override {
        biquad.process(buffer);
    }

    void reset() override {
        biquad.reset();
    }

private:
    Biquad biquad;
};

// ============================================================================
// Window Functions for FFT
// ============================================================================

namespace Window {

inline Buffer hann(int size) {
    Buffer window(size);
    for (int i = 0; i < size; i++) {
        window[i] = 0.5f * (1.0f - std::cos(2.0f * M_PI * i / (size - 1)));
    }
    return window;
}

inline Buffer hamming(int size) {
    Buffer window(size);
    for (int i = 0; i < size; i++) {
        window[i] = 0.54f - 0.46f * std::cos(2.0f * M_PI * i / (size - 1));
    }
    return window;
}

inline Buffer blackman(int size) {
    Buffer window(size);
    for (int i = 0; i < size; i++) {
        Sample t = static_cast<Sample>(i) / (size - 1);
        window[i] = 0.42f - 0.5f * std::cos(2.0f * M_PI * t) + 0.08f * std::cos(4.0f * M_PI * t);
    }
    return window;
}

} // namespace Window

// ============================================================================
// Simple FFT (Cooley-Tukey radix-2)
// ============================================================================

class FFT {
public:
    struct Complex {
        Sample real, imag;

        Complex(Sample r = 0, Sample i = 0) : real(r), imag(i) {}

        Sample magnitude() const {
            return std::sqrt(real * real + imag * imag);
        }

        Complex operator+(const Complex& other) const {
            return {real + other.real, imag + other.imag};
        }

        Complex operator-(const Complex& other) const {
            return {real - other.real, imag - other.imag};
        }

        Complex operator*(const Complex& other) const {
            return {
                real * other.real - imag * other.imag,
                real * other.imag + imag * other.real
            };
        }
    };

    FFT(int size) : size_(size) {
        if (size & (size - 1)) {
            throw std::runtime_error("FFT size must be power of 2");
        }
    }

    void forward(const Buffer& input, std::vector<Complex>& output) {
        int n = input.size();
        output.resize(n);

        // Copy input to output as complex numbers
        for (int i = 0; i < n; i++) {
            output[i] = Complex(input[i], 0);
        }

        // Bit-reversal permutation
        for (int i = 1, j = 0; i < n; i++) {
            int bit = n >> 1;
            for (; j & bit; bit >>= 1) {
                j ^= bit;
            }
            j ^= bit;
            if (i < j) {
                std::swap(output[i], output[j]);
            }
        }

        // Cooley-Tukey FFT
        for (int len = 2; len <= n; len <<= 1) {
            Sample angle = -2.0f * M_PI / len;
            Complex wlen(std::cos(angle), std::sin(angle));

            for (int i = 0; i < n; i += len) {
                Complex w(1, 0);
                for (int j = 0; j < len / 2; j++) {
                    Complex u = output[i + j];
                    Complex v = output[i + j + len / 2] * w;
                    output[i + j] = u + v;
                    output[i + j + len / 2] = u - v;
                    w = w * wlen;
                }
            }
        }
    }

    std::vector<Sample> getMagnitudes(const std::vector<Complex>& spectrum) {
        std::vector<Sample> mags(spectrum.size());
        for (size_t i = 0; i < spectrum.size(); i++) {
            mags[i] = spectrum[i].magnitude();
        }
        return mags;
    }

private:
    int size_;
};

// ============================================================================
// Processing Pipeline - Composable Chain
// ============================================================================

class ProcessingChain : public AudioProcessor {
public:
    ProcessingChain& add(std::unique_ptr<AudioProcessor> processor) {
        processors_.push_back(std::move(processor));
        return *this;
    }

    void prepare(SampleRate sampleRate, int maxBlockSize) override {
        for (auto& proc : processors_) {
            proc->prepare(sampleRate, maxBlockSize);
        }
    }

    void process(Buffer& buffer) override {
        for (auto& proc : processors_) {
            proc->process(buffer);
        }
    }

    void reset() override {
        for (auto& proc : processors_) {
            proc->reset();
        }
    }

private:
    std::vector<std::unique_ptr<AudioProcessor>> processors_;
};

// ============================================================================
// Onset Detection via Spectral Flux
// ============================================================================

class SpectralFluxDetector : public Analyzer {
public:
    SpectralFluxDetector(int fftSize, int hopSize)
        : fftSize_(fftSize)
        , hopSize_(hopSize)
        , fft_(fftSize)
        , window_(Window::hann(fftSize))
    {
    }

    void prepare(SampleRate sampleRate, int frameSize) override {
        sampleRate_ = sampleRate;
        previousMagnitudes_.clear();
        previousMagnitudes_.resize(fftSize_ / 2, 0.0f);
        noveltyFunction_.clear();
        reset();
    }

    void analyze(const Buffer& buffer) override {
        // Frame the buffer with overlap
        for (size_t i = 0; i + fftSize_ <= buffer.size(); i += hopSize_) {
            Buffer frame(fftSize_);

            // Extract and window frame
            for (int j = 0; j < fftSize_; j++) {
                frame[j] = buffer[i + j] * window_[j];
            }

            // Compute FFT
            std::vector<FFT::Complex> spectrum;
            fft_.forward(frame, spectrum);
            auto magnitudes = fft_.getMagnitudes(spectrum);

            // Calculate spectral flux (half-wave rectified difference)
            Sample flux = 0.0f;
            for (size_t bin = 0; bin < fftSize_ / 2; bin++) {
                Sample diff = magnitudes[bin] - previousMagnitudes_[bin];
                if (diff > 0) {
                    flux += diff;
                }
            }

            noveltyFunction_.push_back(flux);
            previousMagnitudes_ = magnitudes;
        }
    }

    const std::vector<Sample>& getNoveltyFunction() const {
        return noveltyFunction_;
    }

    // Find peaks in novelty function with adaptive threshold
    std::vector<int> findOnsets(Sample multiplier = 1.5f, int medianWindowSize = 10) {
        std::vector<int> onsets;

        for (size_t i = medianWindowSize; i < noveltyFunction_.size() - medianWindowSize; i++) {
            // Calculate local median as adaptive threshold
            std::vector<Sample> window;
            for (int j = -medianWindowSize; j <= medianWindowSize; j++) {
                window.push_back(noveltyFunction_[i + j]);
            }
            std::sort(window.begin(), window.end());
            Sample threshold = window[window.size() / 2] * multiplier;

            // Check if current point is a peak above threshold
            Sample current = noveltyFunction_[i];
            if (current > threshold &&
                current > noveltyFunction_[i - 1] &&
                current > noveltyFunction_[i + 1]) {

                // Convert frame index to sample index
                int sampleIndex = i * hopSize_;
                onsets.push_back(sampleIndex);
            }
        }

        return onsets;
    }

    void reset() override {
        noveltyFunction_.clear();
        std::fill(previousMagnitudes_.begin(), previousMagnitudes_.end(), 0.0f);
    }

private:
    int fftSize_;
    int hopSize_;
    SampleRate sampleRate_;
    FFT fft_;
    Buffer window_;
    std::vector<Sample> previousMagnitudes_;
    std::vector<Sample> noveltyFunction_;
};

// ============================================================================
// Normalization Processors
// ============================================================================

class PeakNormalizer : public AudioProcessor {
public:
    PeakNormalizer(Sample targetPeak_dB = -0.1f)
        : targetPeak_dB_(targetPeak_dB)
    {
        targetPeak_linear_ = std::pow(10.0f, targetPeak_dB / 20.0f);
    }

    void prepare(SampleRate sampleRate, int maxBlockSize) override {}

    void process(Buffer& buffer) override {
        // Step 1: Find current peak
        Sample currentPeak = 0.0f;
        for (Sample sample : buffer) {
            currentPeak = std::max(currentPeak, std::abs(sample));
        }

        // Step 2: Check if normalization needed
        if (currentPeak == 0.0f) {
            return; // Silent audio, no normalization needed
        }

        // Step 3: Calculate gain factor
        Sample gainFactor = targetPeak_linear_ / currentPeak;

        // Step 4: Apply gain to all samples
        for (Sample& sample : buffer) {
            sample *= gainFactor;
        }
    }

    void reset() override {}

    void setTargetPeak(Sample targetPeak_dB) {
        targetPeak_dB_ = targetPeak_dB;
        targetPeak_linear_ = std::pow(10.0f, targetPeak_dB / 20.0f);
    }

private:
    Sample targetPeak_dB_;
    Sample targetPeak_linear_;
};

class RMSNormalizer : public AudioProcessor {
public:
    RMSNormalizer(Sample targetRMS_dB = -14.0f)
        : targetRMS_dB_(targetRMS_dB)
    {
        targetRMS_linear_ = std::pow(10.0f, targetRMS_dB / 20.0f);
    }

    void prepare(SampleRate sampleRate, int maxBlockSize) override {}

    void process(Buffer& buffer) override {
        // Step 1: Calculate current RMS
        Sample sumOfSquares = 0.0f;
        for (Sample sample : buffer) {
            sumOfSquares += sample * sample;
        }

        Sample meanOfSquares = sumOfSquares / buffer.size();
        Sample currentRMS = std::sqrt(meanOfSquares);

        // Step 2: Check if normalization needed
        if (currentRMS == 0.0f) {
            return; // Silent audio
        }

        // Step 3: Calculate gain factor
        Sample gainFactor = targetRMS_linear_ / currentRMS;

        // Step 4: Apply gain
        for (Sample& sample : buffer) {
            sample *= gainFactor;
        }

        // Step 5: Clipping protection - find peak after gain
        Sample peakAfterGain = 0.0f;
        for (Sample sample : buffer) {
            peakAfterGain = std::max(peakAfterGain, std::abs(sample));
        }

        // Step 6: If clipping would occur, reduce gain
        if (peakAfterGain > 1.0f) {
            Sample clippingCorrectionFactor = 1.0f / peakAfterGain;
            for (Sample& sample : buffer) {
                sample *= clippingCorrectionFactor;
            }
        }
    }

    void reset() override {}

    void setTargetRMS(Sample targetRMS_dB) {
        targetRMS_dB_ = targetRMS_dB;
        targetRMS_linear_ = std::pow(10.0f, targetRMS_dB / 20.0f);
    }

private:
    Sample targetRMS_dB_;
    Sample targetRMS_linear_;
};

// ============================================================================
// Multi-Band Onset Detector (Parallel Band Analysis)
// ============================================================================

struct OnsetDetectionConfig {
    struct Band {
        Sample lowHz;
        Sample highHz;
        Sample weight;
        std::string name;
    };

    int fftSize = 2048;
    int hopSize = 512;
    Sample medianMultiplier = 1.5f;
    int medianWindowSize = 10;
    std::vector<Band> bands;

    static OnsetDetectionConfig drumDetection() {
        OnsetDetectionConfig config;
        config.bands = {
            {60.0f, 200.0f, 1.0f, "low"},      // Kick
            {800.0f, 3000.0f, 1.5f, "mid"},    // Snare crack
            {5000.0f, 15000.0f, 1.2f, "high"}  // Hi-hat/cymbal
        };
        return config;
    }
};

class MultiBandOnsetDetector {
public:
    MultiBandOnsetDetector(const OnsetDetectionConfig& config, SampleRate sampleRate)
        : config_(config)
        , sampleRate_(sampleRate)
    {
        // Create filter and detector for each band
        for (const auto& band : config_.bands) {
            bandFilters_.push_back(
                std::make_unique<BandpassFilter>(band.lowHz, band.highHz, sampleRate)
            );
            bandDetectors_.push_back(
                std::make_unique<SpectralFluxDetector>(config_.fftSize, config_.hopSize)
            );
        }
    }

    void prepare(int maxBlockSize) {
        for (auto& filter : bandFilters_) {
            filter->prepare(sampleRate_, maxBlockSize);
        }
        for (auto& detector : bandDetectors_) {
            detector->prepare(sampleRate_, maxBlockSize);
        }
    }

    std::vector<int> detectOnsets(const Buffer& input) {
        std::vector<std::vector<int>> bandOnsets;

        // Analyze each band
        for (size_t i = 0; i < config_.bands.size(); i++) {
            Buffer bandBuffer = input;
            bandFilters_[i]->process(bandBuffer);
            bandDetectors_[i]->analyze(bandBuffer);

            auto onsets = bandDetectors_[i]->findOnsets(
                config_.medianMultiplier,
                config_.medianWindowSize
            );

            bandOnsets.push_back(onsets);
        }

        // Combine onsets from all bands
        return combineOnsets(bandOnsets);
    }

private:
    std::vector<int> combineOnsets(const std::vector<std::vector<int>>& bandOnsets) {
        std::vector<std::pair<int, Sample>> weightedOnsets;

        // Collect all onsets with their band weights
        for (size_t i = 0; i < bandOnsets.size(); i++) {
            for (int onset : bandOnsets[i]) {
                weightedOnsets.push_back({onset, config_.bands[i].weight});
            }
        }

        // Sort by position
        std::sort(weightedOnsets.begin(), weightedOnsets.end());

        // Merge nearby onsets (within 50ms)
        int mergeThreshold = static_cast<int>(sampleRate_ * 0.05f);
        std::vector<int> merged;

        for (size_t i = 0; i < weightedOnsets.size(); i++) {
            if (merged.empty() || weightedOnsets[i].first - merged.back() > mergeThreshold) {
                merged.push_back(weightedOnsets[i].first);
            }
        }

        return merged;
    }

    OnsetDetectionConfig config_;
    SampleRate sampleRate_;
    std::vector<std::unique_ptr<Filter>> bandFilters_;
    std::vector<std::unique_ptr<SpectralFluxDetector>> bandDetectors_;
};

} // namespace DSP
