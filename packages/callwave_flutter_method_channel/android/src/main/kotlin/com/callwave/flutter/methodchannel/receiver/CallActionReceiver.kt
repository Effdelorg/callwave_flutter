package com.callwave.flutter.methodchannel.receiver

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.callwave.flutter.methodchannel.CallwaveConstants
import com.callwave.flutter.methodchannel.CallwaveRuntime
import com.callwave.flutter.methodchannel.model.CallPayload

class CallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        CallwaveRuntime.ensureInitialized(context)
        val callId = intent.getStringExtra(CallwaveConstants.EXTRA_CALL_ID) ?: return
        val extraJson = intent.getStringExtra(CallwaveConstants.EXTRA_EXTRA)
        val extra = CallPayload.fromIntentExtras(extraJson)

        when (intent.action) {
            CallwaveConstants.ACTION_ACCEPT -> {
                val fallbackPayload = CallwaveRuntime.callManager.payloadFromActionIntent(
                    intent = intent,
                    callId = callId,
                    fallbackExtra = extra,
                )
                val accepted = CallwaveRuntime.callManager.onAccept(callId, extra, fallbackPayload)
                if (accepted) {
                    launchHostApp(context, intent)
                }
            }
            CallwaveConstants.ACTION_DECLINE -> CallwaveRuntime.callManager.onDecline(callId, extra)
            CallwaveConstants.ACTION_END -> CallwaveRuntime.callManager.endCall(callId)
            CallwaveConstants.ACTION_TIMEOUT -> CallwaveRuntime.callManager.onTimeout(callId)
            CallwaveConstants.ACTION_CALLBACK -> CallwaveRuntime.callManager.onCallback(callId, extra)
        }
    }

    private fun launchHostApp(context: Context, sourceIntent: Intent) {
        val launchIntent = CallwaveRuntime.callManager
            .hostLaunchIntentForAction(CallwaveConstants.ACTION_ACCEPT_AND_OPEN)
            ?: run {
                Log.w(TAG, "Unable to resolve host launch intent after call accept.")
                return
            }
        sourceIntent.extras?.let { extras ->
            launchIntent.putExtras(extras)
        }
        launchIntent.putExtra(
            CallwaveConstants.EXTRA_LAUNCH_ACTION,
            CallwaveConstants.ACTION_ACCEPT_AND_OPEN,
        )
        launchIntent.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP,
        )
        try {
            context.startActivity(launchIntent)
        } catch (error: Throwable) {
            Log.w(TAG, "Unable to launch host app after call accept.", error)
        }
    }

    companion object {
        private const val TAG = "CallwaveFlutter"
    }
}
