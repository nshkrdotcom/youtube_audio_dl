#include "dsp_pipeline.h"
#include <iostream>
#include <fstream>
#include <cstring>
#include <cstdint>

// Simple WAV header structure
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
    if (!input) {
        throw std::runtime_error("Cannot open input file");
    }

    // Read RIFF header
    char riff[4], wave[4];
    uint32_t fileSize;
    input.read(riff, 4);
    input.read(reinterpret_cast<char*>(&fileSize), 4);
    input.read(wave, 4);

    if (std::strncmp(riff, "RIFF", 4) != 0 || std::strncmp(wave, "WAVE", 4) != 0) {
        throw std::runtime_error("Not a valid WAV file");
    }

    // Read chunks until we find fmt and data
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

    // Read audio data
    size_t numSamples = dataSize / 2;
    std::vector<int16_t> audioData(numSamples);
    input.read(reinterpret_cast<char*>(audioData.data()), dataSize);
    input.close();

    // Convert to mono float buffer
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

void printUsage(const char* prog) {
    std::cout << "Usage: " << prog << " <input.wav> [options]\n\n";
    std::cout << "Onset Detection Methods:\n";
    std::cout << "  --simple              Simple spectral flux (default)\n";
    std::cout << "  --multiband           Multi-band drum detection\n";
    std::cout << "  --prefilter <hz>      Apply highpass prefilter at <hz>\n\n";
    std::cout << "FFT Parameters:\n";
    std::cout << "  --fft-size <n>        FFT size (default: 2048)\n";
    std::cout << "  --hop-size <n>        Hop size (default: 512)\n\n";
    std::cout << "Peak Picking:\n";
    std::cout << "  --threshold <mult>    Median multiplier (default: 1.5)\n";
    std::cout << "  --median-win <n>      Median window size (default: 10)\n\n";
    std::cout << "Output:\n";
    std::cout << "  --output <file>       Write onset times to file\n";
    std::cout << "  --audacity            Output in Audacity label format\n";
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        printUsage(argv[0]);
        return 1;
    }

    const char* inputFile = argv[1];
    bool multiband = false;
    bool usePrefilter = false;
    float prefilterHz = 60.0f;
    int fftSize = 2048;
    int hopSize = 512;
    float thresholdMult = 1.5f;
    int medianWin = 10;
    const char* outputFile = nullptr;
    bool audacityFormat = false;

    // Parse arguments
    for (int i = 2; i < argc; i++) {
        std::string arg = argv[i];
        if (arg == "--multiband") {
            multiband = true;
        } else if (arg == "--prefilter" && i + 1 < argc) {
            usePrefilter = true;
            prefilterHz = std::atof(argv[++i]);
        } else if (arg == "--fft-size" && i + 1 < argc) {
            fftSize = std::atoi(argv[++i]);
        } else if (arg == "--hop-size" && i + 1 < argc) {
            hopSize = std::atoi(argv[++i]);
        } else if (arg == "--threshold" && i + 1 < argc) {
            thresholdMult = std::atof(argv[++i]);
        } else if (arg == "--median-win" && i + 1 < argc) {
            medianWin = std::atoi(argv[++i]);
        } else if (arg == "--output" && i + 1 < argc) {
            outputFile = argv[++i];
        } else if (arg == "--audacity") {
            audacityFormat = true;
        }
    }

    try {
        std::cout << "=== Spectral Onset Detector ===" << std::endl;
        std::cout << "Input: " << inputFile << std::endl;

        // Load audio
        uint32_t sampleRate;
        uint16_t numChannels;
        auto buffer = loadWAV(inputFile, sampleRate, numChannels);

        std::cout << "Sample Rate: " << sampleRate << " Hz" << std::endl;
        std::cout << "Channels: " << numChannels << " (converted to mono)" << std::endl;
        std::cout << "Duration: " << buffer.size() / static_cast<float>(sampleRate) << " seconds" << std::endl;
        std::cout << std::endl;

        // Apply preprocessing if requested
        if (usePrefilter) {
            std::cout << "Applying " << prefilterHz << " Hz highpass prefilter..." << std::endl;
            DSP::Butterworth4PoleHighpass hpf(prefilterHz, sampleRate);
            hpf.prepare(sampleRate, buffer.size());
            hpf.process(buffer);
        }

        std::vector<int> onsets;

        if (multiband) {
            std::cout << "Running multi-band onset detection..." << std::endl;
            std::cout << "  Low band:  60-200 Hz (kick)" << std::endl;
            std::cout << "  Mid band:  800-3000 Hz (snare)" << std::endl;
            std::cout << "  High band: 5000-15000 Hz (hi-hat)" << std::endl;

            auto config = DSP::OnsetDetectionConfig::drumDetection();
            config.fftSize = fftSize;
            config.hopSize = hopSize;
            config.medianMultiplier = thresholdMult;
            config.medianWindowSize = medianWin;

            DSP::MultiBandOnsetDetector detector(config, sampleRate);
            detector.prepare(buffer.size());
            onsets = detector.detectOnsets(buffer);

        } else {
            std::cout << "Running simple spectral flux detection..." << std::endl;
            std::cout << "  FFT size: " << fftSize << std::endl;
            std::cout << "  Hop size: " << hopSize << std::endl;

            DSP::SpectralFluxDetector detector(fftSize, hopSize);
            detector.prepare(sampleRate, buffer.size());
            detector.analyze(buffer);
            onsets = detector.findOnsets(thresholdMult, medianWin);
        }

        std::cout << "\n✓ Found " << onsets.size() << " onsets\n" << std::endl;

        // Print onset times
        std::cout << "Onset times:" << std::endl;
        for (size_t i = 0; i < std::min(onsets.size(), size_t(20)); i++) {
            float time = onsets[i] / static_cast<float>(sampleRate);
            std::cout << "  " << (i + 1) << ". " << time << " s (sample " << onsets[i] << ")" << std::endl;
        }

        if (onsets.size() > 20) {
            std::cout << "  ... and " << (onsets.size() - 20) << " more" << std::endl;
        }

        // Write output file if requested
        if (outputFile) {
            std::ofstream out(outputFile);
            if (audacityFormat) {
                for (size_t i = 0; i < onsets.size(); i++) {
                    float time = onsets[i] / static_cast<float>(sampleRate);
                    out << std::fixed << time << "\t" << time << "\tOnset" << (i + 1) << "\n";
                }
            } else {
                for (int onset : onsets) {
                    float time = onset / static_cast<float>(sampleRate);
                    out << time << "\n";
                }
            }
            out.close();
            std::cout << "\n✓ Onsets written to: " << outputFile << std::endl;
        }

    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
