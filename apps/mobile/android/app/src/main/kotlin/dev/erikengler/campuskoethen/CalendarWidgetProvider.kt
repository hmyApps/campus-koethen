package dev.erikengler.campuskoethen

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.content.res.Configuration
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject
import java.text.DateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

class CalendarWidgetProvider : HomeWidgetProvider() {
    companion object {
        private const val PAYLOAD_KEY = "calendar_widget_payload"
        private const val MAX_VISIBLE_EVENTS = 3
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val state = parseState(widgetData.getString(PAYLOAD_KEY, null))
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.calendar_widget)
            bind(context, views, state)
            views.setOnClickPendingIntent(
                R.id.calendar_widget_root,
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("campuskoethen://calendar?homeWidget=1"),
                ),
            )
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun bind(context: Context, views: RemoteViews, state: WidgetState) {
        val localized = localizedContext(context, state.locale)
        views.setTextViewText(R.id.calendar_widget_title, localized.getString(R.string.calendar_widget_title))

        if (!state.enabled) {
            showMessage(
                views,
                localized.getString(R.string.calendar_widget_disabled),
            )
            views.setTextViewText(R.id.calendar_widget_updated, "")
            return
        }

        val now = System.currentTimeMillis()
        val upcoming = state.events
            .filter { it.end > now || (it.end <= it.start && it.start > now) }
            .sortedWith(compareBy<WidgetEvent> { it.start }.thenBy { it.title ?: "" })
            .take(MAX_VISIBLE_EVENTS)
        if (upcoming.isEmpty()) {
            showMessage(
                views,
                localized.getString(R.string.calendar_widget_empty),
            )
        } else {
            views.setViewVisibility(R.id.calendar_widget_message, View.GONE)
            val rows = listOf(
                Triple(R.id.calendar_widget_row_1, R.id.calendar_widget_time_1, R.id.calendar_widget_event_1),
                Triple(R.id.calendar_widget_row_2, R.id.calendar_widget_time_2, R.id.calendar_widget_event_2),
                Triple(R.id.calendar_widget_row_3, R.id.calendar_widget_time_3, R.id.calendar_widget_event_3),
            )
            rows.forEachIndexed { index, ids ->
                val event = upcoming.getOrNull(index)
                if (event == null) {
                    views.setViewVisibility(ids.first, View.GONE)
                } else {
                    views.setViewVisibility(ids.first, View.VISIBLE)
                    views.setTextViewText(
                        ids.second,
                        formatWhen(localized, localeFor(state.locale), event),
                    )
                    val privateTitle = localized.getString(R.string.calendar_widget_private_event)
                    val title = event.title?.takeIf { it.isNotBlank() } ?: privateTitle
                    val eventLabel = event.location?.takeIf { it.isNotBlank() }?.let { "$title · $it" } ?: title
                    views.setTextViewText(ids.third, eventLabel)
                }
            }
        }
        val updated = DateFormat.getDateTimeInstance(
            DateFormat.SHORT,
            DateFormat.SHORT,
            localeFor(state.locale),
        ).format(Date(state.generatedAt))
        views.setTextViewText(
            R.id.calendar_widget_updated,
            localized.getString(R.string.calendar_widget_updated, updated),
        )
    }

    private fun showMessage(views: RemoteViews, message: String) {
        views.setViewVisibility(R.id.calendar_widget_message, View.VISIBLE)
        views.setTextViewText(R.id.calendar_widget_message, message)
        listOf(
            R.id.calendar_widget_row_1,
            R.id.calendar_widget_row_2,
            R.id.calendar_widget_row_3,
        ).forEach { views.setViewVisibility(it, View.GONE) }
    }

    private fun formatWhen(context: Context, locale: Locale, event: WidgetEvent): String {
        val start = Calendar.getInstance().apply { timeInMillis = event.start }
        val today = Calendar.getInstance()
        val tomorrow = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, 1) }
        val day = when {
            sameDay(start, today) -> context.getString(R.string.calendar_widget_today)
            sameDay(start, tomorrow) -> context.getString(R.string.calendar_widget_tomorrow)
            else -> DateFormat.getDateInstance(DateFormat.SHORT, locale).format(start.time)
        }
        return if (event.allDay) {
            "$day · ${context.getString(R.string.calendar_widget_all_day)}"
        } else {
            val time = DateFormat.getTimeInstance(DateFormat.SHORT, locale).format(start.time)
            "$day · $time"
        }
    }

    private fun sameDay(a: Calendar, b: Calendar): Boolean =
        a.get(Calendar.ERA) == b.get(Calendar.ERA) &&
            a.get(Calendar.YEAR) == b.get(Calendar.YEAR) &&
            a.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR)

    private fun localizedContext(context: Context, language: String): Context {
        val configuration = Configuration(context.resources.configuration)
        configuration.setLocale(localeFor(language))
        return context.createConfigurationContext(configuration)
    }

    private fun localeFor(language: String): Locale =
        if (language == "en") Locale.ENGLISH else Locale.GERMAN

    private fun parseState(payload: String?): WidgetState {
        if (payload.isNullOrBlank() || payload.length > 64 * 1024) return WidgetState.disabled()
        return try {
            val root = JSONObject(payload)
            if (root.optInt("version", -1) != 1) return WidgetState.disabled()
            val language = if (root.optString("locale") == "en") "en" else "de"
            val eventsJson = root.optJSONArray("events")
            val events = buildList {
                if (eventsJson != null) {
                    for (index in 0 until minOf(eventsJson.length(), 12)) {
                        val item = eventsJson.optJSONObject(index) ?: continue
                        val start = item.optLong("start", Long.MIN_VALUE)
                        val end = item.optLong("end", Long.MIN_VALUE)
                        if (start == Long.MIN_VALUE || end == Long.MIN_VALUE) continue
                        add(
                            WidgetEvent(
                                start = start,
                                end = end,
                                allDay = item.optBoolean("allDay", false),
                                title = item.optString("title").takeIf { it.isNotBlank() }?.take(120),
                                location = item.optString("location").takeIf { it.isNotBlank() }?.take(120),
                            ),
                        )
                    }
                }
            }
            WidgetState(
                enabled = root.optBoolean("enabled", false),
                generatedAt = root.optLong("generatedAt", 0L).coerceAtLeast(0L),
                locale = language,
                events = events,
            )
        } catch (_: Exception) {
            WidgetState.disabled()
        }
    }

    private data class WidgetState(
        val enabled: Boolean,
        val generatedAt: Long,
        val locale: String,
        val events: List<WidgetEvent>,
    ) {
        companion object {
            fun disabled() = WidgetState(false, 0L, "de", emptyList())
        }
    }

    private data class WidgetEvent(
        val start: Long,
        val end: Long,
        val allDay: Boolean,
        val title: String?,
        val location: String?,
    )
}
