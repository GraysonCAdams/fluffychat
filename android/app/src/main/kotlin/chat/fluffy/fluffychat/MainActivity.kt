package chat.fluffy.fluffychat

import io.flutter.embedding.android.FlutterFragment
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor.DartEntrypoint
import io.flutter.plugin.common.MethodChannel

import android.content.Context
import android.content.Intent
import android.os.Bundle

class MainActivity : FlutterFragmentActivity() {

    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
    }


    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return provideEngine(getApplicationContext())
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        rememberShareTarget(intent)
        super.onCreate(savedInstanceState)
        EngineHandoff.holder = this
    }

    override fun onNewIntent(intent: Intent) {
        // Before super, which hands the share to receive_sharing_intent.
        rememberShareTarget(intent)
        super.onNewIntent(intent)
    }

    /** A Direct Share names the chosen conversation's shortcut, i.e. room ID. */
    private fun rememberShareTarget(intent: Intent?) {
        if (intent == null) return
        if (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE) return
        pendingShareRoomId = intent.getStringExtra(Intent.EXTRA_SHORTCUT_ID)
    }

    override fun onRestart() {
        super.onRestart()
        // A chat bubble took the shared engine; recreate to take it back.
        if (EngineHandoff.holder !== this) recreate()
    }

    override fun onResume() {
        super.onResume()
        engine?.let {
            MethodChannel(it.dartExecutor.binaryMessenger, BubbleActivity.CHANNEL_NAME)
                .invokeMethod("leaveBubble", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // do nothing, because the engine was been configured in provideEngine
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ConversationNotifications.CHANNEL_NAME,
        ).setMethodCallHandler(ConversationNotifications(this))
    }

    // Prevent Flutter engine gets destroyed on back button close.
    override fun createFlutterFragment(): FlutterFragment =
        super.createFlutterFragment().apply {
            arguments?.putBoolean("destroy_engine_with_fragment", false)
        }

    companion object {
        var engine: FlutterEngine? = null

        const val SHARE_CHANNEL_NAME = "chat.fluffy.fluffychat/share"

        /** The room a Direct Share picked, until Dart takes it. */
        var pendingShareRoomId: String? = null
        fun provideEngine(context: Context): FlutterEngine {
            engine?.let { return it }
            val eng = FlutterEngine(context, emptyArray(), true, false)
            engine = eng
            // Registered with the engine rather than an activity, so a bubble
            // started while the app is closed can hand Dart its room too.
            MethodChannel(eng.dartExecutor.binaryMessenger, BubbleActivity.CHANNEL_NAME)
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "takePendingRoom" -> {
                            result.success(BubbleActivity.pendingRoomId)
                            BubbleActivity.pendingRoomId = null
                        }
                        else -> result.notImplemented()
                    }
                }
            MethodChannel(eng.dartExecutor.binaryMessenger, SHARE_CHANNEL_NAME)
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "takeShareTargetRoom" -> {
                            result.success(pendingShareRoomId)
                            pendingShareRoomId = null
                        }
                        else -> result.notImplemented()
                    }
                }
            return eng
        }

        // Make push services run in the same engine.
        // https://codeberg.org/UnifiedPush/flutter-connector/src/branch/main/unifiedpush_android/android/src/main/kotlin/org/unifiedpush/flutter/connector/UnifiedPushService.kt#L17-L32
        fun provideRunningEngine(context: Context): FlutterEngine {
            var eng = engine
            if (eng == null) {
                eng = provideEngine(context)
                eng.getLocalizationPlugin().sendLocalesToFlutter(
                    context.getResources().getConfiguration())
                eng.getDartExecutor().executeDartEntrypoint(
                    DartEntrypoint.createDefault())
            }
            return eng
        }
    }
}
