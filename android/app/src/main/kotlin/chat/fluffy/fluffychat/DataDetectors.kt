// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

package chat.fluffy.fluffychat

import android.app.ActivityOptions
import android.app.RemoteAction
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Build
import android.os.Handler
import android.os.LocaleList
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.textclassifier.TextClassification
import android.view.textclassifier.TextClassificationManager
import android.view.textclassifier.TextClassifier
import android.view.textclassifier.TextLinks
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Android's data detectors (Smart Linkify) for lib/utils/data_detectors,
 * through the system TextClassifier, so detection and its actions are the
 * phone's own: localised, and handled by the apps the phone would use.
 *
 * - `detect` with `text` and `referenceTime` (ms since the epoch) finds
 *   addresses, phone numbers, dates, dates with times and flight numbers
 *   with `generateLinks`, then classifies each with `classifyText` for the
 *   system's actions (`RemoteAction`s): each one's title, description and,
 *   where the system shows one, the handling app's icon as a PNG.
 * - `runAction` with `token` and `index` sends that action's intent. A
 *   token no longer held is classified again from `text`.
 *
 * The classifier blocks, so both run on one background thread. Detections
 * are cached by the Dart side, keyed by event and text, so a message is
 * classified once.
 */
class DataDetectors(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL_NAME = "chat.fluffy.fluffychat/data_detectors"
        private const val TAG = "DataDetectors"

        /** Detections classified for actions per message; the rest of a long list is skipped. */
        private const val MAX_DETECTIONS = 6

        /** Icons are sent at this size in pixels: 24dp at 4x. */
        private const val ICON_PX = 96

        /** Actions are kept for this many detections. */
        private const val MAX_TOKENS = 300

        private val ENTITY_TYPES = listOf(
            TextClassifier.TYPE_ADDRESS,
            TextClassifier.TYPE_PHONE,
            TextClassifier.TYPE_DATE,
            TextClassifier.TYPE_DATE_TIME,
            TextClassifier.TYPE_FLIGHT_NUMBER,
        )
    }

    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    /** The actions of each detection handed to Dart, by token, oldest first. */
    private val actions = object : LinkedHashMap<String, List<RemoteAction>>(64, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, List<RemoteAction>>?) =
            size > MAX_TOKENS
    }

    private val classifier: TextClassifier?
        get() = context.getSystemService(TextClassificationManager::class.java)?.textClassifier

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "detect" -> {
                val text = call.argument<String>("text").orEmpty()
                val reference = call.argument<Number>("referenceTime")?.toLong()
                worker.execute {
                    val answer = try {
                        detect(text, reference)
                    } catch (e: Exception) {
                        Log.w(TAG, "Detection failed", e)
                        emptyList()
                    }
                    main.post { result.success(answer) }
                }
            }
            "runAction" -> {
                val token = call.argument<String>("token")
                val index = call.argument<Int>("index") ?: 0
                val text = call.argument<String>("text").orEmpty()
                val reference = call.argument<Number>("referenceTime")?.toLong()
                worker.execute {
                    val action = try {
                        val known = token?.let { synchronized(actions) { actions[it] } }
                        (known ?: classify(text, 0, text.length, reference)).getOrNull(index)
                    } catch (e: Exception) {
                        Log.w(TAG, "Classification failed", e)
                        null
                    }
                    main.post { result.success(action != null && send(action)) }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun locales(): LocaleList = LocaleList.getDefault()

    private fun zoned(reference: Long?): ZonedDateTime? = reference?.let {
        ZonedDateTime.ofInstant(Instant.ofEpochMilli(it), ZoneId.systemDefault())
    }

    private fun detect(text: String, reference: Long?): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return emptyList()
        val classifier = classifier ?: return emptyList()
        if (text.isBlank() || text.length > classifier.maxGenerateLinksTextLength) return emptyList()
        val started = SystemClock.elapsedRealtime()
        val request = TextLinks.Request.Builder(text)
            .setEntityConfig(TextClassifier.EntityConfig.createWithExplicitEntityList(ENTITY_TYPES))
            .setDefaultLocales(locales())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            request.setReferenceTime(zoned(reference))
        }
        val links = classifier.generateLinks(request.build()).links
        val linked = SystemClock.elapsedRealtime()
        val answer = mutableListOf<Map<String, Any?>>()
        for (link in links.sortedBy { it.start }) {
            if (answer.size >= MAX_DETECTIONS) break
            if (link.entityCount == 0) continue
            val type = link.getEntity(0)
            if (type !in ENTITY_TYPES) continue
            val remoteActions = classify(text, link.start, link.end, reference)
            val token = UUID.randomUUID().toString()
            synchronized(actions) { actions[token] = remoteActions }
            answer.add(
                mapOf(
                    "type" to type,
                    "start" to link.start,
                    "end" to link.end,
                    "token" to token,
                    "actions" to remoteActions.map { action ->
                        mapOf(
                            "title" to action.title.toString(),
                            "description" to action.contentDescription?.toString(),
                            "icon" to if (action.shouldShowIcon()) iconPng(action) else null,
                        )
                    },
                ),
            )
        }
        Log.d(
            TAG,
            "${text.length} chars: generateLinks ${linked - started} ms, " +
                "classifyText x${answer.size} ${SystemClock.elapsedRealtime() - linked} ms",
        )
        return answer
    }

    private fun classify(text: String, start: Int, end: Int, reference: Long?): List<RemoteAction> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return emptyList()
        val classifier = classifier ?: return emptyList()
        val request = TextClassification.Request.Builder(text, start, end)
            .setDefaultLocales(locales())
            .setReferenceTime(zoned(reference))
            .build()
        return classifier.classifyText(request).actions
    }

    /** Icons drawn once per app and action kind. */
    private val icons = HashMap<String, ByteArray?>()

    private fun iconPng(action: RemoteAction): ByteArray? {
        val icon = action.icon
        val key = if (icon.type == android.graphics.drawable.Icon.TYPE_RESOURCE) {
            "${icon.resPackage}/${icon.resId}"
        } else {
            null
        }
        if (key != null && icons.containsKey(key)) return icons[key]
        val png = try {
            val drawable = icon.loadDrawable(context) ?: return null
            val bitmap = Bitmap.createBitmap(ICON_PX, ICON_PX, Bitmap.Config.ARGB_8888)
            drawable.setBounds(0, 0, ICON_PX, ICON_PX)
            drawable.draw(Canvas(bitmap))
            ByteArrayOutputStream().use { out ->
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
                out.toByteArray()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Action icon failed", e)
            null
        }
        if (key != null) icons[key] = png
        return png
    }

    /**
     * Sends [action]'s intent. The intent belongs to the classifier's
     * process, so from Android 14 Seam, in the foreground, lends it the
     * right to start an activity.
     */
    private fun send(action: RemoteAction): Boolean = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val options = ActivityOptions.makeBasic().setPendingIntentBackgroundActivityStartMode(
                ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED,
            )
            action.actionIntent.send(context, 0, null, null, null, null, options.toBundle())
        } else {
            action.actionIntent.send()
        }
        true
    } catch (e: Exception) {
        Log.w(TAG, "Action failed", e)
        false
    }
}
