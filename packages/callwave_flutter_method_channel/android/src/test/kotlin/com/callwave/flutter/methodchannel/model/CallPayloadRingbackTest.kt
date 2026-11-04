package com.callwave.flutter.methodchannel.model

import org.junit.Assert.*
import org.junit.Test

class CallPayloadRingbackTest {
    @Test fun modeRoundTripsAndDefaultsToAutomatic() {
        for (raw in listOf(null, "unknown", "automatic", "appControlled")) {
            val args = mutableMapOf<String, Any?>("callId" to "call", "ringbackStartMode" to raw)
            val payload = CallPayload.fromMethodArgs(args)
            val expected = if (raw == "appControlled") raw else "automatic"
            assertEquals(expected, payload.ringbackStartMode)
            assertEquals(expected, payload.toMethodArgs()["ringbackStartMode"])
            assertTrue(payload.playRingback)
            assertEquals(120, payload.maxRingbackSeconds)
        }
        val disabled = CallPayload.fromMethodArgs(mapOf("callId" to "call", "playRingback" to false,
            "ringbackStartMode" to "appControlled", "maxRingbackSeconds" to 15))
        assertFalse(disabled.playRingback)
        assertEquals(15, disabled.maxRingbackSeconds)
        assertEquals("appControlled", disabled.copy(extra = mapOf("key" to "value")).ringbackStartMode)
    }
}
