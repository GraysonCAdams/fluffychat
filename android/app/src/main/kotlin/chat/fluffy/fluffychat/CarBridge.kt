// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

package chat.fluffy.fluffychat

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * The Android Auto screens' line to the Dart side, which owns the Matrix
 * clients (lib/utils/car_app_bridge.dart).
 *
 * It runs on the app's single shared Flutter engine, started headless when
 * the app is not open, the same way a push starts it. Dart registers its
 * handler once the clients are loaded; a call that arrives earlier comes back
 * as not implemented and is retried every half second for up to 20 seconds.
 * Dart calls `changed` here when a conversation changed while a car session
 * listens, and `ready` once its handler is registered.
 */
object CarBridge {
    const val CHANNEL_NAME = "chat.fluffy.fluffychat/car"

    private const val RETRY_MS = 500L
    private const val RETRY_LIMIT = 40

    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private val listeners = mutableSetOf<() -> Unit>()

    private fun channel(context: Context): MethodChannel {
        channel?.let { return it }
        val engine = MainActivity.provideRunningEngine(context.applicationContext)
        return MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "changed", "ready" -> {
                        listeners.toList().forEach { listener -> listener() }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
            channel = it
        }
    }

    /** [listener] runs on the main thread whenever Dart reports a change. */
    fun addListener(listener: () -> Unit) {
        listeners.add(listener)
    }

    fun removeListener(listener: () -> Unit) {
        listeners.remove(listener)
    }

    /**
     * Calls [method] on the Dart side. [onResult] gets the answer, or null
     * after an error or once Dart never registered within the retry window.
     */
    fun call(
        context: Context,
        method: String,
        arguments: Any? = null,
        onResult: (Any?) -> Unit = {},
    ) = callWithRetry(context, method, arguments, onResult, 0)

    private fun callWithRetry(
        context: Context,
        method: String,
        arguments: Any?,
        onResult: (Any?) -> Unit,
        attempt: Int,
    ) {
        channel(context).invokeMethod(method, arguments, object : MethodChannel.Result {
            override fun success(result: Any?) = onResult(result)

            override fun error(code: String, message: String?, details: Any?) {
                android.util.Log.w("CarBridge", "$method failed: $code $message")
                onResult(null)
            }

            override fun notImplemented() {
                if (attempt >= RETRY_LIMIT) {
                    android.util.Log.w("CarBridge", "$method: Dart side never registered")
                    onResult(null)
                    return
                }
                main.postDelayed(
                    { callWithRetry(context, method, arguments, onResult, attempt + 1) },
                    RETRY_MS,
                )
            }
        })
    }
}
