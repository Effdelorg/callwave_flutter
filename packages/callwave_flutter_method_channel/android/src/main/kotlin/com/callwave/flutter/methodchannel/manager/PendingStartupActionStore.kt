package com.callwave.flutter.methodchannel.manager

import android.content.Context
import com.callwave.flutter.methodchannel.CallwaveConstants
import com.callwave.flutter.methodchannel.model.CallPayload
import com.callwave.flutter.methodchannel.model.CallPayload.Companion.toExtraJson
import org.json.JSONObject

class PendingStartupActionStore(context: Context) {
    private val sharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun save(
        type: String,
        payload: CallPayload,
    ) {
        val json = JSONObject().apply {
            put(CallwaveConstants.EXTRA_STARTUP_ACTION_TYPE, type)
            put(CallwaveConstants.EXTRA_CALL_ID, payload.callId)
            put(CallwaveConstants.EXTRA_CALLER_NAME, payload.callerName)
            put(CallwaveConstants.EXTRA_HANDLE, payload.handle)
            put(CallwaveConstants.EXTRA_AVATAR_URL, payload.avatarUrl)
            put(CallwaveConstants.EXTRA_CALL_TYPE, payload.callType)
            put(
                CallwaveConstants.EXTRA_EXTRA,
                toExtraJson(payload.extra),
            )
        }
        sharedPreferences.edit().putString(KEY_PENDING_ACTION, json.toString()).apply()
    }

    fun take(): Map<String, Any?>? {
        val raw = sharedPreferences.getString(KEY_PENDING_ACTION, null) ?: return null
        sharedPreferences.edit().remove(KEY_PENDING_ACTION).apply()
        return try {
            val json = JSONObject(raw)
            val extra = CallPayload.fromIntentExtras(
                json.optString(CallwaveConstants.EXTRA_EXTRA),
            )
            hashMapOf<String, Any?>(
                CallwaveConstants.EXTRA_STARTUP_ACTION_TYPE to
                    json.optString(CallwaveConstants.EXTRA_STARTUP_ACTION_TYPE),
                CallwaveConstants.EXTRA_CALL_ID to
                    json.optString(CallwaveConstants.EXTRA_CALL_ID),
                CallwaveConstants.EXTRA_CALLER_NAME to
                    json.optString(CallwaveConstants.EXTRA_CALLER_NAME),
                CallwaveConstants.EXTRA_HANDLE to
                    json.optString(CallwaveConstants.EXTRA_HANDLE),
                CallwaveConstants.EXTRA_AVATAR_URL to
                    json.opt(CallwaveConstants.EXTRA_AVATAR_URL).takeUnless { it == JSONObject.NULL },
                CallwaveConstants.EXTRA_CALL_TYPE to
                    json.optString(CallwaveConstants.EXTRA_CALL_TYPE),
                CallwaveConstants.EXTRA_EXTRA to extra,
            )
        } catch (_: Throwable) {
            null
        }
    }

    companion object {
        private const val PREFS_NAME = "callwave_flutter_pending_startup_action"
        private const val KEY_PENDING_ACTION = "pending_startup_action"
    }
}
