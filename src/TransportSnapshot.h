#pragma once
/*
  TransportSnapshot — the only safe way to show host transport in a UI.

  juce::AudioPlayHead is an audio-thread object: querying it from the
  editor (message thread) returns empty or stale data in AUv3 hosts —
  AUM shows "stopped" while playing — even though some macOS hosts let
  it slide, which is how the bug survives desktop testing.

  Pattern: the processor calls capture() inside processBlock; the editor
  reads the atomics from its timer. Lock-free both sides.
*/

#include <juce_audio_basics/juce_audio_basics.h>
#include <atomic>

namespace enkerli
{

class TransportSnapshot
{
public:
    /** Audio thread, once per block. */
    void capture (juce::AudioPlayHead* playHead) noexcept
    {
        bool isPlaying = false;
        double currentBpm = 0.0;
        double currentPpq = 0.0;

        if (playHead != nullptr)
        {
            if (auto pos = playHead->getPosition())
            {
                isPlaying = pos->getIsPlaying();
                if (auto b = pos->getBpm()) currentBpm = *b;
                if (auto p = pos->getPpqPosition()) currentPpq = *p;
            }
        }

        playing.store (isPlaying, std::memory_order_relaxed);
        bpm.store (currentBpm, std::memory_order_relaxed);
        ppq.store (currentPpq, std::memory_order_relaxed);
    }

    /** Message thread (editor timers, WebView events). */
    bool isPlaying() const noexcept { return playing.load (std::memory_order_relaxed); }
    double getBpm() const noexcept { return bpm.load (std::memory_order_relaxed); }
    double getPpq() const noexcept { return ppq.load (std::memory_order_relaxed); }

private:
    std::atomic<bool> playing { false };
    std::atomic<double> bpm { 0.0 };
    std::atomic<double> ppq { 0.0 };
};

} // namespace enkerli
