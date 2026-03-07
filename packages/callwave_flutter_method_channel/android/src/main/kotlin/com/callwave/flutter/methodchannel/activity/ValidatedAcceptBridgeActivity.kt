package com.callwave.flutter.methodchannel.activity

import android.os.Bundle
import android.util.Log
import androidx.appcompat.app.AppCompatActivity
import com.callwave.flutter.methodchannel.CallwaveConstants
import com.callwave.flutter.methodchannel.CallwaveRuntime
import com.callwave.flutter.methodchannel.manager.AcceptResult
import com.callwave.flutter.methodchannel.model.CallPayload

internal class ValidatedAcceptBridgeActivity : AppCompatActivity() {
    private var acceptStarted = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "ValidatedAcceptBridgeActivity created.")
        overridePendingTransition(0, 0)
        startValidatedAcceptIfNeeded()
    }

    override fun onNewIntent(intent: android.content.Intent?) {
        super.onNewIntent(intent)
        setIntent(intent)
        startValidatedAcceptIfNeeded()
    }

    override fun finish() {
        super.finish()
        overridePendingTransition(0, 0)
    }

    private fun startValidatedAcceptIfNeeded() {
        if (acceptStarted) {
            return
        }
        acceptStarted = true

        CallwaveRuntime.ensureInitialized(applicationContext)
        val callId = intent.getStringExtra(CallwaveConstants.EXTRA_CALL_ID)
            ?: return finishQuietly()
        Log.d(TAG, "ValidatedAcceptBridgeActivity handling callId=$callId.")
        val extra = CallPayload.fromIntentExtras(
            intent.getStringExtra(CallwaveConstants.EXTRA_EXTRA),
        )
        val payload = CallwaveRuntime.callManager.payloadFromActionIntent(
            intent = intent,
            callId = callId,
            fallbackExtra = extra,
        ) ?: return finishQuietly()

        val acceptResult = CallwaveRuntime.callManager.onAccept(
            callId = callId,
            extra = extra,
            fallbackPayload = payload,
            shouldOpenAfterConfirm = true,
            requireBackgroundValidationForValidatedAccept = true,
            onBackgroundValidationResolved = ::finishQuietly,
        )
        Log.d(TAG, "ValidatedAcceptBridgeActivity onAccept result=$acceptResult for $callId.")
        when (acceptResult) {
            AcceptResult.LAUNCH_NOW -> {
                CallwaveRuntime.callManager.launchHostApp(
                    CallwaveConstants.ACTION_ACCEPT_AND_OPEN,
                    payload,
                )
                finishQuietly()
            }
            AcceptResult.HANDLED,
            AcceptResult.IGNORED -> finishQuietly()
            AcceptResult.VALIDATION_PENDING -> return
        }
    }

    private fun finishQuietly() {
        runOnUiThread {
            if (isFinishing || isDestroyed) {
                return@runOnUiThread
            }
            Log.d(TAG, "ValidatedAcceptBridgeActivity finishing.")
            finish()
        }
    }

    companion object {
        private const val TAG = "CallwaveFlutter"
    }
}
