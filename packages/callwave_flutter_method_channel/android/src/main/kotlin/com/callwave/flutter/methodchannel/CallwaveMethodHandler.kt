package com.callwave.flutter.methodchannel

import android.app.Activity
import com.callwave.flutter.methodchannel.manager.AndroidCallManager
import com.callwave.flutter.methodchannel.model.CallPayload
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class CallwaveMethodHandler(
    private val callManager: AndroidCallManager,
) : MethodChannel.MethodCallHandler {
    var activity: Activity? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                callManager.initialize()
                result.success(null)
            }

            "showIncomingCall" -> {
                val payload = payloadFromCall(call)
                if (payload == null) {
                    result.error("invalid_payload", "Missing incoming call payload", null)
                    return
                }
                callManager.showIncomingCall(payload)
                result.success(null)
            }

            "showOutgoingCall" -> {
                val payload = payloadFromCall(call)
                if (payload == null) {
                    result.error("invalid_payload", "Missing outgoing call payload", null)
                    return
                }
                callManager.showOutgoingCall(payload)
                result.success(null)
            }

            "endCall" -> {
                val callId = call.argument<String>(CallwaveConstants.EXTRA_CALL_ID)
                if (callId.isNullOrBlank()) {
                    result.error("invalid_call_id", "callId is required", null)
                    return
                }
                callManager.endCall(callId)
                result.success(null)
            }

            "acceptCall" -> {
                val callId = call.argument<String>(CallwaveConstants.EXTRA_CALL_ID)
                if (callId.isNullOrBlank()) {
                    result.error("invalid_call_id", "callId is required", null)
                    return
                }
                if (!callManager.acceptCall(callId)) {
                    result.error(
                        "invalid_call_id",
                        "No active incoming call found for callId=$callId",
                        null,
                    )
                    return
                }
                result.success(null)
            }

            "declineCall" -> {
                val callId = call.argument<String>(CallwaveConstants.EXTRA_CALL_ID)
                if (callId.isNullOrBlank()) {
                    result.error("invalid_call_id", "callId is required", null)
                    return
                }
                if (!callManager.declineCall(callId)) {
                    result.error(
                        "invalid_call_id",
                        "No active incoming call found for callId=$callId",
                        null,
                    )
                    return
                }
                result.success(null)
            }

            "markMissed" -> {
                val callId = call.argument<String>(CallwaveConstants.EXTRA_CALL_ID)
                if (callId.isNullOrBlank()) {
                    result.error("invalid_call_id", "callId is required", null)
                    return
                }
                callManager.markMissed(callId)
                result.success(null)
            }

            "getActiveCallIds" -> {
                result.success(callManager.getActiveCallIds())
            }

            "getActiveCallEventSnapshots" -> {
                result.success(callManager.getActiveCallEventSnapshots())
            }

            "syncActiveCallsToEvents" -> {
                callManager.syncActiveCallsToEvents()
                result.success(null)
            }

            "requestNotificationPermission" -> {
                result.success(callManager.requestNotificationPermission(activity))
            }

            "requestFullScreenIntentPermission" -> {
                callManager.requestFullScreenIntentPermission(activity)
                result.success(null)
            }

            "setPostCallBehavior" -> {
                val behavior = call.argument<String>(CallwaveConstants.EXTRA_POST_CALL_BEHAVIOR)
                callManager.setPostCallBehavior(behavior)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun payloadFromCall(call: MethodCall): CallPayload? {
        val raw = call.arguments as? Map<*, *> ?: return null
        val normalized = raw.entries.associate { it.key.toString() to it.value }
        return try {
            CallPayload.fromMethodArgs(normalized)
        } catch (_: Throwable) {
            null
        }
    }
}
