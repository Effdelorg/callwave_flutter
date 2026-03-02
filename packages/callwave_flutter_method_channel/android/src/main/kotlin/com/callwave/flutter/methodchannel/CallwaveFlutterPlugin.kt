package com.callwave.flutter.methodchannel

import android.app.Activity
import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class CallwaveFlutterPlugin :
    FlutterPlugin,
    EventChannel.StreamHandler,
    ActivityAware {

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var methodHandler: CallwaveMethodHandler? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        setup(binding.applicationContext, binding.binaryMessenger)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        methodHandler = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        CallwaveRuntime.eventSinkBridge.attach(events)
    }

    override fun onCancel(arguments: Any?) {
        CallwaveRuntime.eventSinkBridge.detach()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        bindActivity(binding.activity)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        bindActivity(null)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        bindActivity(binding.activity)
    }

    override fun onDetachedFromActivity() {
        bindActivity(null)
    }

    private fun setup(context: Context, messenger: io.flutter.plugin.common.BinaryMessenger) {
        CallwaveRuntime.ensureInitialized(context)
        methodHandler = CallwaveMethodHandler(CallwaveRuntime.callManager)

        methodChannel = MethodChannel(messenger, CallwaveConstants.METHOD_CHANNEL).also {
            it.setMethodCallHandler(methodHandler)
        }

        eventChannel = EventChannel(messenger, CallwaveConstants.EVENT_CHANNEL).also {
            it.setStreamHandler(this)
        }
    }

    private fun bindActivity(activity: Activity?) {
        methodHandler?.activity = activity
    }
}
