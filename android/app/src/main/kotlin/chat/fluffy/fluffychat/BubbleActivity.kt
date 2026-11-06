// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

package chat.fluffy.fluffychat

import android.app.Activity
import android.content.Context
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragment
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Shows one conversation inside an Android chat bubble.
 *
 * It runs on the app's single shared Flutter engine, so the bubble and the
 * main window share one Matrix client and database. An engine can only be
 * attached to one activity at a time, so whichever activity comes back to the
 * front recreates itself to take the engine over (see [EngineHandoff]).
 */
class BubbleActivity : FlutterFragmentActivity() {

    override fun provideFlutterEngine(context: Context): FlutterEngine =
        MainActivity.provideRunningEngine(applicationContext)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Configured once in MainActivity.provideEngine.
    }

    override fun createFlutterFragment(): FlutterFragment =
        super.createFlutterFragment().apply {
            arguments?.putBoolean("destroy_engine_with_fragment", false)
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        pendingRoomId = intent.getStringExtra("shortcutId")
        super.onCreate(savedInstanceState)
        EngineHandoff.holder = this
    }

    override fun onRestart() {
        super.onRestart()
        if (EngineHandoff.holder !== this) recreate()
    }

    override fun onResume() {
        super.onResume()
        val roomId = intent.getStringExtra("shortcutId") ?: return
        // The Dart side also asks for pendingRoomId once it is ready, which
        // covers a cold start where this call arrives before it listens.
        MainActivity.engine?.let {
            MethodChannel(it.dartExecutor.binaryMessenger, CHANNEL_NAME)
                .invokeMethod("openRoom", roomId)
        }
    }

    companion object {
        const val CHANNEL_NAME = "chat.fluffy.fluffychat/bubble"

        /** The room a bubble was opened for, until Dart takes it. */
        var pendingRoomId: String? = null
    }
}

/** Which activity the shared Flutter engine is attached to. */
object EngineHandoff {
    var holder: Activity? = null
}
