// SPDX-License-Identifier: Apache-2.0
// AtmosphereSubtitleForwarder.kt — forwards libmpv subtitle cues to the
// ATMOSphere Presenter VideoOutputManager so they render on the secondary
// HDMI display when MPV is routed to TV.
//
// QA Session 26.04.01 User #6 Tier C2 — mpv-player fork.
// Covers the libmpv OpenGL-render path that the Presenter
// AccessibilityService (Tier B) cannot observe via the view tree.
//
// How it works:
//   1. MPVView.observeProperties is extended to include sub-text,
//      sub-start, sub-end.
//   2. Attaching this observer to MPVLib makes libmpv emit a PropertyChange
//      event every time the active subtitle text changes (every cue
//      boundary).
//   3. We call VideoOutputManager#routeSubtitleCue via reflection,
//      passing the current sub-text. VOM returns true when there's an
//      active secondary-display route for this app, meaning Presenter
//      is now rendering the cue on the TV. We DON'T disable libmpv's
//      own sub-render on the primary — primary sub-hiding is handled
//      by the Presenter PrimarySubtitleOverlay, not at the player.
//
// Works without modifying any libmpv C code. The JNI bindings in
// MPVLib already expose the property-observer callback pipeline.

package `is`.xyz.mpv

import android.os.IBinder
import android.util.Log

class AtmosphereSubtitleForwarder : MPVLib.EventObserver {

    companion object {
        private const val TAG = "ATMOSphere::MpvSubFwd"
        private const val PKG = "is.xyz.mpv"
    }

    @Volatile private var currentText: String = ""
    @Volatile private var vomBinder: IBinder? = null

    override fun eventProperty(property: String) {
        // No-op — we only care about typed variants below.
    }

    override fun eventProperty(property: String, value: Long) {
        // No-op — sub-start / sub-end are Double in mpv; Long path unused.
    }

    override fun eventProperty(property: String, value: Boolean) {
        // No-op — subtitles are not boolean.
    }

    override fun eventProperty(property: String, value: String) {
        if (property != "sub-text") return
        val text = value.trim()
        if (text == currentText) return
        currentText = text
        dispatch(text)
    }

    override fun eventProperty(property: String, value: Double) {
        // No-op — sub-start / sub-end aren't needed for forwarding;
        // sub-text already arrives timed by mpv.
    }

    override fun event(eventId: Int) {
        // END_FILE / IDLE: drop any lingering cue so Presenter clears.
        if (eventId == MPVLib.MpvEvent.MPV_EVENT_END_FILE ||
            eventId == MPVLib.MpvEvent.MPV_EVENT_SHUTDOWN ||
            @Suppress("DEPRECATION") eventId == MPVLib.MpvEvent.MPV_EVENT_IDLE
        ) {
            if (currentText.isNotEmpty()) {
                currentText = ""
                dispatch("")
            }
        }
    }

    private fun dispatch(text: String) {
        try {
            val binder = vomBinder ?: (getServiceBinder("video_output")?.also {
                vomBinder = it
            })
            if (binder == null) {
                // Service may not be up (e.g. on non-ATMOSphere builds);
                // stay silent to avoid log spam.
                return
            }
            val stubCls = Class.forName("android.media.IVideoOutputManager\$Stub")
            val asInterface = stubCls.getMethod("asInterface", IBinder::class.java)
            val vom = asInterface.invoke(null, binder)
            val routeFn = vom.javaClass.getMethod(
                "routeSubtitleCue",
                String::class.java, String::class.java,
                Long::class.javaPrimitiveType, Long::class.javaPrimitiveType,
                String::class.java
            )
            routeFn.invoke(vom, PKG, text, 0L, 0L, "")
        } catch (t: Throwable) {
            // Non-ATMOSphere build, or early-boot service-not-ready, etc.
            // Forwarding is best-effort.
        }
    }

    private fun getServiceBinder(name: String): IBinder? {
        return try {
            val sm = Class.forName("android.os.ServiceManager")
            sm.getMethod("getService", String::class.java).invoke(null, name) as IBinder?
        } catch (t: Throwable) {
            null
        }
    }
}
