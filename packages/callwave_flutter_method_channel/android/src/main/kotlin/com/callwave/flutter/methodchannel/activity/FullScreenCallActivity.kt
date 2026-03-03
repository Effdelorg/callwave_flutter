package com.callwave.flutter.methodchannel.activity

import android.content.Intent
import android.os.Build
import android.os.Bundle
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
        val extra = intent.getStringExtra(CallwaveConstants.EXTRA_EXTRA)

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
                sendAction(
                    action = CallwaveConstants.ACTION_ACCEPT,
                    callId = callId,
                    callerName = callerName,
                    handle = handle,
                    avatarUrl = avatarUrl,
                    timeoutSeconds = timeoutSeconds,
                    callType = callType,
                    extra = extra,
                )
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
                    extra = extra,
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
        extra: String?,
    ) {
        val intent = Intent(this, CallActionReceiver::class.java).apply {
            this.action = action
            putExtra(CallwaveConstants.EXTRA_CALL_ID, callId)
            putExtra(CallwaveConstants.EXTRA_CALLER_NAME, callerName)
            putExtra(CallwaveConstants.EXTRA_HANDLE, handle)
            putExtra(CallwaveConstants.EXTRA_AVATAR_URL, avatarUrl)
            putExtra(CallwaveConstants.EXTRA_TIMEOUT_SECONDS, timeoutSeconds)
            putExtra(CallwaveConstants.EXTRA_CALL_TYPE, callType)
            putExtra(CallwaveConstants.EXTRA_EXTRA, extra)
        }
        sendBroadcast(intent)
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
}
