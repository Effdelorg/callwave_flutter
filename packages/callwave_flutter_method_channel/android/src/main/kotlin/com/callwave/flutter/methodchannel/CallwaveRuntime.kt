package com.callwave.flutter.methodchannel

import android.content.Context
import com.callwave.flutter.methodchannel.events.EventBufferStore
import com.callwave.flutter.methodchannel.events.EventSinkBridge
import com.callwave.flutter.methodchannel.manager.ActiveCallRegistry
import com.callwave.flutter.methodchannel.manager.AndroidCallManager
import com.callwave.flutter.methodchannel.manager.CallNotificationManager
import com.callwave.flutter.methodchannel.manager.CallTimeoutScheduler

object CallwaveRuntime {
    @Volatile
    private var initialized = false

    lateinit var callManager: AndroidCallManager
        private set

    lateinit var eventSinkBridge: EventSinkBridge
        private set

    fun ensureInitialized(context: Context) {
        if (initialized) {
            return
        }
        synchronized(this) {
            if (initialized) {
                return
            }
            val appContext = context.applicationContext
            val bufferStore = EventBufferStore(appContext)
            eventSinkBridge = EventSinkBridge(bufferStore)
            val registry = ActiveCallRegistry()
            val notificationManager = CallNotificationManager(appContext)
            val timeoutScheduler = CallTimeoutScheduler(appContext)
            callManager = AndroidCallManager(
                context = appContext,
                notificationManager = notificationManager,
                timeoutScheduler = timeoutScheduler,
                activeCallRegistry = registry,
                eventSinkBridge = eventSinkBridge,
            )
            initialized = true
        }
    }
}
