package com.callwave.flutter.methodchannel.manager

import java.util.UUID

/** Main-thread-only startup state. Never persisted or recreated on restoration. */
internal class OutgoingRingbackReadiness {
    private data class Attempt(
        val id: String = UUID.randomUUID().toString(),
        val appControlled: Boolean,
        var allowed: Boolean = false,
        var visible: Boolean = false,
    )
    private val pending = HashMap<String, Attempt>()

    fun prepare(callId: String, enabled: Boolean, appControlled: Boolean = false) {
        invalidate(callId)
        if (enabled) pending[callId] = Attempt(appControlled = appControlled)
    }

    fun requestId(callId: String): String? = pending[callId]?.id

    fun allow(callId: String, requestId: String) {
        pending[callId]?.takeIf { it.id == requestId }?.allowed = true
    }

    fun hide(callId: String, requestId: String) {
        pending[callId]?.takeIf { it.id == requestId }?.visible = false
    }

    fun consume(
        callId: String,
        requestId: String,
        active: Boolean,
        outgoing: Boolean,
        connected: Boolean,
        enabled: Boolean,
        visible: Boolean = true,
    ): Boolean {
        val attempt = pending[callId]?.takeIf { it.id == requestId } ?: return false
        if (!active || !outgoing || connected || !enabled) {
            invalidate(callId)
            return false
        }
        if (visible) attempt.visible = true
        if (!attempt.visible || (attempt.appControlled && !attempt.allowed)) return false
        invalidate(callId)
        return true
    }

    fun invalidate(callId: String) { pending.remove(callId) }
    fun clear() = pending.clear()
}
