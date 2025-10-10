#include "dsp_pipeline.h"
#include <iostream>
#include <fstream>
#include <cstring>
#include <cstdint>
#include <sstream>
#include <iomanip>

// Simple WAV I/O
struct WAVHeader {
    char riff[4];
    uint32_t fileSize;
    char wave[4];
    char fmt[4];
    uint32_t fmtSize;
    uint16_t audioFormat;
    uint16_t numChannels;
    uint32_t sampleRate;
    uint32_t byteRate;
    uint16_t blockAlign;
    uint16_t bitsPerSample;
    char data[4];
    uint32_t dataSize;
};

DSP::Buffer loadWAV(const char* filename, uint32_t& sampleRate, uint16_t& numChannels) {
    std::ifstream input(filename, std::ios::binary);
    if (!input) throw std::runtime_error("Cannot open input file");

    char riff[4], wave[4];
    uint32_t fileSize;
    input.read(riff, 4);
    input.read(reinterpret_cast<char*>(&fileSize), 4);
    input.read(wave, 4);

    if (std::strncmp(riff, "RIFF", 4) != 0 || std::strncmp(wave, "WAVE", 4) != 0) {
        throw std::runtime_error("Not a valid WAV file");
    }

    uint16_t bitsPerSample = 0;
    uint32_t dataSize = 0;
    std::streampos dataStart = 0;

    while (input.good()) {
        char chunkId[4];
        uint32_t chunkSize;
        input.read(chunkId, 4);
        input.read(reinterpret_cast<char*>(&chunkSize), 4);

        if (std::strncmp(chunkId, "fmt ", 4) == 0) {
            uint16_t audioFormat;
            input.read(reinterpret_cast<char*>(&audioFormat), 2);
            input.read(reinterpret_cast<char*>(&numChannels), 2);
            input.read(reinterpret_cast<char*>(&sampleRate), 4);
            uint32_t byteRate;
            input.read(reinterpret_cast<char*>(&byteRate), 4);
            uint16_t blockAlign;
            input.read(reinterpret_cast<char*>(&blockAlign), 2);
            input.read(reinterpret_cast<char*>(&bitsPerSample), 2);
            if (chunkSize > 16) {
                input.seekg(chunkSize - 16, std::ios::cur);
            }
        } else if (std::strncmp(chunkId, "data", 4) == 0) {
            dataSize = chunkSize;
            dataStart = input.tellg();
            break;
        } else {
            input.seekg(chunkSize, std::ios::cur);
        }
    }

    if (dataSize == 0 || bitsPerSample != 16) {
        throw std::runtime_error("Only 16-bit PCM WAV supported");
    }

    size_t numSamples = dataSize / 2;
    std::vector<int16_t> audioData(numSamples);
    input.read(reinterpret_cast<char*>(audioData.data()), dataSize);
    input.close();

    // Convert to mono float
    size_t monoSamples = numSamples / numChannels;
    DSP::Buffer buffer(monoSamples);
    for (size_t i = 0; i < monoSamples; i++) {
        float sum = 0.0f;
        for (int ch = 0; ch < numChannels; ch++) {
            sum += audioData[i * numChannels + ch] / 32768.0f;
        }
        buffer[i] = sum / numChannels;
    }

    return buffer;
}

void saveWAV(const char* filename, const DSP::Buffer& buffer, uint32_t sampleRate, bool normalize = true) {
    // Apply peak normalization before saving
    DSP::Buffer processedBuffer = buffer;
    if (normalize) {
        DSP::PeakNormalizer normalizer(-0.1f); // Target peak at -0.1 dB
        normalizer.prepare(sampleRate, processedBuffer.size());
        normalizer.process(processedBuffer);
    }

    std::ofstream output(filename, std::ios::binary);
    if (!output) throw std::runtime_error("Cannot create output file");

    uint16_t numChannels = 1;
    uint16_t bitsPerSample = 16;
    uint32_t dataSize = processedBuffer.size() * 2;

    // Write WAV header
    output.write("RIFF", 4);
    uint32_t fileSize = 36 + dataSize;
    output.write(reinterpret_cast<char*>(&fileSize), 4);
    output.write("WAVE", 4);
    output.write("fmt ", 4);
    uint32_t fmtSize = 16;
    output.write(reinterpret_cast<char*>(&fmtSize), 4);
    uint16_t audioFormat = 1;
    output.write(reinterpret_cast<char*>(&audioFormat), 2);
    output.write(reinterpret_cast<char*>(&numChannels), 2);
    output.write(reinterpret_cast<char*>(&sampleRate), 4);
    uint32_t byteRate = sampleRate * numChannels * bitsPerSample / 8;
    output.write(reinterpret_cast<char*>(&byteRate), 4);
    uint16_t blockAlign = numChannels * bitsPerSample / 8;
    output.write(reinterpret_cast<char*>(&blockAlign), 2);
    output.write(reinterpret_cast<char*>(&bitsPerSample), 2);
    output.write("data", 4);
    output.write(reinterpret_cast<char*>(&dataSize), 4);

    // Write audio data
    for (float sample : processedBuffer) {
        int16_t s = static_cast<int16_t>(std::max(-32768.0f, std::min(32767.0f, sample * 32767.0f)));
        output.write(reinterpret_cast<char*>(&s), 2);
    }

    output.close();
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <input.wav>\n";
        return 1;
    }

    const char* inputFile = argv[1];

    try {
        std::cout << "=== DSP Pipeline Demo - Multi-Stage Filtering ===" << std::endl;
        std::cout << "Input: " << inputFile << std::endl;

        // Load audio
        uint32_t sampleRate;
        uint16_t numChannels;
        auto buffer = loadWAV(inputFile, sampleRate, numChannels);

        std::cout << "Sample Rate: " << sampleRate << " Hz" << std::endl;
        std::cout << "Duration: " << buffer.size() / static_cast<float>(sampleRate) << " seconds" << std::endl;
        std::cout << std::endl;

        std::cout << "Processing stages:" << std::endl;

        // Stage 1: Original (save for reference)
        std::cout << "  1. original.wav - Unprocessed mono conversion" << std::endl;
        saveWAV("simple_filter_demos/01_original.wav", buffer, sampleRate);

        // Stage 2: Highpass 40Hz (remove rumble)
        {
            auto stage = buffer;
            DSP::Butterworth4PoleHighpass hpf(40, sampleRate);
            hpf.prepare(sampleRate, stage.size());
            hpf.process(stage);
            std::cout << "  2. highpass_40hz.wav - Remove sub-bass rumble" << std::endl;
            saveWAV("simple_filter_demos/02_highpass_40hz.wav", stage, sampleRate);
        }

        // Stage 3: Lowpass 15000Hz (remove air/hiss)
        {
            auto stage = buffer;
            DSP::Butterworth4PoleLowpass lpf(15000, sampleRate);
            lpf.prepare(sampleRate, stage.size());
            lpf.process(stage);
            std::cout << "  3. lowpass_15khz.wav - Remove high frequency hiss" << std::endl;
            saveWAV("simple_filter_demos/03_lowpass_15khz.wav", stage, sampleRate);
        }

        // Stage 4: Bandpass 60-200Hz (kick drum only)
        {
            auto stage = buffer;
            DSP::BandpassFilter bpf(60, 200, sampleRate);
            bpf.prepare(sampleRate, stage.size());
            bpf.process(stage);
            std::cout << "  4. bandpass_kick.wav - Kick drum fundamental (60-200 Hz)" << std::endl;
            saveWAV("simple_filter_demos/04_bandpass_kick.wav", stage, sampleRate);
        }

        // Stage 5: Bandpass 800-3000Hz (snare/mid)
        {
            auto stage = buffer;
            DSP::BandpassFilter bpf(800, 3000, sampleRate);
            bpf.prepare(sampleRate, stage.size());
            bpf.process(stage);
            std::cout << "  5. bandpass_snare.wav - Snare crack (800-3000 Hz)" << std::endl;
            saveWAV("simple_filter_demos/05_bandpass_snare.wav", stage, sampleRate);
        }

        // Stage 6: Bandpass 5000-15000Hz (hi-hat/cymbals)
        {
            auto stage = buffer;
            DSP::BandpassFilter bpf(5000, 15000, sampleRate);
            bpf.prepare(sampleRate, stage.size());
            bpf.process(stage);
            std::cout << "  6. bandpass_hihat.wav - Hi-hats/cymbals (5-15 kHz)" << std::endl;
            saveWAV("simple_filter_demos/06_bandpass_hihat.wav", stage, sampleRate);
        }

        // Stage 7: Lowpass 800Hz (dark/lofi)
        {
            auto stage = buffer;
            DSP::Butterworth4PoleLowpass lpf(800, sampleRate);
            lpf.prepare(sampleRate, stage.size());
            lpf.process(stage);
            std::cout << "  7. lowpass_800hz.wav - Dark/lofi (remove all highs)" << std::endl;
            saveWAV("simple_filter_demos/07_lowpass_800hz.wav", stage, sampleRate);
        }

        // Stage 8: Lowpass 1200Hz (telephone effect)
        {
            auto stage = buffer;
            DSP::Butterworth4PoleLowpass lpf(1200, sampleRate);
            lpf.prepare(sampleRate, stage.size());
            lpf.process(stage);
            std::cout << "  8. lowpass_1200hz.wav - Telephone/AM radio quality" << std::endl;
            saveWAV("simple_filter_demos/08_lowpass_1200hz.wav", stage, sampleRate);
        }

        // Stage 9: Lowpass 3000Hz (muffled)
        {
            auto stage = buffer;
            DSP::Butterworth4PoleLowpass lpf(3000, sampleRate);
            lpf.prepare(sampleRate, stage.size());
            lpf.process(stage);
            std::cout << "  9. lowpass_3000hz.wav - Muffled (no sizzle)" << std::endl;
            saveWAV("simple_filter_demos/09_lowpass_3000hz.wav", stage, sampleRate);
        }

        // Stage 10: Lowpass 6000Hz (slightly dark)
        {
            auto stage = buffer;
            DSP::Butterworth4PoleLowpass lpf(6000, sampleRate);
            lpf.prepare(sampleRate, stage.size());
            lpf.process(stage);
            std::cout << " 10. lowpass_6000hz.wav - Slightly warm/dark" << std::endl;
            saveWAV("simple_filter_demos/10_lowpass_6000hz.wav", stage, sampleRate);
        }

        // Stage 11: Highpass 200Hz (no kick)
        {
            auto stage = buffer;
            DSP::Butterworth4PoleHighpass hpf(200, sampleRate);
            hpf.prepare(sampleRate, stage.size());
            hpf.process(stage);
            std::cout << " 11. highpass_200hz.wav - Remove kick drum" << std::endl;
            saveWAV("simple_filter_demos/11_highpass_200hz.wav", stage, sampleRate);
        }

        // Stage 12: Highpass 1000Hz (thin/tinny)
        {
            auto stage = buffer;
            DSP::Butterworth4PoleHighpass hpf(1000, sampleRate);
            hpf.prepare(sampleRate, stage.size());
            hpf.process(stage);
            std::cout << " 12. highpass_1000hz.wav - Thin/tinny (no body)" << std::endl;
            saveWAV("simple_filter_demos/12_highpass_1000hz.wav", stage, sampleRate);
        }

        // Stage 13: Combined - HPF 40Hz + LPF 12kHz (clean)
        {
            auto stage = buffer;
            DSP::Butterworth4PoleHighpass hpf(40, sampleRate);
            DSP::Butterworth4PoleLowpass lpf(12000, sampleRate);
            hpf.prepare(sampleRate, stage.size());
            lpf.prepare(sampleRate, stage.size());
            hpf.process(stage);
            lpf.process(stage);
            std::cout << " 13. combined_clean.wav - HPF 40Hz + LPF 12kHz (broadcast quality)" << std::endl;
            saveWAV("simple_filter_demos/13_combined_clean.wav", stage, sampleRate);
        }

        std::cout << "\n✓ All 13 stages saved to simple_filter_demos/\n" << std::endl;
        std::cout << "Listen to each file to hear the effect of different filters!" << std::endl;

    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
