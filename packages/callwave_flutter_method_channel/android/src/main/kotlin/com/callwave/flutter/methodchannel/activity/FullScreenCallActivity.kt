package com.callwave.flutter.methodchannel.activity

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.callwave.flutter.methodchannel.CallwaveConstants
import com.callwave.flutter.methodchannel.receiver.CallActionReceiver

class FullScreenCallActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyLockScreenFlags()

        val callId = intent.getStringExtra(CallwaveConstants.EXTRA_CALL_ID) ?: return finish()
        val callerName = intent.getStringExtra(CallwaveConstants.EXTRA_CALLER_NAME) ?: "Incoming call"
        val handle = intent.getStringExtra(CallwaveConstants.EXTRA_HANDLE) ?: ""
        val avatarUrl = intent.getStringExtra(CallwaveConstants.EXTRA_AVATAR_URL)
        val timeoutSeconds = intent.getIntExtra(CallwaveConstants.EXTRA_TIMEOUT_SECONDS, 30)
        val callType = intent.getStringExtra(CallwaveConstants.EXTRA_CALL_TYPE) ?: "audio"
        val incomingAcceptStrategy = intent.getStringExtra(
            CallwaveConstants.EXTRA_INCOMING_ACCEPT_STRATEGY,
        )
        val extra = intent.getStringExtra(CallwaveConstants.EXTRA_EXTRA)
        val backgroundDispatcherHandle =
            intent.takeIf {
                it.hasExtra(CallwaveConstants.EXTRA_BACKGROUND_DISPATCHER_HANDLE)
            }?.getLongExtra(CallwaveConstants.EXTRA_BACKGROUND_DISPATCHER_HANDLE, 0L)
                ?.takeIf { it > 0L }
        val backgroundCallbackHandle =
            intent.takeIf {
                it.hasExtra(CallwaveConstants.EXTRA_BACKGROUND_CALLBACK_HANDLE)
            }?.getLongExtra(CallwaveConstants.EXTRA_BACKGROUND_CALLBACK_HANDLE, 0L)
                ?.takeIf { it > 0L }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(48, 48, 48, 48)
        }

        val title = TextView(this).apply {
            text = callerName
            textSize = 28f
            gravity = Gravity.CENTER
        }

        val accept = Button(this).apply {
            text = "Accept"
            setOnClickListener {
                if (incomingAcceptStrategy ==
                    CallwaveConstants.INCOMING_ACCEPT_STRATEGY_DEFER_OPEN_UNTIL_CONFIRMED
                ) {
                    Log.d(TAG, "FullScreenCallActivity launching validated bridge for $callId.")
                    launchValidatedAcceptBridge(
                        callId = callId,
                        callerName = callerName,
                        handle = handle,
                        avatarUrl = avatarUrl,
                        timeoutSeconds = timeoutSeconds,
                        callType = callType,
                        incomingAcceptStrategy = incomingAcceptStrategy,
                        extra = extra,
                        backgroundDispatcherHandle = backgroundDispatcherHandle,
                        backgroundCallbackHandle = backgroundCallbackHandle,
                    )
                } else {
                    sendAction(
                        action = CallwaveConstants.ACTION_ACCEPT,
                        callId = callId,
                        callerName = callerName,
                        handle = handle,
                        avatarUrl = avatarUrl,
                        timeoutSeconds = timeoutSeconds,
                        callType = callType,
                        incomingAcceptStrategy = incomingAcceptStrategy,
                        extra = extra,
                        backgroundDispatcherHandle = backgroundDispatcherHandle,
                        backgroundCallbackHandle = backgroundCallbackHandle,
                    )
                }
                finish()
            }
        }

        val decline = Button(this).apply {
            text = "Decline"
            setOnClickListener {
                sendAction(
                    action = CallwaveConstants.ACTION_DECLINE,
                    callId = callId,
                    callerName = callerName,
                    handle = handle,
                    avatarUrl = avatarUrl,
                    timeoutSeconds = timeoutSeconds,
                    callType = callType,
                    incomingAcceptStrategy = incomingAcceptStrategy,
                    extra = extra,
                    backgroundDispatcherHandle = backgroundDispatcherHandle,
                    backgroundCallbackHandle = backgroundCallbackHandle,
                )
                finish()
            }
        }

        root.addView(title)
        root.addView(accept)
        root.addView(decline)
        setContentView(root)
    }

    private fun sendAction(
        action: String,
        callId: String,
        callerName: String,
        handle: String,
        avatarUrl: String?,
        timeoutSeconds: Int,
        callType: String,
        incomingAcceptStrategy: String?,
        extra: String?,
        backgroundDispatcherHandle: Long?,
        backgroundCallbackHandle: Long?,
    ) {
        val intent = Intent(this, CallActionReceiver::class.java).apply {
            this.action = action
            putExtra(CallwaveConstants.EXTRA_CALL_ID, callId)
            putExtra(CallwaveConstants.EXTRA_CALLER_NAME, callerName)
            putExtra(CallwaveConstants.EXTRA_HANDLE, handle)
            putExtra(CallwaveConstants.EXTRA_AVATAR_URL, avatarUrl)
            putExtra(CallwaveConstants.EXTRA_TIMEOUT_SECONDS, timeoutSeconds)
            putExtra(CallwaveConstants.EXTRA_CALL_TYPE, callType)
            putExtra(
                CallwaveConstants.EXTRA_INCOMING_ACCEPT_STRATEGY,
                incomingAcceptStrategy,
            )
            putExtra(CallwaveConstants.EXTRA_EXTRA, extra)
            putExtra(
                CallwaveConstants.EXTRA_BACKGROUND_DISPATCHER_HANDLE,
                backgroundDispatcherHandle,
            )
            putExtra(
                CallwaveConstants.EXTRA_BACKGROUND_CALLBACK_HANDLE,
                backgroundCallbackHandle,
            )
        }
        sendBroadcast(intent)
    }

    private fun launchValidatedAcceptBridge(
        callId: String,
        callerName: String,
        handle: String,
        avatarUrl: String?,
        timeoutSeconds: Int,
        callType: String,
        incomingAcceptStrategy: String?,
        extra: String?,
        backgroundDispatcherHandle: Long?,
        backgroundCallbackHandle: Long?,
    ) {
        val intent = Intent(this, ValidatedAcceptBridgeActivity::class.java).apply {
            putExtra(CallwaveConstants.EXTRA_LAUNCH_ACTION, CallwaveConstants.ACTION_ACCEPT)
            putExtra(CallwaveConstants.EXTRA_CALL_ID, callId)
            putExtra(CallwaveConstants.EXTRA_CALLER_NAME, callerName)
            putExtra(CallwaveConstants.EXTRA_HANDLE, handle)
            putExtra(CallwaveConstants.EXTRA_AVATAR_URL, avatarUrl)
            putExtra(CallwaveConstants.EXTRA_TIMEOUT_SECONDS, timeoutSeconds)
            putExtra(CallwaveConstants.EXTRA_CALL_TYPE, callType)
            putExtra(
                CallwaveConstants.EXTRA_INCOMING_ACCEPT_STRATEGY,
                incomingAcceptStrategy,
            )
            putExtra(CallwaveConstants.EXTRA_EXTRA, extra)
            putExtra(
                CallwaveConstants.EXTRA_BACKGROUND_DISPATCHER_HANDLE,
                backgroundDispatcherHandle,
            )
            putExtra(
                CallwaveConstants.EXTRA_BACKGROUND_CALLBACK_HANDLE,
                backgroundCallbackHandle,
            )
            addFlags(
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_NO_ANIMATION,
            )
        }
        startActivity(intent)
    }

    private fun applyLockScreenFlags() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON,
            )
        }
    }

    companion object {
        private const val TAG = "CallwaveFlutter"
    }
}
