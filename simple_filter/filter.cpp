#include <iostream>
#include <vector>
#include <fstream>
#include <cmath>
#include <cstring>
#include <cstdint>

// Simple WAV header structure
struct WAVHeader {
    char riff[4];              // "RIFF"
    uint32_t fileSize;
    char wave[4];              // "WAVE"
    char fmt[4];               // "fmt "
    uint32_t fmtSize;
    uint16_t audioFormat;
    uint16_t numChannels;
    uint32_t sampleRate;
    uint32_t byteRate;
    uint16_t blockAlign;
    uint16_t bitsPerSample;
    char data[4];              // "data"
    uint32_t dataSize;
};

// 4-pole (24dB/octave) Butterworth lowpass filter
// Implemented as cascade of 2 biquad filters
class Biquad {
public:
    Biquad() : x1(0), x2(0), y1(0), y2(0) {}

    void setCoefficients(float b0, float b1, float b2, float a1, float a2) {
        this->b0 = b0;
        this->b1 = b1;
        this->b2 = b2;
        this->a1 = a1;
        this->a2 = a2;
    }

    float process(float x0) {
        float y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
        x2 = x1;
        x1 = x0;
        y2 = y1;
        y1 = y0;
        return y0;
    }

private:
    float b0, b1, b2, a1, a2;
    float x1, x2, y1, y2;
};

class Butterworth4PoleLowpass {
public:
    Butterworth4PoleLowpass(float cutoffHz, float sampleRate) {
        // 4-pole Butterworth = cascade of 2 second-order sections
        float wc = 2.0f * M_PI * cutoffHz;
        float wc2 = wc * wc;
        float wc3 = wc2 * wc;
        float wc4 = wc2 * wc2;

        // Pre-warp the cutoff frequency
        float wa = (2.0f * sampleRate) * std::tan(wc / (2.0f * sampleRate));
        float wa2 = wa * wa;

        // Q values for 4-pole Butterworth (maximally flat response)
        float q1 = 0.54119610f; // First biquad Q
        float q2 = 1.3065630f;  // Second biquad Q

        // Calculate coefficients for first biquad
        float k = wa / sampleRate;
        float k2 = k * k;
        float norm = 1.0f / (1.0f + k / q1 + k2);

        float b0_1 = k2 * norm;
        float b1_1 = 2.0f * b0_1;
        float b2_1 = b0_1;
        float a1_1 = 2.0f * (k2 - 1.0f) * norm;
        float a2_1 = (1.0f - k / q1 + k2) * norm;

        // Calculate coefficients for second biquad
        norm = 1.0f / (1.0f + k / q2 + k2);

        float b0_2 = k2 * norm;
        float b1_2 = 2.0f * b0_2;
        float b2_2 = b0_2;
        float a1_2 = 2.0f * (k2 - 1.0f) * norm;
        float a2_2 = (1.0f - k / q2 + k2) * norm;

        biquad1.setCoefficients(b0_1, b1_1, b2_1, a1_1, a2_1);
        biquad2.setCoefficients(b0_2, b1_2, b2_2, a1_2, a2_2);
    }

    float process(float x) {
        float y = biquad1.process(x);
        y = biquad2.process(y);
        return y;
    }

private:
    Biquad biquad1;
    Biquad biquad2;
};

int main(int argc, char* argv[]) {
    if (argc < 3) {
        std::cerr << "Usage: " << argv[0] << " <input.wav> <output.wav> [cutoff_hz]\n";
        return 1;
    }

    const char* inputFile = argv[1];
    const char* outputFile = argv[2];
    float cutoffHz = argc > 3 ? std::atof(argv[3]) : 800.0f;

    std::cout << "=== 4-Pole Butterworth Lowpass Filter (24dB/octave) ===" << std::endl;
    std::cout << "Input: " << inputFile << std::endl;
    std::cout << "Output: " << outputFile << std::endl;
    std::cout << "Cutoff: " << cutoffHz << " Hz" << std::endl;

    // Read input WAV file
    std::ifstream input(inputFile, std::ios::binary);
    if (!input) {
        std::cerr << "Error: Cannot open input file!" << std::endl;
        return 1;
    }

    WAVHeader header;
    input.read(reinterpret_cast<char*>(&header), 12); // Read RIFF header

    // Validate WAV format
    if (std::strncmp(header.riff, "RIFF", 4) != 0 ||
        std::strncmp(header.wave, "WAVE", 4) != 0) {
        std::cerr << "Error: Not a valid WAV file!" << std::endl;
        return 1;
    }

    // Read chunks until we find fmt and data
    uint32_t sampleRate = 0;
    uint16_t numChannels = 0;
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
            // Skip any extra fmt chunk data
            if (chunkSize > 16) {
                input.seekg(chunkSize - 16, std::ios::cur);
            }
        } else if (std::strncmp(chunkId, "data", 4) == 0) {
            dataSize = chunkSize;
            dataStart = input.tellg();
            break;
        } else {
            // Skip unknown chunk
            input.seekg(chunkSize, std::ios::cur);
        }
    }

    if (dataSize == 0) {
        std::cerr << "Error: No data chunk found!" << std::endl;
        return 1;
    }

    header.sampleRate = sampleRate;
    header.numChannels = numChannels;
    header.bitsPerSample = bitsPerSample;
    header.dataSize = dataSize;

    std::cout << "\nAudio Info:" << std::endl;
    std::cout << "  Sample Rate: " << header.sampleRate << " Hz" << std::endl;
    std::cout << "  Channels: " << header.numChannels << std::endl;
    std::cout << "  Bits: " << header.bitsPerSample << std::endl;
    std::cout << "  Data Size: " << header.dataSize << " bytes" << std::endl;

    // Only support 16-bit PCM for now
    if (header.bitsPerSample != 16) {
        std::cerr << "Error: Only 16-bit PCM WAV files supported!" << std::endl;
        return 1;
    }

    // Read audio data
    size_t numSamples = header.dataSize / 2; // 16-bit = 2 bytes per sample
    std::vector<int16_t> audioData(numSamples);
    input.read(reinterpret_cast<char*>(audioData.data()), header.dataSize);
    input.close();

    std::cout << "\nProcessing " << numSamples << " samples..." << std::endl;

    // Apply 4-pole Butterworth lowpass filter to each channel
    std::vector<Butterworth4PoleLowpass> filters;
    for (int i = 0; i < numChannels; i++) {
        filters.emplace_back(cutoffHz, sampleRate);
    }

    for (size_t i = 0; i < numSamples; i++) {
        int channel = i % numChannels;
        float sample = audioData[i] / 32768.0f; // Convert to float [-1, 1]
        sample = filters[channel].process(sample);
        audioData[i] = static_cast<int16_t>(sample * 32767.0f); // Convert back
    }

    std::cout << "✓ Filter applied" << std::endl;

    // Write output WAV file
    std::cout << "\nWriting output file..." << std::endl;
    std::ofstream output(outputFile, std::ios::binary);
    if (!output) {
        std::cerr << "Error: Cannot create output file!" << std::endl;
        return 1;
    }

    // Write WAV header manually
    output.write("RIFF", 4);
    uint32_t fileSize = 36 + dataSize;
    output.write(reinterpret_cast<char*>(&fileSize), 4);
    output.write("WAVE", 4);
    output.write("fmt ", 4);
    uint32_t fmtSize = 16;
    output.write(reinterpret_cast<char*>(&fmtSize), 4);
    uint16_t audioFormat = 1; // PCM
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
    output.write(reinterpret_cast<char*>(audioData.data()), dataSize);
    output.close();

    std::cout << "✓ Output written: " << outputFile << std::endl;
    std::cout << "\n✓ Done!" << std::endl;

    return 0;
}
