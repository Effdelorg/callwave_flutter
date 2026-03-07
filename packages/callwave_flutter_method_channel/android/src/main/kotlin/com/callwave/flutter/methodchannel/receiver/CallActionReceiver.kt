package com.callwave.flutter.methodchannel.receiver

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.callwave.flutter.methodchannel.CallwaveConstants
import com.callwave.flutter.methodchannel.CallwaveRuntime
import com.callwave.flutter.methodchannel.manager.AcceptResult
import com.callwave.flutter.methodchannel.model.CallPayload

class CallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        CallwaveRuntime.ensureInitialized(context)
        val callId = intent.getStringExtra(CallwaveConstants.EXTRA_CALL_ID) ?: return
        val extraJson = intent.getStringExtra(CallwaveConstants.EXTRA_EXTRA)
        val extra = CallPayload.fromIntentExtras(extraJson)

        when (intent.action) {
            CallwaveConstants.ACTION_ACCEPT -> {
                Log.d(TAG, "CallActionReceiver received ACTION_ACCEPT for $callId.")
                val fallbackPayload = CallwaveRuntime.callManager.payloadFromActionIntent(
                    intent = intent,
                    callId = callId,
                    fallbackExtra = extra,
                )
                if (CallwaveRuntime.callManager.shouldHandleValidatedAcceptInBridge(
                        fallbackPayload,
                    )
                ) {
                    Log.d(TAG, "CallActionReceiver redirecting $callId to validated bridge.")
                    fallbackPayload?.let(CallwaveRuntime.callManager::launchValidatedAcceptBridge)
                    return
                }

                val pendingResult = goAsync()
                var shouldFinishPendingResult = true
                try {
                    val acceptResult = CallwaveRuntime.callManager.onAccept(
                        callId = callId,
                        extra = extra,
                        fallbackPayload = fallbackPayload,
                        shouldOpenAfterConfirm = true,
                        onBackgroundValidationResolved = {
                            pendingResult.finish()
                        },
                    )
                    shouldFinishPendingResult =
                        acceptResult != AcceptResult.VALIDATION_PENDING
                    if (acceptResult == AcceptResult.LAUNCH_NOW &&
                        fallbackPayload != null
                    ) {
                        Log.d(TAG, "CallActionReceiver launching host app for $callId.")
                        launchHostApp(fallbackPayload)
                    }
                } finally {
                    if (shouldFinishPendingResult) {
                        pendingResult.finish()
                    }
                }
            }
            CallwaveConstants.ACTION_DECLINE -> {
                val fallbackPayload = CallwaveRuntime.callManager.payloadFromActionIntent(
                    intent = intent,
                    callId = callId,
                    fallbackExtra = extra,
                )
                CallwaveRuntime.callManager.onDecline(
                    callId = callId,
                    extra = extra,
                    fallbackPayload = fallbackPayload,
                    preferHeadlessReporting = true,
                )
            }
            CallwaveConstants.ACTION_END -> CallwaveRuntime.callManager.endCall(callId)
            CallwaveConstants.ACTION_TIMEOUT -> CallwaveRuntime.callManager.onTimeout(callId)
            CallwaveConstants.ACTION_CALLBACK -> CallwaveRuntime.callManager.onCallback(callId, extra)
        }
    }

    private fun launchHostApp(payload: CallPayload) {
        try {
            CallwaveRuntime.callManager.launchHostApp(
                CallwaveConstants.ACTION_ACCEPT_AND_OPEN,
                payload,
            )
        } catch (error: Throwable) {
            Log.w(TAG, "Unable to launch host app after call accept.", error)
        }
    }

    companion object {
        private const val TAG = "CallwaveFlutter"
    }
}
