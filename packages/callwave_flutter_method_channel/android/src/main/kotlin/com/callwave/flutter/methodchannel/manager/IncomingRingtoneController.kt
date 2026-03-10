package com.callwave.flutter.methodchannel.manager

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.util.Log

internal class IncomingRingtoneController(
    context: Context,
) {
    private val appContext = context.applicationContext
    private val lock = Any()
    private var activeCallId: String? = null
    private var player: MediaPlayer? = null
    private var playerGeneration = 0L

    fun start(callId: String) {
        val ringtoneUri = resolveRingtoneUri() ?: run {
            Log.w(TAG, "Unable to resolve system ringtone for incoming call $callId.")
            return
        }
        synchronized(lock) {
            if (activeCallId == callId && player != null) {
                return
            }
            stopLocked()
            val currentGeneration = ++playerGeneration
            val mediaPlayer = MediaPlayer()
            activeCallId = callId
            player = mediaPlayer
            try {
                mediaPlayer.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                mediaPlayer.isLooping = true
                mediaPlayer.setDataSource(appContext, ringtoneUri)
                mediaPlayer.setOnPreparedListener { preparedPlayer ->
                    synchronized(lock) {
                        val isCurrentPlayer = playerGeneration == currentGeneration &&
                            activeCallId == callId &&
                            player === preparedPlayer
                        if (!isCurrentPlayer) {
                            releasePlayer(preparedPlayer)
                            return@synchronized
                        }
                        try {
                            preparedPlayer.start()
                        } catch (error: Throwable) {
                            Log.w(TAG, "Failed to start incoming ringtone for $callId.", error)
                            stopLocked()
                        }
                    }
                }
                mediaPlayer.setOnErrorListener { erroredPlayer, what, extra ->
                    synchronized(lock) {
                        if (player === erroredPlayer) {
                            activeCallId = null
                            player = null
                            playerGeneration += 1
                        }
                        releasePlayer(erroredPlayer)
                    }
                    Log.w(
                        TAG,
                        "Incoming ringtone playback failed for $callId (what=$what, extra=$extra).",
                    )
                    true
                }
                mediaPlayer.prepareAsync()
            } catch (error: Throwable) {
                if (player === mediaPlayer) {
                    activeCallId = null
                    player = null
                    playerGeneration += 1
                }
                releasePlayer(mediaPlayer)
                Log.w(TAG, "Failed to prepare incoming ringtone for $callId.", error)
            }
        }
    }

    fun stop(callId: String) {
        synchronized(lock) {
            if (activeCallId != callId) {
                return
            }
            stopLocked()
        }
    }

    private fun stopLocked() {
        playerGeneration += 1
        activeCallId = null
        val currentPlayer = player
        player = null
        if (currentPlayer != null) {
            releasePlayer(currentPlayer)
        }
    }

    private fun resolveRingtoneUri(): Uri? {
        return RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
    }

    private fun releasePlayer(mediaPlayer: MediaPlayer) {
        try {
            mediaPlayer.setOnPreparedListener(null)
            mediaPlayer.setOnErrorListener(null)
            if (mediaPlayer.isPlaying) {
                mediaPlayer.stop()
            }
        } catch (_: Throwable) {
        } finally {
            try {
                mediaPlayer.reset()
            } catch (_: Throwable) {
            }
            mediaPlayer.release()
        }
    }

    private companion object {
        private const val TAG = "CallwaveFlutter"
    }
}
