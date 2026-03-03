package com.callwave.flutter.methodchannel

import android.app.Activity
import android.content.Context
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class CallwaveFlutterPlugin :
    FlutterPlugin,
    EventChannel.StreamHandler,
    ActivityAware,
    PluginRegistry.NewIntentListener {

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var methodHandler: CallwaveMethodHandler? = null
    private var activityBinding: ActivityPluginBinding? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        setup(binding.applicationContext, binding.binaryMessenger)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        CallwaveRuntime.callManager.activity = null
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
        activityBinding = binding
        binding.addOnNewIntentListener(this)
        bindActivity(binding.activity)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
        bindActivity(null)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addOnNewIntentListener(this)
        bindActivity(binding.activity)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
        bindActivity(null)
    }

    override fun onNewIntent(intent: Intent): Boolean {
        return CallwaveRuntime.callManager.handleIncomingCallIntent(intent)
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
        CallwaveRuntime.callManager.activity = activity
        CallwaveRuntime.callManager.handleIncomingCallIntent(activity?.intent)
    }
}
