# DSP Pipeline - Composable Audio Processing

A clean, modular C++ DSP library for audio analysis and onset detection.

## Architecture

The library uses a **composable pipeline architecture** with abstract base classes:

```cpp
AudioProcessor → Filter → Biquad, Butterworth4PoleLowpass, BandpassFilter
AudioProcessor → ProcessingChain (compose multiple processors)
Analyzer → SpectralFluxDetector, MultiBandOnsetDetector
```

## Core Components

### 1. Filters (IIR)

**Biquad** - Building block for all filters
```cpp
DSP::Biquad filter;
auto coeffs = DSP::FilterDesign::butterworthLowpass2(800, 48000, 0.707);
filter.setCoefficients(coeffs.b0, coeffs.b1, coeffs.b2, coeffs.a1, coeffs.a2);
filter.process(buffer);
```

**Butterworth 4-Pole Filters** - 24dB/octave rolloff
```cpp
DSP::Butterworth4PoleLowpass lpf(800, sampleRate);  // Lowpass
DSP::Butterworth4PoleHighpass hpf(60, sampleRate);  // Highpass
```

**Bandpass Filter** - Isolate frequency ranges
```cpp
DSP::BandpassFilter kickFilter(60, 200, sampleRate);  // 60-200 Hz
```

### 2. FFT Analysis

**Short-Time Fourier Transform**
```cpp
DSP::FFT fft(2048);  // Power-of-2 size
std::vector<DSP::FFT::Complex> spectrum;
fft.forward(buffer, spectrum);
auto magnitudes = fft.getMagnitudes(spectrum);
```

**Window Functions** - Reduce spectral leakage
```cpp
auto window = DSP::Window::hann(2048);
auto window = DSP::Window::hamming(2048);
auto window = DSP::Window::blackman(2048);
```

### 3. Onset Detection

**Spectral Flux Detector** - Measures spectral change over time

The algorithm:
1. Divide audio into overlapping frames (e.g., 2048 samples, 512 hop)
2. Apply window function (Hann)
3. Compute FFT magnitude spectrum
4. Calculate half-wave rectified spectral difference: `flux = sum(max(0, mag[i] - prev_mag[i]))`
5. Peak-pick with adaptive threshold

```cpp
DSP::SpectralFluxDetector detector(2048, 512);  // FFT size, hop size
detector.prepare(sampleRate, bufferSize);
detector.analyze(buffer);
auto onsets = detector.findOnsets(1.5f, 10);  // threshold multiplier, median window
```

**Multi-Band Onset Detector** - Parallel analysis across frequency bands

Analyzes low/mid/high bands separately to detect different drum types:
- **Low (60-200 Hz)**: Kick drum fundamentals
- **Mid (800-3000 Hz)**: Snare crack, tom body
- **High (5000-15000 Hz)**: Hi-hat, cymbal attacks

```cpp
auto config = DSP::OnsetDetectionConfig::drumDetection();
config.fftSize = 2048;
config.hopSize = 512;

DSP::MultiBandOnsetDetector detector(config, sampleRate);
detector.prepare(bufferSize);
auto onsets = detector.detectOnsets(buffer);
```

### 4. Processing Chain - Pipeline Composition

Combine multiple processors in sequence:

```cpp
DSP::ProcessingChain chain;
chain.add(std::make_unique<DSP::Butterworth4PoleHighpass>(40, sampleRate))
     .add(std::make_unique<DSP::Butterworth4PoleLowpass>(15000, sampleRate));

chain.prepare(sampleRate, bufferSize);
chain.process(buffer);
```

## Command-Line Tools

### 1. Filter Tool

Apply IIR filters to WAV files:

```bash
# 4-pole Butterworth lowpass at 800 Hz (default)
./filter input.wav output.wav

# Custom cutoff
./filter input.wav output.wav 1200

# Examples
./filter drums.wav drums_dark.wav 400    # Very dark/bassy
./filter drums.wav drums_bright.wav 5000 # Remove bass
```

### 2. Onset Detector

Find transients using spectral analysis:

**Simple spectral flux**
```bash
./onset_detector input.wav --simple
```

**Multi-band drum detection**
```bash
./onset_detector input.wav --multiband
```

**With preprocessing**
```bash
./onset_detector input.wav \
  --multiband \
  --prefilter 40 \
  --threshold 2.0 \
  --output onsets.txt \
  --audacity
```

**Full options**
```
Onset Detection Methods:
  --simple              Simple spectral flux (default)
  --multiband           Multi-band drum detection
  --prefilter <hz>      Apply highpass prefilter at <hz>

FFT Parameters:
  --fft-size <n>        FFT size (default: 2048)
  --hop-size <n>        Hop size (default: 512)

Peak Picking:
  --threshold <mult>    Median multiplier (default: 1.5)
  --median-win <n>      Median window size (default: 10)

Output:
  --output <file>       Write onset times to file
  --audacity            Output in Audacity label format
```

## Algorithm Details

### Spectral Flux Onset Detection

The spectral flux method detects onsets by measuring sudden increases in spectral energy.

**Stage 1: STFT (Short-Time Fourier Transform)**
- Break audio into overlapping frames
- Apply window function (Hann)
- Compute FFT for each frame
- Result: Spectrogram (time × frequency)

**Stage 2: Novelty Function**
- For each frequency bin, calculate change from previous frame
- Keep only increases (half-wave rectification): `max(0, current - previous)`
- Sum across all bins: `flux = Σ max(0, mag[i,t] - mag[i,t-1])`
- Result: 1D curve with peaks at onsets

**Stage 3: Peak Picking**
- Calculate adaptive threshold: `threshold = median(flux[t-w:t+w]) × multiplier`
- Find local maxima above threshold
- Result: Onset sample indices

### Multi-Band Detection

Analyzes three frequency bands in parallel:

1. **Bandpass filter** audio into low/mid/high bands
2. **Run spectral flux** on each band independently
3. **Combine onsets** from all bands with weight factors
4. **Merge** nearby onsets (within 50ms)

This catches onsets missed by single-band analysis (e.g., soft hi-hat during loud kick).

## Implementation Notes

### Why Biquads?

All filters use cascaded biquad (2nd-order) sections:
- **Numerical stability**: Lower-order filters are more stable
- **Modularity**: Mix and match filter types
- **Efficiency**: Direct Form I implementation, minimal state

### FFT Implementation

Simple Cooley-Tukey radix-2 FFT:
- **Requirement**: Size must be power of 2
- **In-place**: Uses bit-reversal permutation
- **Performance**: O(N log N), adequate for offline analysis
- **For real-time**: Consider FFTW or hand-tuned SIMD

### Window Function Choice

- **Hann**: Good general-purpose, smooth rolloff
- **Hamming**: Slightly better frequency resolution
- **Blackman**: Best sidelobe rejection, wider main lobe

For onset detection, **Hann** is recommended.

## Example: Building a Custom Pipeline

```cpp
// Load audio
DSP::Buffer audio = loadMonoAudio("drums.wav", sampleRate);

// Stage 1: Preprocessing
DSP::Butterworth4PoleHighpass hpf(40, sampleRate);
hpf.prepare(sampleRate, audio.size());
hpf.process(audio);

// Stage 2: Create bandpass filters
DSP::BandpassFilter lowBand(60, 200, sampleRate);    // Kick
DSP::BandpassFilter midBand(800, 3000, sampleRate);  // Snare
DSP::BandpassFilter hiBand(5000, 15000, sampleRate); // Hi-hat

// Stage 3: Analyze each band
std::vector<DSP::Buffer> bands = {audio, audio, audio};
lowBand.process(bands[0]);
midBand.process(bands[1]);
hiBand.process(bands[2]);

// Stage 4: Detect onsets per band
std::vector<std::vector<int>> onsets(3);
for (int i = 0; i < 3; i++) {
    DSP::SpectralFluxDetector detector(2048, 512);
    detector.prepare(sampleRate, bands[i].size());
    detector.analyze(bands[i]);
    onsets[i] = detector.findOnsets(1.5f, 10);
}

// Stage 5: Combine results
// (Your custom merging logic here)
```

## Extending the Library

### Adding a New Filter

```cpp
class MyCustomFilter : public DSP::Filter {
public:
    void prepare(DSP::SampleRate sr, int maxBlock) override {
        // Initialize state
    }

    void process(DSP::Buffer& buffer) override {
        // Process samples
    }

    void reset() override {
        // Clear state
    }
};
```

### Adding a New Analyzer

```cpp
class MyAnalyzer : public DSP::Analyzer {
public:
    void prepare(DSP::SampleRate sr, int frameSize) override {
        // Setup
    }

    void analyze(const DSP::Buffer& buffer) override {
        // Analysis algorithm
    }

    void reset() override {
        // Clear state
    }
};
```

## Performance

**Typical processing time** (15-second drum loop, 48kHz):
- Simple spectral flux: ~50ms
- Multi-band detection: ~150ms
- 4-pole lowpass filter: ~5ms

**Memory usage**:
- FFT (2048): ~32 KB per detector
- Audio buffer: ~2.8 MB for 15s stereo @ 48kHz

## References

- **Onset Detection**: Bello et al., "A Tutorial on Onset Detection in Music Signals" (2005)
- **Spectral Flux**: Masri, "Computer Modelling of Sound for Transformation and Synthesis of Musical Signals" (1996)
- **Butterworth Filters**: Butterworth, "On the Theory of Filter Amplifiers" (1930)
- **FFT**: Cooley & Tukey, "An Algorithm for the Machine Calculation of Complex Fourier Series" (1965)

## License

Public domain / MIT - use freely
