package com.callwave.flutter.methodchannel.manager

import android.content.Context
import com.callwave.flutter.methodchannel.CallwaveConstants
import com.callwave.flutter.methodchannel.model.CallPayload
import com.callwave.flutter.methodchannel.model.CallPayload.Companion.fromIntentExtras
import com.callwave.flutter.methodchannel.model.CallPayload.Companion.toExtraJson
import org.json.JSONObject

internal class IncomingCallStore(context: Context) {
    private val sharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun save(payload: CallPayload, expiresAtMs: Long) {
        val json = JSONObject().apply {
            put(CallwaveConstants.EXTRA_CALL_ID, payload.callId)
            put(CallwaveConstants.EXTRA_CALLER_NAME, payload.callerName)
            put(CallwaveConstants.EXTRA_HANDLE, payload.handle)
            put(CallwaveConstants.EXTRA_AVATAR_URL, payload.avatarUrl)
            put(CallwaveConstants.EXTRA_TIMEOUT_SECONDS, payload.timeoutSeconds)
            put(CallwaveConstants.EXTRA_CALL_TYPE, payload.callType)
            put(CallwaveConstants.EXTRA_EXTRA, toExtraJson(payload.extra))
            put(
                CallwaveConstants.EXTRA_INCOMING_ACCEPT_STRATEGY,
                payload.incomingAcceptStrategy,
            )
            put(
                CallwaveConstants.EXTRA_BACKGROUND_DISPATCHER_HANDLE,
                payload.backgroundDispatcherHandle,
            )
            put(
                CallwaveConstants.EXTRA_BACKGROUND_CALLBACK_HANDLE,
                payload.backgroundCallbackHandle,
            )
            put(
                CallwaveConstants.EXTRA_BACKGROUND_DECLINE_CALLBACK_HANDLE,
                payload.backgroundDeclineCallbackHandle,
            )
            put(CallwaveConstants.EXTRA_EXPIRES_AT_MS, expiresAtMs)
        }
        sharedPreferences.edit().putString(KEY_INCOMING_CALL, json.toString()).apply()
    }

    fun restore(): StoredIncomingCall? {
        val raw = sharedPreferences.getString(KEY_INCOMING_CALL, null) ?: return null
        return try {
            val json = JSONObject(raw)
            val payload = CallPayload(
                callId = json.optString(CallwaveConstants.EXTRA_CALL_ID),
                callerName = json.optString(CallwaveConstants.EXTRA_CALLER_NAME, "Unknown"),
                handle = json.optString(CallwaveConstants.EXTRA_HANDLE),
                avatarUrl =
                    json.opt(CallwaveConstants.EXTRA_AVATAR_URL).takeUnless { it == JSONObject.NULL }
                        as? String,
                timeoutSeconds = json.optInt(CallwaveConstants.EXTRA_TIMEOUT_SECONDS, 30),
                callType = json.optString(CallwaveConstants.EXTRA_CALL_TYPE, "audio"),
                extra = fromIntentExtras(json.optString(CallwaveConstants.EXTRA_EXTRA)),
                incomingAcceptStrategy = json.optString(
                    CallwaveConstants.EXTRA_INCOMING_ACCEPT_STRATEGY,
                    CallwaveConstants.INCOMING_ACCEPT_STRATEGY_OPEN_IMMEDIATELY,
                ),
                backgroundDispatcherHandle =
                    json.optLong(CallwaveConstants.EXTRA_BACKGROUND_DISPATCHER_HANDLE, 0L)
                        .takeIf { it > 0L },
                backgroundCallbackHandle =
                    json.optLong(CallwaveConstants.EXTRA_BACKGROUND_CALLBACK_HANDLE, 0L)
                        .takeIf { it > 0L },
                backgroundDeclineCallbackHandle =
                    json.optLong(
                        CallwaveConstants.EXTRA_BACKGROUND_DECLINE_CALLBACK_HANDLE,
                        0L,
                    ).takeIf { it > 0L },
            )
            val expiresAtMs = json.optLong(CallwaveConstants.EXTRA_EXPIRES_AT_MS, 0L)
                .takeIf { it > 0L }
                ?: (System.currentTimeMillis() + payload.timeoutSeconds.coerceAtLeast(1) * 1000L)
            if (payload.callId.isBlank()) {
                null
            } else {
                StoredIncomingCall(
                    payload = payload,
                    expiresAtMs = expiresAtMs,
                )
            }
        } catch (_: Throwable) {
            null
        }
    }

    fun clear(callId: String? = null) {
        if (callId != null) {
            val current = restore() ?: return
            if (current.payload.callId != callId) {
                return
            }
        }
        sharedPreferences.edit().remove(KEY_INCOMING_CALL).apply()
    }

    internal data class StoredIncomingCall(
        val payload: CallPayload,
        val expiresAtMs: Long,
    )

    companion object {
        private const val PREFS_NAME = "callwave_flutter_incoming_call"
        private const val KEY_INCOMING_CALL = "incoming_call"
    }
}
