package com.callwave.flutter.methodchannel.manager

import android.content.Context
import com.callwave.flutter.methodchannel.CallwaveConstants
import com.callwave.flutter.methodchannel.model.CallPayload
import com.callwave.flutter.methodchannel.model.CallPayload.Companion.fromIntentExtras
import com.callwave.flutter.methodchannel.model.CallPayload.Companion.toExtraJson
import org.json.JSONObject

internal class OngoingCallStore(context: Context) {
    private val sharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun save(
        payload: CallPayload,
        eventType: String,
        connectedAtMs: Long?,
    ) {
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
            put(KEY_EVENT_TYPE, eventType)
            put(KEY_CONNECTED_AT_MS, connectedAtMs)
        }
        sharedPreferences.edit().putString(KEY_ONGOING_CALL, json.toString()).apply()
    }

    fun updateConnectedAt(callId: String, connectedAtMs: Long) {
        val snapshot = takeCurrent() ?: return
        if (snapshot.payload.callId != callId) {
            return
        }
        save(
            payload = snapshot.payload,
            eventType = snapshot.eventType,
            connectedAtMs = connectedAtMs,
        )
    }

    fun restore(): StoredOngoingCall? {
        return takeCurrent()
    }

    fun clear(callId: String? = null) {
        if (callId != null) {
            val current = takeCurrent() ?: return
            if (current.payload.callId != callId) {
                return
            }
        }
        sharedPreferences.edit().remove(KEY_ONGOING_CALL).apply()
    }

    private fun takeCurrent(): StoredOngoingCall? {
        val raw = sharedPreferences.getString(KEY_ONGOING_CALL, null) ?: return null
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
            )
            val eventType = json.optString(KEY_EVENT_TYPE)
            if (payload.callId.isBlank() || eventType.isBlank()) {
                null
            } else {
                StoredOngoingCall(
                    payload = payload,
                    eventType = eventType,
                    connectedAtMs =
                        json.optLong(KEY_CONNECTED_AT_MS, 0L).takeIf { it > 0L },
                )
            }
        } catch (_: Throwable) {
            null
        }
    }

    internal data class StoredOngoingCall(
        val payload: CallPayload,
        val eventType: String,
        val connectedAtMs: Long?,
    )

    companion object {
        private const val PREFS_NAME = "callwave_flutter_ongoing_call"
        private const val KEY_ONGOING_CALL = "ongoing_call"
        private const val KEY_EVENT_TYPE = "eventType"
        private const val KEY_CONNECTED_AT_MS = "connectedAtMs"
    }
}
