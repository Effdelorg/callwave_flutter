package com.callwave.flutter.methodchannel.manager

import org.junit.Assert.*
import org.junit.Test

class OutgoingRingbackReadinessTest {
    private val readiness = OutgoingRingbackReadiness()

    private fun consume(id: String, active: Boolean = true, outgoing: Boolean = true,
                        connected: Boolean = false, enabled: Boolean = true): Boolean =
        readiness.consume("call", id, active, outgoing, connected, enabled)

    @Test fun startsOnceAndCannotRestartAfterPlaybackStops() {
        readiness.prepare("call", true)
        val id = readiness.requestId("call")!!
        assertTrue(consume(id))
        assertNull(readiness.requestId("call"))
        assertFalse(consume(id)) // Also covers reopening after the sound safety cap.
    }

    @Test fun staleCallbackCannotConsumeNewAttemptWithReusedCallId() {
        readiness.prepare("call", true)
        val old = readiness.requestId("call")!!
        readiness.invalidate("call")
        readiness.prepare("call", true)
        val current = readiness.requestId("call")!!
        assertNotEquals(old, current)
        assertFalse(consume(old))
        assertTrue(consume(current))
    }

    @Test fun disabledCallsDoNotCreateRequests() {
        readiness.prepare("call", false)
        assertNull(readiness.requestId("call"))
        assertFalse(consume("invented"))
    }

    @Test fun rejectsInactiveIncomingConnectedAndDisabledCalls() {
        for (invalid in 0..3) {
            readiness.prepare("call", true)
            val id = readiness.requestId("call")!!
            assertFalse(consume(id, active = invalid != 0, outgoing = invalid != 1,
                                connected = invalid == 2, enabled = invalid != 3))
            assertFalse(consume(id))
        }
    }

    @Test fun connectionCleanupAndIncomingConversionInvalidatePendingReadiness() {
        readiness.prepare("call", true)
        val id = readiness.requestId("call")!!
        readiness.invalidate("call")
        assertFalse(consume(id))
    }

    @Test fun engineDetachAndNewProcessHaveNoPendingReadiness() {
        readiness.prepare("call", true)
        val id = readiness.requestId("call")!!
        readiness.clear()
        assertFalse(consume(id))
        assertNull(OutgoingRingbackReadiness().requestId("call"))
    }
}
