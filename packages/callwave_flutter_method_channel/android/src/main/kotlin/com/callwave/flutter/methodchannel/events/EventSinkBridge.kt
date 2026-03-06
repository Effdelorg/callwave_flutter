package com.callwave.flutter.methodchannel.events

import com.callwave.flutter.methodchannel.model.CallEventPayload
import io.flutter.plugin.common.EventChannel

class EventSinkBridge(
    private val bufferStore: EventBufferStore,
) {
    @Volatile
    private var sink: EventChannel.EventSink? = null

    fun attach(eventSink: EventChannel.EventSink) {
        sink = eventSink
        flushBuffered()
    }

    fun detach() {
        sink = null
    }

    fun hasListener(): Boolean = sink != null

    fun emit(event: CallEventPayload) {
        val currentSink = sink
        if (currentSink == null) {
            bufferStore.enqueue(event)
            return
        }

        try {
            currentSink.success(event.toMap())
        } catch (_: Throwable) {
            bufferStore.enqueue(event)
        }
    }

    private fun flushBuffered() {
        val currentSink = sink ?: return
        val buffered = bufferStore.drain()
        for (event in buffered) {
            try {
                currentSink.success(event.toMap())
            } catch (_: Throwable) {
                bufferStore.enqueue(event)
                return
            }
        }
    }
}
