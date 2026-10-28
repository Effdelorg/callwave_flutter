package com.callwave.flutter.methodchannel.manager

import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * Plays the region-appropriate ringback tone (via [ToneGenerator.TONE_SUP_RINGTONE])
 * while an outgoing call waits to be answered. Audio mode and routing are left
 * to the host app. Stops on its own after the call's max ringback duration as a
 * safety cap.
 */
internal class OutgoingRingbackController {
    private val lock = Any()
    private var activeCallId: String? = null
    private var toneGenerator: ToneGenerator? = null
    private var capRunnable: Runnable? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    fun start(callId: String, maxDurationMs: Long) {
        synchronized(lock) {
            if (activeCallId == callId && toneGenerator != null) {
                return
            }
            stopLocked()
            val generator = try {
                ToneGenerator(AudioManager.STREAM_VOICE_CALL, TONE_VOLUME)
            } catch (error: RuntimeException) {
                Log.w(TAG, "Unable to create ringback tone generator for outgoing call $callId.", error)
                return
            }
            val started = try {
                generator.startTone(ToneGenerator.TONE_SUP_RINGTONE)
            } catch (error: RuntimeException) {
                Log.w(TAG, "Failed to start ringback tone for outgoing call $callId.", error)
                false
            }
            if (!started) {
                releaseGenerator(generator)
                return
            }
            activeCallId = callId
            toneGenerator = generator
            val cap = object : Runnable {
                override fun run() {
                    synchronized(lock) {
                        // A stop/start may have replaced this cap after it was dequeued.
                        if (capRunnable !== this) {
                            return
                        }
                        Log.w(TAG, "Ringback for outgoing call $callId reached the safety cap.")
                        stopLocked()
                    }
                }
            }
            capRunnable = cap
            mainHandler.postDelayed(cap, maxDurationMs)
        }
    }

    fun stop(callId: String) {
        synchronized(lock) {
            if (activeCallId != callId) {
                return
            }
            stopLocked()
        }
    }

    fun stopAll() {
        synchronized(lock) {
            stopLocked()
        }
    }

    private fun stopLocked() {
        capRunnable?.let(mainHandler::removeCallbacks)
        capRunnable = null
        activeCallId = null
        val currentGenerator = toneGenerator
        toneGenerator = null
        if (currentGenerator != null) {
            releaseGenerator(currentGenerator)
        }
    }

    private fun releaseGenerator(generator: ToneGenerator) {
        try {
            generator.stopTone()
        } catch (_: Throwable) {
        } finally {
            generator.release()
        }
    }

    private companion object {
        private const val TAG = "CallwaveFlutter"
        private const val TONE_VOLUME = 80
    }
}
