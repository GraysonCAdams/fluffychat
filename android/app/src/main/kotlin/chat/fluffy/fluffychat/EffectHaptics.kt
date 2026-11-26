// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

package chat.fluffy.fluffychat

import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Plays the haptics of message effects for lib/utils/effect_haptics.dart.
 *
 * `play` takes a pattern, a list of `[primitive, atMs, scale]`, and sends it
 * to the vibrator as one vibration so its beats keep time with the effect's
 * animation. A vibrator that supports every primitive in it plays it as a
 * composition of those primitives. Any other plays plainer haptics: a single
 * beat at the start is the predefined click, heavy click or tick nearest
 * it, anything else a waveform of short pulses, their strength standing in
 * for the primitives when the vibrator can vary its amplitude. The vibration is touch feedback, so it follows the phone's
 * touch feedback setting, and nothing plays while that is off. It answers
 * how the pattern was played: "composition", "predefined", "waveform" or
 * "none".
 */
class EffectHaptics(private val context: Context) : MethodChannel.MethodCallHandler {

    private val vibrator: Vibrator? by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    private class Beat(val primitive: String, val atMs: Long, val scale: Float)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "play" -> {
                val beats = (call.arguments as? List<*>).orEmpty().mapNotNull { item ->
                    val fields = item as? List<*> ?: return@mapNotNull null
                    Beat(
                        fields.getOrNull(0) as? String ?: return@mapNotNull null,
                        (fields.getOrNull(1) as? Number)?.toLong() ?: return@mapNotNull null,
                        ((fields.getOrNull(2) as? Number)?.toFloat() ?: 1f).coerceIn(0f, 1f),
                    )
                }.sortedBy { it.atMs }
                result.success(play(beats))
            }
            else -> result.notImplemented()
        }
    }

    private fun touchFeedbackOn(): Boolean =
        Settings.System.getInt(
            context.contentResolver,
            Settings.System.HAPTIC_FEEDBACK_ENABLED,
            1,
        ) != 0

    private fun play(beats: List<Beat>): String {
        val vibrator = vibrator ?: return "none"
        if (beats.isEmpty() || !vibrator.hasVibrator() || !touchFeedbackOn()) return "none"
        composition(vibrator, beats)?.let {
            vibrate(vibrator, it)
            return "composition"
        }
        predefined(beats)?.let {
            vibrate(vibrator, it)
            return "predefined"
        }
        vibrate(vibrator, waveform(vibrator, beats))
        return "waveform"
    }

    /** A lone beat at the start as the predefined effect nearest it. */
    private fun predefined(beats: List<Beat>): VibrationEffect? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val beat = beats.singleOrNull()?.takeIf { it.atMs == 0L } ?: return null
        return VibrationEffect.createPredefined(
            when (beat.primitive) {
                "thud" -> VibrationEffect.EFFECT_HEAVY_CLICK
                "tick", "lowTick" -> VibrationEffect.EFFECT_TICK
                else -> VibrationEffect.EFFECT_CLICK
            },
        )
    }

    private fun vibrate(vibrator: Vibrator, effect: VibrationEffect?) {
        if (effect == null) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            vibrator.vibrate(
                effect,
                VibrationAttributes.createForUsage(VibrationAttributes.USAGE_TOUCH),
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Sonification is what these versions treat as touch feedback.
            vibrator.vibrate(
                effect,
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
        }
    }

    /** The pattern as primitives, or null when the vibrator lacks any of them. */
    private fun composition(vibrator: Vibrator, beats: List<Beat>): VibrationEffect? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        val ids = beats.map { primitiveId(it.primitive) ?: return null }
        val distinct = ids.distinct().toIntArray()
        if (!vibrator.areAllPrimitivesSupported(*distinct)) return null
        val durations = distinct.zip(vibrator.getPrimitiveDurations(*distinct).toList()).toMap()
        val composition = VibrationEffect.startComposition()
        // A primitive's delay counts from the end of the one before it.
        var cursor = 0L
        for ((beat, id) in beats.zip(ids)) {
            val delay = (beat.atMs - cursor).coerceAtLeast(0)
            composition.addPrimitive(id, beat.scale, delay.toInt())
            cursor += delay + (durations[id] ?: 0)
        }
        return composition.compose()
    }

    private fun primitiveId(name: String): Int? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        return when (name) {
            "thud" -> VibrationEffect.Composition.PRIMITIVE_THUD
            "click" -> VibrationEffect.Composition.PRIMITIVE_CLICK
            "tick" -> VibrationEffect.Composition.PRIMITIVE_TICK
            "lowTick" -> VibrationEffect.Composition.PRIMITIVE_LOW_TICK
            "quickRise" -> VibrationEffect.Composition.PRIMITIVE_QUICK_RISE
            "slowRise" -> VibrationEffect.Composition.PRIMITIVE_SLOW_RISE
            "spin" -> VibrationEffect.Composition.PRIMITIVE_SPIN
            else -> null
        }
    }

    /** A pulse standing in for a primitive: how long, and how strong at full scale. */
    private fun pulseOf(name: String): Pair<Long, Int> = when (name) {
        "thud" -> 40L to 255
        "click" -> 20L to 200
        "quickRise" -> 50L to 170
        "slowRise" -> 90L to 130
        "spin" -> 40L to 150
        "lowTick" -> 14L to 90
        else -> 10L to 110
    }

    /** The pattern as pulses, the plainer haptics every vibrator can play. */
    private fun waveform(vibrator: Vibrator, beats: List<Beat>): VibrationEffect? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        val timings = mutableListOf<Long>()
        val amplitudes = mutableListOf<Int>()
        var cursor = 0L
        for (beat in beats) {
            val (length, strength) = pulseOf(beat.primitive)
            val gap = (beat.atMs - cursor).coerceAtLeast(0)
            timings += gap
            amplitudes += 0
            timings += length
            amplitudes += (strength * beat.scale).toInt().coerceIn(1, 255)
            cursor += gap + length
        }
        return if (vibrator.hasAmplitudeControl()) {
            VibrationEffect.createWaveform(timings.toLongArray(), amplitudes.toIntArray(), -1)
        } else {
            VibrationEffect.createWaveform(timings.toLongArray(), -1)
        }
    }

    companion object {
        const val CHANNEL_NAME = "chat.fluffy.fluffychat/haptics"
    }
}
