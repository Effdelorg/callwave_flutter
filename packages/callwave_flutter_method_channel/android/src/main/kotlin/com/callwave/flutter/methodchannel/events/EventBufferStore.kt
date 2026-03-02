package com.callwave.flutter.methodchannel.events

import android.content.Context
import com.callwave.flutter.methodchannel.model.CallEventPayload
import org.json.JSONArray

class EventBufferStore(context: Context) {
    private val sharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val memoryQueue = ArrayDeque<CallEventPayload>()

    @Synchronized
    fun enqueue(event: CallEventPayload) {
        loadPersistedIfNeeded()
        pruneLocked()

        if (memoryQueue.any { it.dedupeKey() == event.dedupeKey() }) {
            return
        }

        memoryQueue.addLast(event)
        if (memoryQueue.size > MAX_EVENTS) {
            memoryQueue.removeFirst()
        }
        persistLocked()
    }

    @Synchronized
    fun drain(): List<CallEventPayload> {
        loadPersistedIfNeeded()
        pruneLocked()
        val drained = memoryQueue.toList()
        memoryQueue.clear()
        persistLocked()
        return drained
    }

    @Synchronized
    private fun loadPersistedIfNeeded() {
        if (memoryQueue.isNotEmpty()) {
            return
        }

        val raw = sharedPreferences.getString(KEY_EVENTS, null) ?: return
        val list = mutableListOf<CallEventPayload>()
        try {
            val array = JSONArray(raw)
            for (index in 0 until array.length()) {
                val payload = CallEventPayload.fromJson(array.getJSONObject(index))
                if (payload != null) {
                    list.add(payload)
                }
            }
        } catch (_: Throwable) {
            sharedPreferences.edit().remove(KEY_EVENTS).apply()
        }
        memoryQueue.addAll(list)
    }

    @Synchronized
    private fun pruneLocked() {
        val minTimestamp = System.currentTimeMillis() - MAX_AGE_MS
        while (memoryQueue.isNotEmpty() && memoryQueue.first().timestampMs < minTimestamp) {
            memoryQueue.removeFirst()
        }

        val seen = HashSet<String>()
        val deduped = ArrayDeque<CallEventPayload>()
        for (event in memoryQueue) {
            val key = event.dedupeKey()
            if (seen.add(key)) {
                deduped.addLast(event)
            }
        }

        memoryQueue.clear()
        memoryQueue.addAll(deduped.takeLast(MAX_EVENTS))
    }

    @Synchronized
    private fun persistLocked() {
        if (memoryQueue.isEmpty()) {
            sharedPreferences.edit().remove(KEY_EVENTS).apply()
            return
        }

        val array = JSONArray()
        for (event in memoryQueue) {
            array.put(event.toJson())
        }
        sharedPreferences.edit().putString(KEY_EVENTS, array.toString()).apply()
    }

    companion object {
        private const val PREFS_NAME = "callwave_flutter_events"
        private const val KEY_EVENTS = "buffered_events"
        private const val MAX_EVENTS = 50
        private const val MAX_AGE_MS = 10L * 60L * 1000L
    }
}
