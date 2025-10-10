#include <JuceHeader.h>
#include <iostream>

int main(int argc, char* argv[])
{
    if (argc < 3) {
        std::cerr << "Usage: " << argv[0] << " <input.wav> <output.wav> [cutoff_hz]\n";
        return 1;
    }

    juce::String inputFile = argv[1];
    juce::String outputFile = argv[2];
    double cutoffHz = argc > 3 ? std::stod(argv[3]) : 4000.0;

    std::cout << "=== JUCE Audio Lowpass Filter ===" << std::endl;
    std::cout << "Input: " << inputFile << std::endl;
    std::cout << "Output: " << outputFile << std::endl;
    std::cout << "Cutoff: " << cutoffHz << " Hz" << std::endl;

    // Read input file
    juce::File input(inputFile);
    if (!input.existsAsFile()) {
        std::cerr << "Error: Input file not found!" << std::endl;
        return 1;
    }

    juce::AudioFormatManager formatManager;
    formatManager.registerBasicFormats();

    std::unique_ptr<juce::AudioFormatReader> reader(formatManager.createReaderFor(input));
    if (!reader) {
        std::cerr << "Error: Could not read audio file!" << std::endl;
        return 1;
    }

    int sampleRate = (int)reader->sampleRate;
    int numChannels = (int)reader->numChannels;
    long long numSamples = reader->lengthInSamples;

    std::cout << "\nAudio Info:" << std::endl;
    std::cout << "  Sample Rate: " << sampleRate << " Hz" << std::endl;
    std::cout << "  Channels: " << numChannels << std::endl;
    std::cout << "  Samples: " << numSamples << std::endl;
    std::cout << "  Duration: " << (double)numSamples / sampleRate << " seconds" << std::endl;

    // Read entire file into buffer
    juce::AudioBuffer<float> buffer(numChannels, (int)numSamples);
    reader->read(&buffer, 0, (int)numSamples, 0, true, true);

    // Setup lowpass filter
    std::cout << "\nApplying lowpass filter at " << cutoffHz << " Hz..." << std::endl;

    juce::dsp::ProcessSpec spec;
    spec.sampleRate = sampleRate;
    spec.maximumBlockSize = 512;
    spec.numChannels = numChannels;

    // Create IIR lowpass filter (butterworth, 4th order)
    juce::dsp::ProcessorDuplicator<juce::dsp::IIR::Filter<float>,
                                    juce::dsp::IIR::Coefficients<float>> lowpass;

    auto coefficients = juce::dsp::IIR::Coefficients<float>::makeLowPass(sampleRate, cutoffHz);
    lowpass.state = coefficients;
    lowpass.prepare(spec);

    // Process audio
    juce::dsp::AudioBlock<float> block(buffer);
    juce::dsp::ProcessContextReplacing<float> context(block);
    lowpass.process(context);

    std::cout << "✓ Filter applied" << std::endl;

    // Write output file
    std::cout << "\nWriting output file..." << std::endl;
    juce::File output(outputFile);
    output.deleteFile();

    std::unique_ptr<juce::AudioFormatWriter> writer;
    juce::WavAudioFormat wavFormat;

    if (auto* fileStream = new juce::FileOutputStream(output)) {
        if (fileStream->openedOk()) {
            writer.reset(wavFormat.createWriterFor(fileStream, sampleRate, numChannels, 24, {}, 0));
            if (writer) {
                writer->writeFromAudioSampleBuffer(buffer, 0, buffer.getNumSamples());
                std::cout << "✓ Output written: " << outputFile << std::endl;
            } else {
                std::cerr << "Error: Could not create writer!" << std::endl;
                return 1;
            }
        } else {
            std::cerr << "Error: Could not open output file for writing!" << std::endl;
            delete fileStream;
            return 1;
        }
    }

    std::cout << "\n✓ Done!" << std::endl;
    return 0;
}
