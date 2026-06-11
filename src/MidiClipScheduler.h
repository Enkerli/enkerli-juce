#pragma once
/*
  MidiClipScheduler — host-synced playback of a beat-positioned MIDI clip,
  for aumi-archetype plugins (the Progression Studio plugin path: the
  WebView sends a voiced progression; this emits it as MIDI, following the
  host transport when it runs and an internal clock when it doesn't).

  Real-time rules: setClip swaps an immutable shared_ptr (no locks in
  process); transport stop or clip swap flushes note-offs; loops wrap
  sample-accurately within the block.
*/

#include <juce_audio_basics/juce_audio_basics.h>
#include <atomic>
#include <cmath>
#include <memory>
#include <vector>

namespace enkerli
{

struct ClipNote
{
    double startBeat = 0.0;
    double lengthBeats = 1.0;
    int pitch = 60;
    int velocity = 96;
    int channel = 1; // 1-based, JUCE convention
};

class MidiClipScheduler
{
public:
    struct Clip
    {
        std::vector<ClipNote> notes;
        double lengthBeats = 0.0;
        bool loop = true;
    };

    /** Message-thread side. Takes effect at the next block. */
    void setClip (Clip clip)
    {
        std::atomic_store_explicit (&pending, std::make_shared<const Clip> (std::move (clip)),
                                    std::memory_order_release);
    }

    void clear() { setClip ({}); }

    void setFallbackBpm (double bpm) { fallbackBpm.store (bpm, std::memory_order_relaxed); }
    void setRunWithoutTransport (bool shouldRun) { freeRun.store (shouldRun, std::memory_order_relaxed); }

    /** Audio-thread side: append events for this block into `midi`. */
    void process (juce::AudioPlayHead* playHead, double sampleRate, int numSamples, juce::MidiBuffer& midi)
    {
        if (auto next = std::atomic_exchange_explicit (&pending, std::shared_ptr<const Clip> {},
                                                       std::memory_order_acquire))
        {
            flushActive (midi, 0);
            current = std::move (next);
            positionValid = false;
        }

        if (current == nullptr || current->notes.empty() || current->lengthBeats <= 0.0)
            return;

        double bpm = fallbackBpm.load (std::memory_order_relaxed);
        bool hostPlaying = false;
        double hostPpq = 0.0;

        if (playHead != nullptr)
        {
            if (auto pos = playHead->getPosition())
            {
                hostPlaying = pos->getIsPlaying();
                if (auto b = pos->getBpm()) bpm = *b;
                if (auto p = pos->getPpqPosition()) hostPpq = *p;
            }
        }

        const bool running = hostPlaying || freeRun.load (std::memory_order_relaxed);
        if (! running)
        {
            if (wasRunning)
                flushActive (midi, 0);
            wasRunning = false;
            positionValid = false;
            return;
        }

        const double beatsPerSample = bpm / 60.0 / sampleRate;
        const double blockBeats = beatsPerSample * numSamples;

        double blockStart;
        if (hostPlaying)
        {
            blockStart = hostPpq;
            // A transport jump (loop, relocate) invalidates held notes.
            if (positionValid && std::abs (hostPpq - expectedNextPpq) > blockBeats)
                flushActive (midi, 0);
        }
        else
        {
            if (! positionValid)
                internalBeat = 0.0;
            blockStart = internalBeat;
        }
        const double blockEnd = blockStart + blockBeats;

        emitWindow (blockStart, blockEnd, beatsPerSample, numSamples, midi);

        internalBeat = blockEnd;
        expectedNextPpq = blockEnd;
        positionValid = true;
        wasRunning = true;
    }

    /** All-notes-off into the buffer (e.g. from releaseResources). */
    void panic (juce::MidiBuffer& midi) { flushActive (midi, 0); }

private:
    struct Active
    {
        int pitch, channel;
        double offBeat; // absolute (unwrapped) timeline
    };

    void emitWindow (double startBeat, double endBeat, double beatsPerSample,
                     int numSamples, juce::MidiBuffer& midi)
    {
        const auto& clip = *current;
        auto toSample = [&] (double beat)
        {
            auto s = static_cast<int> ((beat - startBeat) / beatsPerSample);
            return juce::jlimit (0, numSamples - 1, s);
        };

        // Note-offs due in this window.
        for (size_t i = active.size(); i-- > 0;)
        {
            if (active[i].offBeat < endBeat)
            {
                midi.addEvent (juce::MidiMessage::noteOff (active[i].channel, active[i].pitch),
                               toSample (active[i].offBeat));
                active.erase (active.begin() + static_cast<long> (i));
            }
        }

        // Note-ons whose (possibly loop-wrapped) start falls in the window.
        for (const auto& note : clip.notes)
        {
            double start = note.startBeat;
            if (clip.loop)
            {
                const double offset = std::floor ((startBeat - note.startBeat) / clip.lengthBeats) * clip.lengthBeats;
                start = note.startBeat + offset;
                if (start < startBeat)
                    start += clip.lengthBeats;
            }
            if (start >= startBeat && start < endBeat)
            {
                if (! clip.loop && note.startBeat != start)
                    continue;
                midi.addEvent (juce::MidiMessage::noteOn (note.channel, note.pitch,
                                                          static_cast<juce::uint8> (note.velocity)),
                               toSample (start));
                active.push_back ({ note.pitch, note.channel, start + note.lengthBeats });
            }
        }
    }

    void flushActive (juce::MidiBuffer& midi, int sample)
    {
        for (const auto& a : active)
            midi.addEvent (juce::MidiMessage::noteOff (a.channel, a.pitch), sample);
        active.clear();
    }

    std::shared_ptr<const Clip> pending;
    std::shared_ptr<const Clip> current;
    std::vector<Active> active;
    std::atomic<double> fallbackBpm { 120.0 };
    std::atomic<bool> freeRun { false };
    double internalBeat = 0.0;
    double expectedNextPpq = 0.0;
    bool positionValid = false;
    bool wasRunning = false;
};

} // namespace enkerli
