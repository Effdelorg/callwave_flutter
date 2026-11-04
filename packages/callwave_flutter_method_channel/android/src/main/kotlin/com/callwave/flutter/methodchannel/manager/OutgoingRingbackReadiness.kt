package com.callwave.flutter.methodchannel.manager

import java.util.UUID

/** Main-thread-only, in-memory permissions to start ringback once per attempt. */
internal class OutgoingRingbackReadiness {
    private val pending = HashMap<String, String>()

    fun prepare(callId: String, enabled: Boolean) {
        invalidate(callId)
        if (enabled) pending[callId] = UUID.randomUUID().toString()
    }

    fun requestId(callId: String): String? = pending[callId]

    fun consume(
        callId: String,
        requestId: String,
        active: Boolean,
        outgoing: Boolean,
        connected: Boolean,
        enabled: Boolean,
    ): Boolean {
        if (pending[callId] != requestId) return false
        pending.remove(callId)
        return active && outgoing && !connected && enabled
    }

    fun invalidate(callId: String) {
        pending.remove(callId)
    }

    fun clear() = pending.clear()
}
