#pragma once
/*
  RuntimeInfo — on-device runtime observability for host testing.

  iPadOS plugin failures are usually invisible: the AUv3 memory ceiling
  kills extensions without a dialog, hosts differ in what transport and
  sample-rate they provide, and "which host am I even in" matters for
  bug reports. This helper snapshots the runtime facts cheaply so the
  WebView UI can display them (and testers can read them off the screen
  of a misbehaving device).

  memoryFootprintMB uses phys_footprint — the same number iOS enforces
  its extension limit against (not resident size, which under-reports).
*/

#include <juce_audio_processors/juce_audio_processors.h>

#if JUCE_MAC || JUCE_IOS
 #include <mach/mach.h>
#endif

namespace enkerli
{

struct RuntimeInfo
{
    /** Footprint in MB as the OS counts it, or -1 when unavailable. */
    static double memoryFootprintMB()
    {
       #if JUCE_MAC || JUCE_IOS
        task_vm_info_data_t info {};
        mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
        if (task_info (mach_task_self(), TASK_VM_INFO,
                       reinterpret_cast<task_info_t> (&info), &count) == KERN_SUCCESS)
            return static_cast<double> (info.phys_footprint) / (1024.0 * 1024.0);
       #endif
        return -1.0;
    }

    /** Message-thread snapshot for UI display / bug reports. */
    static juce::var snapshot (const juce::AudioProcessor& processor)
    {
        auto* obj = new juce::DynamicObject();
        obj->setProperty ("memMB", std::round (memoryFootprintMB() * 10.0) / 10.0);
        obj->setProperty ("wrapper",
            juce::String (juce::AudioProcessor::getWrapperTypeDescription (processor.wrapperType)));
        obj->setProperty ("host", juce::PluginHostType().getHostDescription());
        obj->setProperty ("sampleRate", processor.getSampleRate());
        obj->setProperty ("juce", juce::String (JUCE_STRINGIFY (JUCE_MAJOR_VERSION)
                                                "." JUCE_STRINGIFY (JUCE_MINOR_VERSION)
                                                "." JUCE_STRINGIFY (JUCE_BUILDNUMBER)));
        return juce::var (obj);
    }
};

} // namespace enkerli
