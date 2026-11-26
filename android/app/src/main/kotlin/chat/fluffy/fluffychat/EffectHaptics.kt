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
 * Plays the haptics of message effects for lib/utils/effect_haptics.dart,
 * which decides what each effect is felt as on this phone's vibrator.
 *
 * - `capabilities` answers what the vibrator can do: `primitives`, the
 *   composition primitives it plays with how long each lasts in
 *   milliseconds, and `amplitudeControl`.
 * - `compose` plays a list of `[primitive, scale, delayMs]` as one
 *   composition, each delay counted from the end of the primitive before.
 * - `waveform` plays `timings` (milliseconds) with `amplitudes` (0 to 255)
 *   one for one, or without them as off and on times in turn, off first.
 * - `predefined` plays `click`, `heavyClick` or `tick`.
 *
 * Each effect goes to the vibrator as one vibration, so its beats keep time
 * with the animation. The vibration is touch feedback, so it follows the
 * phone's touch feedback setting, and nothing plays while that is off. The
 * three that play answer whether anything was sent to the vibrator.
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

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "capabilities" -> result.success(capabilities())
            "compose" -> result.success(
                vibrate(composition((call.arguments as? List<*>).orEmpty())),
            )
            "waveform" -> {
                val timings = call.argument<List<Number>>("timings").orEmpty()
                val amplitudes = call.argument<List<Number>>("amplitudes")
                result.success(vibrate(waveform(timings, amplitudes)))
            }
            "predefined" -> result.success(vibrate(predefined(call.arguments as? String)))
            else -> result.notImplemented()
        }
    }

    private fun touchFeedbackOn(): Boolean =
        Settings.System.getInt(
            context.contentResolver,
            Settings.System.HAPTIC_FEEDBACK_ENABLED,
            1,
        ) != 0

    private fun capabilities(): Map<String, Any> {
        val vibrator = vibrator?.takeIf { it.hasVibrator() }
        val primitives = mutableMapOf<String, Int>()
        if (vibrator != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            for ((name, id) in PRIMITIVES) {
                if (vibrator.areAllPrimitivesSupported(id)) {
                    primitives[name] = vibrator.getPrimitiveDurations(id)[0]
                }
            }
        }
        return mapOf(
            "primitives" to primitives,
            "amplitudeControl" to
                (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    vibrator?.hasAmplitudeControl() == true),
        )
    }

    /** Sends [effect] to the vibrator as touch feedback; false when nothing was sent. */
    private fun vibrate(effect: VibrationEffect?): Boolean {
        val vibrator = vibrator ?: return false
        if (effect == null || !vibrator.hasVibrator() || !touchFeedbackOn()) return false
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
        } else {
            return false
        }
        return true
    }

    private fun composition(steps: List<*>): VibrationEffect? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || steps.isEmpty()) return null
        val composition = VibrationEffect.startComposition()
        for (step in steps) {
            val fields = step as? List<*> ?: return null
            val id = PRIMITIVES[fields.getOrNull(0) as? String] ?: return null
            val scale = ((fields.getOrNull(1) as? Number)?.toFloat() ?: 1f).coerceIn(0f, 1f)
            val delay = ((fields.getOrNull(2) as? Number)?.toInt() ?: 0).coerceAtLeast(0)
            composition.addPrimitive(id, scale, delay)
        }
        return composition.compose()
    }

    private fun waveform(timings: List<Number>, amplitudes: List<Number>?): VibrationEffect? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || timings.isEmpty()) return null
        val times = LongArray(timings.size) { timings[it].toLong().coerceAtLeast(0) }
        // A waveform must vibrate at some point.
        if (times.all { it == 0L }) return null
        if (amplitudes == null) return VibrationEffect.createWaveform(times, -1)
        if (amplitudes.size != times.size) return null
        val levels = IntArray(amplitudes.size) { amplitudes[it].toInt().coerceIn(0, 255) }
        if (levels.all { it == 0 }) return null
        return VibrationEffect.createWaveform(times, levels, -1)
    }

    private fun predefined(name: String?): VibrationEffect? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        return VibrationEffect.createPredefined(
            when (name) {
                "heavyClick" -> VibrationEffect.EFFECT_HEAVY_CLICK
                "tick" -> VibrationEffect.EFFECT_TICK
                "click" -> VibrationEffect.EFFECT_CLICK
                else -> return null
            },
        )
    }

    companion object {
        const val CHANNEL_NAME = "chat.fluffy.fluffychat/haptics"

        /** The composition primitives by the names the Dart side knows them by. */
        private val PRIMITIVES: Map<String, Int> =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                mapOf(
                    "thud" to VibrationEffect.Composition.PRIMITIVE_THUD,
                    "click" to VibrationEffect.Composition.PRIMITIVE_CLICK,
                    "tick" to VibrationEffect.Composition.PRIMITIVE_TICK,
                    "lowTick" to VibrationEffect.Composition.PRIMITIVE_LOW_TICK,
                    "quickRise" to VibrationEffect.Composition.PRIMITIVE_QUICK_RISE,
                    "slowRise" to VibrationEffect.Composition.PRIMITIVE_SLOW_RISE,
                    "quickFall" to VibrationEffect.Composition.PRIMITIVE_QUICK_FALL,
                    "spin" to VibrationEffect.Composition.PRIMITIVE_SPIN,
                )
            } else {
                emptyMap()
            }
    }
}
