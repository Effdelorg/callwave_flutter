package com.callwave.flutter.methodchannel.model

import com.callwave.flutter.methodchannel.CallwaveConstants
import org.json.JSONObject

data class CallPayload(
    val callId: String,
    val callerName: String,
    val handle: String,
    val avatarUrl: String?,
    val timeoutSeconds: Int,
    val callType: String,
    val extra: Map<String, Any?>?,
    val incomingAcceptStrategy: String,
    val backgroundDispatcherHandle: Long?,
    val backgroundCallbackHandle: Long?,
) {
    fun toMethodArgs(): Map<String, Any?> {
        return mapOf(
            CallwaveConstants.EXTRA_CALL_ID to callId,
            CallwaveConstants.EXTRA_CALLER_NAME to callerName,
            CallwaveConstants.EXTRA_HANDLE to handle,
            CallwaveConstants.EXTRA_AVATAR_URL to avatarUrl,
            CallwaveConstants.EXTRA_TIMEOUT_SECONDS to timeoutSeconds,
            CallwaveConstants.EXTRA_CALL_TYPE to callType,
            CallwaveConstants.EXTRA_EXTRA to extra,
            CallwaveConstants.EXTRA_INCOMING_ACCEPT_STRATEGY to incomingAcceptStrategy,
            CallwaveConstants.EXTRA_BACKGROUND_DISPATCHER_HANDLE to backgroundDispatcherHandle,
            CallwaveConstants.EXTRA_BACKGROUND_CALLBACK_HANDLE to backgroundCallbackHandle,
        )
    }

    companion object {
        fun fromMethodArgs(args: Map<String, Any?>): CallPayload {
            val timeoutSeconds = (args[CallwaveConstants.EXTRA_TIMEOUT_SECONDS] as? Number)?.toInt() ?: 30
            return CallPayload(
                callId = args[CallwaveConstants.EXTRA_CALL_ID] as String,
                callerName = args[CallwaveConstants.EXTRA_CALLER_NAME] as? String ?: "Unknown",
                handle = args[CallwaveConstants.EXTRA_HANDLE] as? String ?: "",
                avatarUrl = args[CallwaveConstants.EXTRA_AVATAR_URL] as? String,
                timeoutSeconds = timeoutSeconds,
                callType = args[CallwaveConstants.EXTRA_CALL_TYPE] as? String ?: "audio",
                extra = (args[CallwaveConstants.EXTRA_EXTRA] as? Map<*, *>)
                    ?.entries
                    ?.associate { it.key.toString() to it.value },
                incomingAcceptStrategy = args[CallwaveConstants.EXTRA_INCOMING_ACCEPT_STRATEGY]
                    as? String ?: CallwaveConstants.INCOMING_ACCEPT_STRATEGY_OPEN_IMMEDIATELY,
                backgroundDispatcherHandle =
                    (args[CallwaveConstants.EXTRA_BACKGROUND_DISPATCHER_HANDLE] as? Number)
                        ?.toLong(),
                backgroundCallbackHandle =
                    (args[CallwaveConstants.EXTRA_BACKGROUND_CALLBACK_HANDLE] as? Number)
                        ?.toLong(),
            )
        }

        fun fromIntentExtras(extras: String?): Map<String, Any?>? {
            if (extras.isNullOrBlank()) {
                return null
            }
            return try {
                val json = JSONObject(extras)
                json.keys().asSequence().associateWith { key -> json.opt(key) }
            } catch (_: Throwable) {
                null
            }
        }

        fun toExtraJson(extra: Map<String, Any?>?): String? {
            if (extra == null) {
                return null
            }
            return try {
                JSONObject(extra).toString()
            } catch (_: Throwable) {
                null
            }
        }
    }
}
