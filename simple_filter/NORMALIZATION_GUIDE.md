# Audio Normalization Guide

Clean implementation of peak and RMS normalization in the DSP pipeline.

## What is Normalization?

Normalization applies a **constant gain** to all samples to bring audio to a target loudness level.

- Does NOT change dynamics (quiet parts stay quiet relative to loud parts)
- Different from compression (which changes dynamics)
- Two main types: Peak and RMS

## Types of Normalization

### 1. Peak Normalization

**What it does:** Finds the loudest sample and scales everything so that sample hits the target level.

**Use case:**
- Maximize volume without clipping
- Ensure consistent peak levels across files
- Broadcasting/mastering

**Default target:** -0.1 dBFS (just below digital maximum)

**Example:**
```bash
./normalize input.wav                  # Peak normalize to -0.1 dB
./normalize input.wav --peak -3        # Peak normalize to -3 dB
```

### 2. RMS Normalization

**What it does:** Calculates average loudness (RMS = Root Mean Square) and scales to match target.

**Use case:**
- Perceptual loudness matching
- Background music leveling
- Podcast/voiceover consistency

**Default target:** -14 dBFS (common streaming standard)

**Includes clipping protection:** If RMS boost would cause clipping, gain is automatically reduced.

**Example:**
```bash
./normalize input.wav --rms -14        # RMS normalize to -14 dB
./normalize input.wav --rms -18        # Quieter target
```

## Command-Line Tools

### Standalone Normalizer

```bash
./normalize <input.wav> [output.wav] [options]

Options:
  --peak <dB>     Peak normalization (default: -0.1)
  --rms <dB>      RMS normalization (default: -14)

Examples:
  ./normalize drums.wav
  ./normalize drums.wav drums_loud.wav --peak -0.1
  ./normalize vocals.wav --rms -14
```

**Output:**
```
=== Audio Normalizer ===
Input: drums.wav
Sample Rate: 48000 Hz
Duration: 15 seconds

Current levels:
  Peak: -0.56 dBFS
  RMS:  -13.17 dBFS

Applying peak normalization to -0.1 dBFS...

New levels:
  Peak: -0.10 dBFS
  RMS:  -12.71 dBFS

✓ Output: drums_normalized.wav
```

### Automatic Normalization in Filters

All output from the `./dsp` helper and `pipeline_demo` is **automatically peak normalized** to -0.1 dB.

```bash
./dsp hp 2000          # Highpass + auto normalize
./dsp lp 800           # Lowpass + auto normalize
./pipeline_demo file   # All 13 stages + auto normalize
```

## Algorithm Details

### Peak Normalization Algorithm

```
1. Find current peak:
   currentPeak = max(|sample|) for all samples

2. Convert target dB to linear:
   targetLinear = 10^(targetPeak_dB / 20)

3. Calculate gain factor:
   gain = targetLinear / currentPeak

4. Apply gain to all samples:
   output[i] = input[i] * gain
```

**Time complexity:** O(n) - single pass through audio

### RMS Normalization Algorithm

```
1. Calculate current RMS:
   sumOfSquares = Σ(sample²)
   currentRMS = √(sumOfSquares / numSamples)

2. Convert target dB to linear:
   targetRMS_linear = 10^(targetRMS_dB / 20)

3. Calculate gain factor:
   gain = targetRMS_linear / currentRMS

4. Apply gain to all samples:
   output[i] = input[i] * gain

5. Clipping protection:
   newPeak = max(|output|)
   if newPeak > 1.0:
       clippingCorrection = 1.0 / newPeak
       for each sample:
           output[i] *= clippingCorrection
```

**Time complexity:** O(n) - two passes (RMS calculation + clipping check)

## Integration in Pipeline

### DSP Pipeline Classes

**PeakNormalizer** - AudioProcessor
```cpp
DSP::PeakNormalizer normalizer(-0.1f);  // Target -0.1 dB
normalizer.prepare(sampleRate, bufferSize);
normalizer.process(buffer);
```

**RMSNormalizer** - AudioProcessor
```cpp
DSP::RMSNormalizer normalizer(-14.0f);  // Target -14 dB
normalizer.prepare(sampleRate, bufferSize);
normalizer.process(buffer);
```

### Chain with Other Processors

```cpp
DSP::ProcessingChain chain;
chain.add(std::make_unique<DSP::Butterworth4PoleLowpass>(800, sampleRate))
     .add(std::make_unique<DSP::PeakNormalizer>(-0.1f));

chain.prepare(sampleRate, bufferSize);
chain.process(buffer);
```

### saveWAV() Auto-Normalization

All `saveWAV()` calls in `pipeline_demo.cpp` automatically apply peak normalization:

```cpp
void saveWAV(const char* filename, const DSP::Buffer& buffer,
             uint32_t sampleRate, bool normalize = true) {
    DSP::Buffer processedBuffer = buffer;
    if (normalize) {
        DSP::PeakNormalizer normalizer(-0.1f);
        normalizer.prepare(sampleRate, processedBuffer.size());
        normalizer.process(processedBuffer);
    }
    // ... write to file
}
```

## Understanding dBFS

**dBFS = Decibels Full Scale**

The scale in digital audio where 0 dBFS is the maximum possible level.

| Level | Linear | Meaning |
|-------|--------|---------|
| 0 dBFS | 1.0 | Maximum (clipping point) |
| -0.1 dBFS | 0.989 | Just below maximum (safe) |
| -3 dBFS | 0.708 | Half power |
| -6 dBFS | 0.501 | Half amplitude |
| -12 dBFS | 0.251 | Quarter amplitude |
| -14 dBFS | 0.200 | Common RMS target |
| -∞ dBFS | 0.0 | Silence |

**Conversion formulas:**
```
dB to linear: linear = 10^(dB / 20)
Linear to dB: dB = 20 * log10(linear)
```

## Practical Examples

### Example 1: Normalize Quiet Recording

**Problem:** Recording is -12 dB too quiet

```bash
./normalize quiet_drums.wav

Current levels:
  Peak: -12.5 dBFS
  RMS:  -25.3 dBFS

Applying peak normalization to -0.1 dBFS...

New levels:
  Peak: -0.1 dBFS    # Gained 12.4 dB
  RMS:  -12.9 dBFS   # Also gained 12.4 dB
```

**Result:** Everything is 12.4 dB louder, dynamics preserved.

### Example 2: Match Loudness Across Files

**Problem:** Multiple files with different loudness

```bash
./normalize file1.wav --rms -14
./normalize file2.wav --rms -14
./normalize file3.wav --rms -14
```

**Result:** All files have same perceived loudness (RMS -14 dB).

### Example 3: After Heavy Filtering

**Problem:** Lowpass filter at 500 Hz makes audio very quiet

```bash
./dsp lp 500 drums.wav filtered.wav

Applying 4-pole lowpass at 500 Hz...
✓ Output (normalized): filtered.wav
```

**Result:** Filter + normalization applied automatically.

## When to Use Which Method

### Use Peak Normalization When:
- ✅ Maximizing volume is priority
- ✅ Preventing clipping is critical
- ✅ Preserving exact dynamics
- ✅ Mastering final output
- ✅ Broadcasting requirements

### Use RMS Normalization When:
- ✅ Matching perceived loudness
- ✅ Leveling background music
- ✅ Podcast/voiceover work
- ✅ Streaming platforms (Spotify, YouTube target ~-14 LUFS)
- ✅ Creating consistent listening experience

## Implementation Notes

**Thread safety:** Both normalizers are stateless (except for target level). Safe to use on multiple files in parallel.

**Memory:** Requires two passes through audio:
1. Analysis pass (find peak/RMS)
2. Processing pass (apply gain)

**No clipping:** RMS normalizer includes automatic clipping protection.

**Deterministic:** Same input always produces same output.

**Precision:** Uses 32-bit float for gain calculation, converts to 16-bit int for WAV output.

## Common Targets

**Music Production:**
- Peak: -0.1 to -1.0 dBFS (headroom for lossy encoding)
- RMS: -8 to -12 dBFS (loud/aggressive) or -14 to -18 dBFS (dynamic)

**Streaming Platforms:**
- Spotify: ~-14 LUFS (≈ -14 dBFS RMS)
- YouTube: ~-13 LUFS
- Apple Music: -16 LUFS

**Broadcasting:**
- EBU R128: -23 LUFS
- ATSC A/85: -24 LUFS

**Note:** LUFS is slightly different from RMS but similar concept.

## Performance

**Normalization overhead:** ~5ms for 15 seconds of audio @ 48kHz

Negligible compared to filtering (which is also fast). Safe to apply to all outputs.

## References

- **ITU-R BS.1770**: Loudness measurement standard
- **EBU R128**: Broadcast loudness
- **AES Standard**: Dynamic range control
