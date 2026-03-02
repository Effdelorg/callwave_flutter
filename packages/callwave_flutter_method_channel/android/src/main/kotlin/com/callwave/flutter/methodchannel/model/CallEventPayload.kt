package com.callwave.flutter.methodchannel.model

import com.callwave.flutter.methodchannel.CallwaveConstants
import org.json.JSONObject

data class CallEventPayload(
    val callId: String,
    val type: String,
    val timestampMs: Long,
    val extra: Map<String, Any?>?,
) {
    fun toMap(): Map<String, Any?> {
        return mapOf(
            CallwaveConstants.EXTRA_CALL_ID to callId,
            "type" to type,
            "timestampMs" to timestampMs,
            "extra" to extra,
        )
    }

    fun dedupeKey(): String {
        val secondBucket = timestampMs / 1000L
        return "$callId|$type|$secondBucket"
    }

    fun toJson(): JSONObject {
        return JSONObject().apply {
            put(CallwaveConstants.EXTRA_CALL_ID, callId)
            put("type", type)
            put("timestampMs", timestampMs)
            put("extra", if (extra == null) JSONObject.NULL else JSONObject(extra))
        }
    }

    companion object {
        fun now(callId: String, type: String, extra: Map<String, Any?>?): CallEventPayload {
            return CallEventPayload(
                callId = callId,
                type = type,
                timestampMs = System.currentTimeMillis(),
                extra = extra,
            )
        }

        fun fromJson(json: JSONObject): CallEventPayload? {
            val callId = json.optString(CallwaveConstants.EXTRA_CALL_ID)
            val type = json.optString("type")
            val timestamp = json.optLong("timestampMs", 0L)
            if (callId.isBlank() || type.isBlank() || timestamp <= 0L) {
                return null
            }

            val extraJson = json.optJSONObject("extra")
            val extraMap = extraJson?.keys()?.asSequence()?.associateWith { key ->
                extraJson.opt(key)
            }

            return CallEventPayload(
                callId = callId,
                type = type,
                timestampMs = timestamp,
                extra = extraMap,
            )
        }
    }
}
