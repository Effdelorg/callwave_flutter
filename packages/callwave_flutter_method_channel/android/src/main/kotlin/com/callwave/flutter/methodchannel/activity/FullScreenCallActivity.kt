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
                sendAction(CallwaveConstants.ACTION_ACCEPT, callId, extra)
                finish()
            }
        }

        val decline = Button(this).apply {
            text = "Decline"
            setOnClickListener {
                sendAction(CallwaveConstants.ACTION_DECLINE, callId, extra)
                finish()
            }
        }

        root.addView(title)
        root.addView(accept)
        root.addView(decline)
        setContentView(root)
    }

    private fun sendAction(action: String, callId: String, extra: String?) {
        val intent = Intent(this, CallActionReceiver::class.java).apply {
            this.action = action
            putExtra(CallwaveConstants.EXTRA_CALL_ID, callId)
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
