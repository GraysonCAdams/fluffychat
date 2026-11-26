// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

package chat.fluffy.fluffychat

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.BitmapFactory
import androidx.car.app.CarAppService
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.constraints.ConstraintManager
import androidx.car.app.messaging.model.CarMessage
import androidx.car.app.messaging.model.ConversationCallback
import androidx.car.app.messaging.model.ConversationItem
import androidx.car.app.model.Action
import androidx.car.app.model.CarIcon
import androidx.car.app.model.CarText
import androidx.car.app.model.Header
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Template
import androidx.car.app.validation.HostValidator
import androidx.core.app.Person
import androidx.core.graphics.drawable.IconCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner

/**
 * Android Auto's templated messaging app: a list of the latest conversations
 * that the car can read aloud, mark as read and reply to by voice.
 *
 * Android Auto draws each [ConversationItem] and its play, mark-as-read and
 * reply actions itself; this service only supplies the data, which comes
 * from the Dart side through [CarBridge]. The notification-powered
 * experience (MessagingStyle notifications with reply and mark-as-read
 * actions, built in lib/utils/push_helper.dart) works without it.
 *
 * Docs: https://developer.android.com/training/cars/communication/templated-messaging
 */
class SeamCarAppService : CarAppService() {

    override fun createHostValidator(): HostValidator =
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
        } else {
            // Android Auto and the other hosts Google signs.
            HostValidator.Builder(applicationContext)
                .addAllowedHosts(androidx.car.app.R.array.hosts_allowlist_sample)
                .build()
        }

    override fun onCreateSession(): Session = object : Session() {
        override fun onCreateScreen(intent: Intent): Screen = ConversationListScreen(carContext)
    }
}

/** The latest conversations, newest first. */
class ConversationListScreen(carContext: CarContext) : Screen(carContext) {

    private sealed interface State {
        object Loading : State
        object SignedOut : State
        object Failed : State
        class Loaded(val items: List<ConversationItem>) : State
    }

    private var state: State = State.Loading
    private val onChanged: () -> Unit = { load() }

    init {
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onCreate(owner: LifecycleOwner) {
                CarBridge.addListener(onChanged)
                // Keeps the account syncing while the car shows the list.
                CarBridge.call(carContext, "start")
                load()
            }

            override fun onDestroy(owner: LifecycleOwner) {
                CarBridge.removeListener(onChanged)
                CarBridge.call(carContext, "stop")
            }
        })
    }

    /** How many conversations the car can show, at most ten as the docs advise. */
    private fun limit(): Int {
        val carLimit = try {
            carContext.getCarService(ConstraintManager::class.java)
                .getContentLimit(ConstraintManager.CONTENT_LIMIT_TYPE_LIST)
        } catch (e: Exception) {
            MAX_CONVERSATIONS
        }
        return minOf(carLimit, MAX_CONVERSATIONS)
    }

    private fun load() {
        CarBridge.call(carContext, "conversations", mapOf("limit" to limit())) { result ->
            state = parse(result)
            invalidate()
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun parse(result: Any?): State {
        val map = result as? Map<String, Any?> ?: return State.Failed
        if (map["signedIn"] != true) return State.SignedOut
        val conversations = map["conversations"] as? List<Map<String, Any?>> ?: emptyList()
        return State.Loaded(conversations.mapNotNull { conversationItem(it) })
    }

    @Suppress("UNCHECKED_CAST")
    private fun conversationItem(map: Map<String, Any?>): ConversationItem? {
        val id = map["id"] as? String ?: return null
        // The account's own user, which differs between accounts.
        val selfMap = map["self"] as? Map<String, Any?> ?: return null
        val self = Person.Builder()
            .setName(selfMap["name"] as? String ?: "")
            .setKey(selfMap["key"] as? String)
            .build()
        val clientName = map["client"] as? String ?: return null
        val title = map["title"] as? String ?: return null
        val messages = (map["messages"] as? List<Map<String, Any?>> ?: emptyList()).map {
            CarMessage.Builder()
                .setSender(
                    Person.Builder()
                        .setName(it["name"] as? String ?: "")
                        .setKey(it["key"] as? String)
                        .build()
                )
                .setBody(CarText.create(it["body"] as? String ?: ""))
                .setReceivedTimeEpochMillis((it["ts"] as? Number)?.toLong() ?: 0L)
                .setRead(it["read"] == true)
                .build()
        }
        // A conversation item needs at least one message.
        if (messages.isEmpty()) return null
        val target = mapOf("client" to clientName, "id" to id)
        val callback = object : ConversationCallback {
            override fun onMarkAsRead() {
                CarBridge.call(carContext, "markRead", target)
            }

            override fun onTextReply(replyText: String) {
                CarBridge.call(carContext, "reply", target + ("text" to replyText))
            }
        }
        return ConversationItem.Builder(id, CarText.create(title), self, messages, callback)
            .setGroupConversation(map["group"] == true)
            .apply {
                (map["icon"] as? ByteArray)
                    ?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
                    ?.let { setIcon(CarIcon.Builder(IconCompat.createWithBitmap(it)).build()) }
            }
            .build()
    }

    override fun onGetTemplate(): Template {
        val header = Header.Builder()
            .setStartHeaderAction(Action.APP_ICON)
            .setTitle(carContext.getString(R.string.car_conversations_title))
            .build()
        val builder = ListTemplate.Builder().setHeader(header)
        when (val s = state) {
            State.Loading -> builder.setLoading(true)
            State.SignedOut -> builder.setSingleList(
                emptyList(carContext.getString(R.string.car_signed_out))
            )
            State.Failed -> builder.setSingleList(
                emptyList(carContext.getString(R.string.car_load_failed))
            )
            is State.Loaded -> builder.setSingleList(
                ItemList.Builder()
                    .apply { s.items.forEach { addItem(it) } }
                    .setNoItemsMessage(carContext.getString(R.string.car_no_conversations))
                    .build()
            )
        }
        return builder.build()
    }

    private fun emptyList(message: String) =
        ItemList.Builder().setNoItemsMessage(message).build()

    companion object {
        private const val MAX_CONVERSATIONS = 10
    }
}
