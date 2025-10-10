#include "dsp_pipeline.h"
#include <iostream>
#include <fstream>
#include <cstring>
#include <cstdint>

struct WAVData {
    DSP::Buffer buffer;
    uint32_t sampleRate;
    uint16_t numChannels;
};

WAVData loadWAV(const char* filename) {
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

    uint32_t sampleRate = 0;
    uint16_t numChannels = 0;
    uint16_t bitsPerSample = 0;
    uint32_t dataSize = 0;

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

    size_t monoSamples = numSamples / numChannels;
    DSP::Buffer buffer(monoSamples);
    for (size_t i = 0; i < monoSamples; i++) {
        float sum = 0.0f;
        for (int ch = 0; ch < numChannels; ch++) {
            sum += audioData[i * numChannels + ch] / 32768.0f;
        }
        buffer[i] = sum / numChannels;
    }

    return {buffer, sampleRate, numChannels};
}

void saveWAV(const char* filename, const DSP::Buffer& buffer, uint32_t sampleRate) {
    std::ofstream output(filename, std::ios::binary);
    if (!output) throw std::runtime_error("Cannot create output file");

    uint16_t numChannels = 1;
    uint16_t bitsPerSample = 16;
    uint32_t dataSize = buffer.size() * 2;

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

    for (float sample : buffer) {
        int16_t s = static_cast<int16_t>(std::max(-32768.0f, std::min(32767.0f, sample * 32767.0f)));
        output.write(reinterpret_cast<char*>(&s), 2);
    }
    output.close();
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <input.wav> [output.wav] [options]\n";
        std::cerr << "\nOptions:\n";
        std::cerr << "  --peak <dB>     Peak normalization to target dB (default: -0.1)\n";
        std::cerr << "  --rms <dB>      RMS normalization to target dB (default: -14)\n";
        std::cerr << "\nExamples:\n";
        std::cerr << "  " << argv[0] << " input.wav                    # Peak normalize to -0.1 dB\n";
        std::cerr << "  " << argv[0] << " input.wav output.wav         # Custom output name\n";
        std::cerr << "  " << argv[0] << " input.wav --peak -3          # Peak normalize to -3 dB\n";
        std::cerr << "  " << argv[0] << " input.wav --rms -14          # RMS normalize to -14 dB\n";
        return 1;
    }

    const char* inputFile = argv[1];
    std::string outputFile = "normalized.wav";
    bool useRMS = false;
    float targetLevel = -0.1f;

    // Parse arguments
    for (int i = 2; i < argc; i++) {
        std::string arg = argv[i];
        if (arg == "--peak" && i + 1 < argc) {
            useRMS = false;
            targetLevel = std::atof(argv[++i]);
        } else if (arg == "--rms" && i + 1 < argc) {
            useRMS = true;
            targetLevel = std::atof(argv[++i]);
        } else if (arg[0] != '-') {
            outputFile = arg;
        }
    }

    // If only input file given, generate output name
    if (argc == 2) {
        std::string input(inputFile);
        size_t dotPos = input.find_last_of('.');
        if (dotPos != std::string::npos) {
            outputFile = input.substr(0, dotPos) + "_normalized" + input.substr(dotPos);
        } else {
            outputFile = input + "_normalized.wav";
        }
    }

    try {
        std::cout << "=== Audio Normalizer ===" << std::endl;
        std::cout << "Input: " << inputFile << std::endl;

        auto wav = loadWAV(inputFile);

        std::cout << "Sample Rate: " << wav.sampleRate << " Hz" << std::endl;
        std::cout << "Duration: " << wav.buffer.size() / static_cast<float>(wav.sampleRate) << " seconds" << std::endl;

        // Find current levels before normalization
        float currentPeak = 0.0f;
        float sumOfSquares = 0.0f;
        for (float sample : wav.buffer) {
            currentPeak = std::max(currentPeak, std::abs(sample));
            sumOfSquares += sample * sample;
        }
        float currentRMS = std::sqrt(sumOfSquares / wav.buffer.size());
        float currentPeak_dB = currentPeak > 0 ? 20.0f * std::log10(currentPeak) : -100.0f;
        float currentRMS_dB = currentRMS > 0 ? 20.0f * std::log10(currentRMS) : -100.0f;

        std::cout << "\nCurrent levels:" << std::endl;
        std::cout << "  Peak: " << currentPeak_dB << " dBFS" << std::endl;
        std::cout << "  RMS:  " << currentRMS_dB << " dBFS" << std::endl;

        // Apply normalization
        if (useRMS) {
            std::cout << "\nApplying RMS normalization to " << targetLevel << " dBFS..." << std::endl;
            DSP::RMSNormalizer normalizer(targetLevel);
            normalizer.prepare(wav.sampleRate, wav.buffer.size());
            normalizer.process(wav.buffer);
        } else {
            std::cout << "\nApplying peak normalization to " << targetLevel << " dBFS..." << std::endl;
            DSP::PeakNormalizer normalizer(targetLevel);
            normalizer.prepare(wav.sampleRate, wav.buffer.size());
            normalizer.process(wav.buffer);
        }

        // Calculate new levels
        float newPeak = 0.0f;
        sumOfSquares = 0.0f;
        for (float sample : wav.buffer) {
            newPeak = std::max(newPeak, std::abs(sample));
            sumOfSquares += sample * sample;
        }
        float newRMS = std::sqrt(sumOfSquares / wav.buffer.size());
        float newPeak_dB = newPeak > 0 ? 20.0f * std::log10(newPeak) : -100.0f;
        float newRMS_dB = newRMS > 0 ? 20.0f * std::log10(newRMS) : -100.0f;

        std::cout << "\nNew levels:" << std::endl;
        std::cout << "  Peak: " << newPeak_dB << " dBFS" << std::endl;
        std::cout << "  RMS:  " << newRMS_dB << " dBFS" << std::endl;

        saveWAV(outputFile.c_str(), wav.buffer, wav.sampleRate);
        std::cout << "\n✓ Output: " << outputFile << std::endl;

    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
