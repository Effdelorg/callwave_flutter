package com.callwave.flutter.methodchannel.activity

import android.os.Bundle
import android.util.Log
import androidx.appcompat.app.AppCompatActivity
import com.callwave.flutter.methodchannel.CallwaveConstants
import com.callwave.flutter.methodchannel.CallwaveRuntime
import com.callwave.flutter.methodchannel.model.CallPayload

internal class DeclineReportBridgeActivity : AppCompatActivity() {
    private var declineStarted = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        declineStarted = savedInstanceState?.getBoolean(KEY_DECLINE_STARTED, false) == true
        Log.d(TAG, "DeclineReportBridgeActivity created.")
        overridePendingTransition(0, 0)
        startDeclineReportIfNeeded()
    }

    override fun onNewIntent(intent: android.content.Intent?) {
        super.onNewIntent(intent)
        setIntent(intent)
        startDeclineReportIfNeeded()
    }

    override fun finish() {
        super.finish()
        overridePendingTransition(0, 0)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean(KEY_DECLINE_STARTED, declineStarted)
        super.onSaveInstanceState(outState)
    }

    private fun startDeclineReportIfNeeded() {
        if (declineStarted) {
            return
        }
        declineStarted = true

        CallwaveRuntime.ensureInitialized(applicationContext)
        val callId = intent.getStringExtra(CallwaveConstants.EXTRA_CALL_ID)
            ?: return finishQuietly()
        Log.d(TAG, "DeclineReportBridgeActivity handling callId=$callId.")
        val extra = CallPayload.fromIntentExtras(
            intent.getStringExtra(CallwaveConstants.EXTRA_EXTRA),
        )
        val payload = CallwaveRuntime.callManager.payloadFromActionIntent(
            intent = intent,
            callId = callId,
            fallbackExtra = extra,
        ) ?: return finishQuietly()

        CallwaveRuntime.callManager.onDecline(
            callId = callId,
            extra = extra,
            fallbackPayload = payload,
            preferHeadlessReporting = true,
            requireBackgroundDeclineReport = true,
            onBackgroundDeclineResolved = ::finishQuietly,
        )
    }

    private fun finishQuietly() {
        runOnUiThread {
            if (isFinishing || isDestroyed) {
                return@runOnUiThread
            }
            Log.d(TAG, "DeclineReportBridgeActivity finishing.")
            finish()
        }
    }

    companion object {
        private const val TAG = "CallwaveFlutter"
        private const val KEY_DECLINE_STARTED = "declineStarted"
    }
}
