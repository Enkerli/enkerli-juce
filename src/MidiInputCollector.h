#pragma once

// MidiInputCollector — carry incoming MIDI note events from the audio
// thread (processBlock) to the message thread (editor timer) without a
// lock, so the WebView UI can identify played chords.
//
// MIDI input to an AUv3 is a known source of trouble (hosts route it
// differently; some don't forward it to MIDI-effect nodes at all; the
// audio thread must never touch the WebView or allocate). This is the
// safe pattern, factored out once: a single-producer/single-consumer ring
// buffer of note on/off events. processBlock calls collect(); the editor's
// timer calls drain() and forwards the events over the bridge.
//
// Same discipline as TransportSnapshot/MidiClipScheduler: audio thread
// never blocks, allocates, or calls into JUCE GUI; overflow drops oldest
// (a dropped note-off would stick, so the consumer also resyncs from
// note-ons — see the JS held-notes tracker).

#include <array>
#include <atomic>
#include <juce_audio_basics/juce_audio_basics.h>

namespace enkerli
{

struct MidiNoteEvent
{
    int  note;      // 0–127
    int  velocity;  // 1–127 for on, 0 for off
    bool isOn;
};

class MidiInputCollector
{
public:
    /** Audio thread: scan a block's MIDI buffer for note on/off events. */
    void collect (const juce::MidiBuffer& midi) noexcept
    {
        for (const auto meta : midi)
        {
            const auto m = meta.getMessage();
            if (m.isNoteOn())
                push ({ m.getNoteNumber(), m.getVelocity(), true });
            else if (m.isNoteOff() || (m.isNoteOn() && m.getVelocity() == 0))
                push ({ m.getNoteNumber(), 0, false });
        }
    }

    /** Message thread: move all pending events into `out` (cleared first). */
    void drain (std::vector<MidiNoteEvent>& out) noexcept
    {
        out.clear();
        int r = readPos.load (std::memory_order_relaxed);
        const int w = writePos.load (std::memory_order_acquire);
        while (r != w)
        {
            out.push_back (buffer[(size_t) r]);
            r = (r + 1) % capacity;
        }
        readPos.store (r, std::memory_order_release);
    }

private:
    static constexpr int capacity = 512;

    void push (MidiNoteEvent e) noexcept
    {
        const int w = writePos.load (std::memory_order_relaxed);
        const int next = (w + 1) % capacity;
        if (next == readPos.load (std::memory_order_acquire))
            return; // full — drop (the JS side resyncs held notes from on-events)
        buffer[(size_t) w] = e;
        writePos.store (next, std::memory_order_release);
    }

    std::array<MidiNoteEvent, (size_t) capacity> buffer {};
    std::atomic<int> writePos { 0 };
    std::atomic<int> readPos  { 0 };
};

} // namespace enkerli
