#pragma once
#include <juce_audio_processors/juce_audio_processors.h>
#include "../../../src/MidiClipScheduler.h"

// BridgePilot — minimal aumi pathfinder proving the foundation:
// archetype CMake settings + WebView bridge + host-synced MIDI scheduler.
class BridgePilotProcessor : public juce::AudioProcessor
{
public:
    BridgePilotProcessor()
        : juce::AudioProcessor (BusesProperties()) // MIDI effect: no audio buses
    {
    }

    void prepareToPlay (double newSampleRate, int) override { sampleRate = newSampleRate; }
    void releaseResources() override {}

    void processBlock (juce::AudioBuffer<float>& audio, juce::MidiBuffer& midi) override
    {
        audio.clear();
        // Pass incoming MIDI through, add scheduled clip events.
        scheduler.process (getPlayHead(), sampleRate, audio.getNumSamples() > 0 ? audio.getNumSamples() : lastBlockSize, midi);
    }

    void processBlock (juce::AudioBuffer<double>& audio, juce::MidiBuffer& midi) override
    {
        juce::AudioBuffer<float> dummy;
        juce::ignoreUnused (audio);
        scheduler.process (getPlayHead(), sampleRate, lastBlockSize, midi);
    }

    bool isMidiEffect() const override { return true; }
    bool acceptsMidi() const override { return true; }
    bool producesMidi() const override { return true; }

    juce::AudioProcessorEditor* createEditor() override;
    bool hasEditor() const override { return true; }

    const juce::String getName() const override { return "BridgePilot"; }
    double getTailLengthSeconds() const override { return 0.0; }

    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram (int) override {}
    const juce::String getProgramName (int) override { return {}; }
    void changeProgramName (int, const juce::String&) override {}

    void getStateInformation (juce::MemoryBlock&) override {}
    void setStateInformation (const void*, int) override {}

    enkerli::MidiClipScheduler scheduler;

private:
    double sampleRate = 44100.0;
    int lastBlockSize = 512;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (BridgePilotProcessor)
};
