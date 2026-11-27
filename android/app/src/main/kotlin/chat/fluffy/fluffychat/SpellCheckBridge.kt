// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

package chat.fluffy.fluffychat

import android.content.Context
import android.view.textservice.SentenceSuggestionsInfo
import android.view.textservice.SpellCheckerSession
import android.view.textservice.SuggestionsInfo
import android.view.textservice.TextInfo
import android.view.textservice.TextServicesManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * Checks the message input's spelling with the system spell checker for
 * lib/utils/android_spell_check.dart, as Flutter's own SpellCheckPlugin
 * does, but also hands over each span's SuggestionsInfo attributes. The
 * engine leaves those out, so a span the checker marks as a grammar
 * suggestion reaches Flutter looking like a typo; the Dart side keeps only
 * the spans marked as typos.
 *
 * `check` takes `[languageTag, text]` and answers a list of maps with
 * `startIndex`, `endIndex`, `suggestions` and `attributes`. A check sent
 * while another is still running fails, which the Dart side reads as
 * "no new results", as with the engine's plugin.
 */
class SpellCheckBridge(private val context: Context) :
    MethodChannel.MethodCallHandler, SpellCheckerSession.SpellCheckerSessionListener {

    private var session: SpellCheckerSession? = null
    private var sessionLocale: Locale? = null
    private var pending: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "check") {
            result.notImplemented()
            return
        }
        val args = call.arguments as? List<*>
        val tag = args?.getOrNull(0) as? String
        val text = args?.getOrNull(1) as? String
        if (tag == null || text == null) {
            result.error("bad_args", "Expected [languageTag, text].", null)
            return
        }
        if (pending != null) {
            result.error("pending", "Previous spell check request still pending.", null)
            return
        }
        val session = sessionFor(Locale.forLanguageTag(tag))
        if (session == null) {
            result.success(emptyList<Map<String, Any>>())
            return
        }
        pending = result
        session.getSentenceSuggestions(arrayOf(TextInfo(text)), MAX_SUGGESTIONS)
    }

    private fun sessionFor(locale: Locale): SpellCheckerSession? {
        if (session == null || sessionLocale != locale) {
            session?.close()
            val manager =
                context.getSystemService(Context.TEXT_SERVICES_MANAGER_SERVICE)
                    as? TextServicesManager
            // Follows the spell checker's own language settings, like the
            // engine, with [locale] as the fallback.
            session = manager?.newSpellCheckerSession(null, locale, this, true)
            sessionLocale = locale
        }
        return session
    }

    override fun onGetSentenceSuggestions(results: Array<out SentenceSuggestionsInfo>?) {
        val result = pending ?: return
        pending = null
        val info = results?.firstOrNull()
        if (info == null) {
            result.success(emptyList<Map<String, Any>>())
            return
        }
        val spans = mutableListOf<Map<String, Any>>()
        for (i in 0 until info.suggestionsCount) {
            val suggestions = info.getSuggestionsInfoAt(i)
            // Some checkers (Samsung's) report spans whose suggestions are
            // all empty strings; like the engine, those are left out.
            val words = (0 until suggestions.suggestionsCount)
                .map { suggestions.getSuggestionAt(it) }
                .filter { it.isNotEmpty() }
            if (words.isEmpty()) continue
            val start = info.getOffsetAt(i)
            spans.add(
                mapOf(
                    "startIndex" to start,
                    "endIndex" to start + info.getLengthAt(i),
                    "suggestions" to words,
                    "attributes" to suggestions.suggestionsAttributes,
                ),
            )
        }
        result.success(spans)
    }

    override fun onGetSuggestions(results: Array<out SuggestionsInfo>?) {}

    companion object {
        const val CHANNEL_NAME = "chat.fluffy.fluffychat/spell_check"
        private const val MAX_SUGGESTIONS = 5
    }
}
