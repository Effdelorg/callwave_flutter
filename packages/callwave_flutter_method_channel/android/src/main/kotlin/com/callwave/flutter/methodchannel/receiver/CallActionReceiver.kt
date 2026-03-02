package com.callwave.flutter.methodchannel.receiver

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
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
            CallwaveConstants.ACTION_ACCEPT -> CallwaveRuntime.callManager.onAccept(callId, extra)
            CallwaveConstants.ACTION_DECLINE -> CallwaveRuntime.callManager.onDecline(callId, extra)
            CallwaveConstants.ACTION_TIMEOUT -> CallwaveRuntime.callManager.onTimeout(callId)
            CallwaveConstants.ACTION_CALLBACK -> CallwaveRuntime.callManager.onCallback(callId, extra)
        }
    }
}
