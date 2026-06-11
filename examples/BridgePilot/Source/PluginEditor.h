#pragma once
#include "PluginProcessor.h"
#include "../../../src/EnkerliWebView.h"
#include "BinaryDataWebUI.h"

class BridgePilotEditor : public juce::AudioProcessorEditor,
                          private juce::Timer
{
public:
    explicit BridgePilotEditor (BridgePilotProcessor& p)
        : juce::AudioProcessorEditor (p),
          proc (p),
          web (
              { { "/index.html", { BinaryData::index_html, BinaryData::index_htmlSize, "text/html; charset=utf-8" } } },
              {
                  { "uiReady", [this] (const juce::var&) { pageReady = true; } },
                  { "enkerliSetClip", [this] (const juce::var& v) { applyClip (v); } },
                  { "enkerliClearClip", [this] (const juce::var&) { proc.scheduler.clear(); } },
              })
    {
        addAndMakeVisible (web);
        web.start();
        setSize (480, 360);
        setResizable (true, true);
        startTimerHz (4);
    }

    void resized() override { web.setBounds (getLocalBounds()); }

private:
    void applyClip (const juce::var& v)
    {
        enkerli::MidiClipScheduler::Clip clip;
        clip.lengthBeats = static_cast<double> (v.getProperty ("lengthBeats", 0.0));
        clip.loop = static_cast<bool> (v.getProperty ("loop", true));
        if (auto* arr = v.getProperty ("notes", juce::var()).getArray())
        {
            for (const auto& n : *arr)
            {
                enkerli::ClipNote note;
                note.startBeat = static_cast<double> (n.getProperty ("startBeat", 0.0));
                note.lengthBeats = static_cast<double> (n.getProperty ("lengthBeats", 1.0));
                note.pitch = static_cast<int> (n.getProperty ("pitch", 60));
                note.velocity = static_cast<int> (n.getProperty ("velocity", 96));
                note.channel = juce::jlimit (1, 16, static_cast<int> (n.getProperty ("channel", 1)));
                clip.notes.push_back (note);
            }
        }
        proc.scheduler.setRunWithoutTransport (true); // pilot: audible without a transport
        proc.scheduler.setClip (std::move (clip));
    }

    void timerCallback() override
    {
        if (! pageReady)
            return;
        // Never query AudioPlayHead here (message thread) — read the
        // processor's audio-thread snapshot instead (TransportSnapshot.h).
        auto* obj = new juce::DynamicObject();
        obj->setProperty ("bpm", proc.transport.getBpm());
        obj->setProperty ("playing", proc.transport.isPlaying());
        web.emit ("transport", juce::var (obj));
    }

    BridgePilotProcessor& proc;
    enkerli::BridgedWebView web;
    bool pageReady = false;
};

inline juce::AudioProcessorEditor* BridgePilotProcessor::createEditor()
{
    return new BridgePilotEditor (*this);
}
