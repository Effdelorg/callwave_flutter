package com.callwave.flutter.methodchannel.manager

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.callwave.flutter.methodchannel.CallwaveConstants
import com.callwave.flutter.methodchannel.model.CallPayload
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.loader.FlutterLoader
import io.flutter.view.FlutterCallbackInformation
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal class AndroidBackgroundValidator(
    private val context: Context,
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val flutterLoader = FlutterLoader()
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var activeDispatcherHandle: Long? = null
    private var dispatcherReady = false
    private val pendingValidations = ArrayDeque<PendingValidation>()

    fun validate(
        backgroundDispatcherHandle: Long,
        backgroundCallbackHandle: Long,
        payload: CallPayload,
        onComplete: (BackgroundValidationResult) -> Unit,
    ) {
        val started = ensureEngine(backgroundDispatcherHandle)
        if (!started) {
            Log.d(TAG, "Background validator engine failed to start for ${payload.callId}.")
            onComplete(
                BackgroundValidationResult(
                    isAllowed = false,
                    reason = "failed",
                    extra = null,
                ),
            )
            return
        }

        val completion = ValidationCompletion(onComplete)
        val timeoutRunnable = Runnable {
            removePendingValidation(payload.callId)
            completion.complete(
                BackgroundValidationResult(
                    isAllowed = false,
                    reason = "failed",
                    extra = null,
                ),
            )
        }
        mainHandler.postDelayed(timeoutRunnable, VALIDATION_TIMEOUT_MS)

        val iterator = pendingValidations.iterator()
        while (iterator.hasNext()) {
            val pending = iterator.next()
            if (pending.payload.callId == payload.callId) {
                mainHandler.removeCallbacks(pending.timeoutRunnable)
                iterator.remove()
            }
        }
        pendingValidations.addLast(
            PendingValidation(
                backgroundCallbackHandle = backgroundCallbackHandle,
                payload = payload,
                completion = completion,
                timeoutRunnable = timeoutRunnable,
            ),
        )
        flushPendingValidations()
    }

    private fun ensureEngine(backgroundDispatcherHandle: Long): Boolean {
        if (engine != null && activeDispatcherHandle == backgroundDispatcherHandle) {
            return true
        }

        flutterLoader.startInitialization(context)
        flutterLoader.ensureInitializationComplete(context, emptyArray())
        val callbackInfo = FlutterCallbackInformation.lookupCallbackInformation(
            backgroundDispatcherHandle,
        ) ?: return false

        engine?.destroy()
        val flutterEngine = FlutterEngine(context)
        registerGeneratedPlugins(flutterEngine)
        val backgroundChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CallwaveConstants.BACKGROUND_CHANNEL,
        )
        backgroundChannel.setMethodCallHandler(::onMethodCall)

        val dartCallback = DartExecutor.DartCallback(
            context.assets,
            flutterLoader.findAppBundlePath(),
            callbackInfo,
        )
        flutterEngine.dartExecutor.executeDartCallback(dartCallback)

        engine = flutterEngine
        channel = backgroundChannel
        activeDispatcherHandle = backgroundDispatcherHandle
        dispatcherReady = false
        return true
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            CallwaveConstants.METHOD_BACKGROUND_DISPATCHER_READY -> {
                Log.d(TAG, "Background validator dispatcher is ready.")
                dispatcherReady = true
                result.success(null)
                flushPendingValidations()
            }
            else -> result.notImplemented()
        }
    }

    private fun flushPendingValidations() {
        if (!dispatcherReady) {
            return
        }
        val currentChannel = channel ?: return
        while (pendingValidations.isNotEmpty()) {
            val pending = pendingValidations.removeFirst()
            Log.d(TAG, "Dispatching background validation for ${pending.payload.callId}.")
            currentChannel.invokeMethod(
                CallwaveConstants.METHOD_VALIDATE_BACKGROUND_INCOMING_CALL,
                mapOf(
                    CallwaveConstants.EXTRA_BACKGROUND_CALLBACK_HANDLE to
                        pending.backgroundCallbackHandle,
                    CallwaveConstants.EXTRA_CALL_DATA to pending.payload.toMethodArgs(),
                ),
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        mainHandler.removeCallbacks(pending.timeoutRunnable)
                        Log.d(TAG, "Background validation success for ${pending.payload.callId}.")
                        val map = result as? Map<*, *>
                        pending.completion.complete(
                            BackgroundValidationResult(
                                isAllowed = map?.get("isAllowed") as? Boolean ?: false,
                                reason = map?.get("reason") as? String,
                                extra = (map?.get("extra") as? Map<*, *>)
                                    ?.entries
                                    ?.associate { it.key.toString() to it.value },
                            ),
                        )
                    }

                    override fun error(
                        errorCode: String,
                        errorMessage: String?,
                        errorDetails: Any?,
                    ) {
                        mainHandler.removeCallbacks(pending.timeoutRunnable)
                        Log.w(
                            TAG,
                            "Background validation error for ${pending.payload.callId}: $errorCode $errorMessage",
                        )
                        pending.completion.complete(
                            BackgroundValidationResult(
                                isAllowed = false,
                                reason = "failed",
                                extra = null,
                            ),
                        )
                    }

                    override fun notImplemented() {
                        mainHandler.removeCallbacks(pending.timeoutRunnable)
                        Log.w(
                            TAG,
                            "Background validation not implemented for ${pending.payload.callId}.",
                        )
                        pending.completion.complete(
                            BackgroundValidationResult(
                                isAllowed = false,
                                reason = "failed",
                                extra = null,
                            ),
                        )
                    }
                },
            )
        }
    }

    private fun removePendingValidation(callId: String) {
        val iterator = pendingValidations.iterator()
        while (iterator.hasNext()) {
            val pending = iterator.next()
            if (pending.payload.callId == callId) {
                iterator.remove()
                return
            }
        }
    }

    private fun registerGeneratedPlugins(flutterEngine: FlutterEngine) {
        try {
            val registrant = Class.forName("io.flutter.plugins.GeneratedPluginRegistrant")
            val registerWith = registrant.getDeclaredMethod("registerWith", FlutterEngine::class.java)
            registerWith.invoke(null, flutterEngine)
        } catch (error: Throwable) {
            Log.w(
                TAG,
                "Unable to register generated plugins for background validator engine.",
                error,
            )
        }
    }

    internal data class BackgroundValidationResult(
        val isAllowed: Boolean,
        val reason: String?,
        val extra: Map<String, Any?>?,
    )

    private data class PendingValidation(
        val backgroundCallbackHandle: Long,
        val payload: CallPayload,
        val completion: ValidationCompletion,
        val timeoutRunnable: Runnable,
    )

    private class ValidationCompletion(
        private val onComplete: (BackgroundValidationResult) -> Unit,
    ) {
        @Volatile
        private var completed = false

        fun complete(result: BackgroundValidationResult) {
            if (completed) {
                return
            }
            synchronized(this) {
                if (completed) {
                    return
                }
                completed = true
            }
            onComplete(result)
        }
    }

    companion object {
        private const val TAG = "CallwaveFlutter"
        private const val VALIDATION_TIMEOUT_MS = 8_000L
    }
}
