package dev.zfhelper.app

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.util.SizeF
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup
import android.widget.RemoteViews
import java.time.LocalDate
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

internal object ScheduleWidgetRenderer {
    private const val LARGE_FONT_SCALE = 1.25f
    private const val EXPANDED_FOCUS_HEIGHT_DP = 92f
    private const val TIME_COLUMN_WIDTH_DP = 70f
    private const val LARGE_TIME_COLUMN_WIDTH_DP = 92f
    private val dateFormat = DateTimeFormatter.ofPattern("M月d日 EEE", Locale.SIMPLIFIED_CHINESE)

    fun render(
        context: Context,
        widgetId: Int,
        snapshot: ScheduleWidgetSnapshot?,
        failure: String?,
        now: ZonedDateTime,
    ): RemoteViews {
        val today = now.toLocalDate()
        val day = snapshot?.days?.firstOrNull { it.date == today }
        val frame = WidgetFrame(
            snapshot, day, focus(snapshot, failure, now), colors(context, snapshot), now,
            largeText = context.resources.configuration.fontScale > LARGE_FONT_SCALE,
        )
        return RemoteViews(
            mapOf(
                SizeF(180f, 200f) to layout(context, widgetId, false, frame),
                SizeF(260f, 300f) to layout(context, widgetId, true, frame),
            ),
        )
    }

    private fun layout(
        context: Context,
        widgetId: Int,
        expanded: Boolean,
        frame: WidgetFrame,
    ): RemoteViews {
        val (snapshot, _, focus, colors, now) = frame
        val views = RemoteViews(context.packageName, R.layout.schedule_widget)
        views.setViewVisibility(R.id.schedule_widget_list_container, if (expanded) View.VISIBLE else View.GONE)
        views.setViewVisibility(R.id.schedule_widget_day_summary, if (expanded && !frame.largeText) View.VISIBLE else View.GONE)
        views.setViewVisibility(R.id.schedule_widget_account, if (expanded && !frame.largeText) View.VISIBLE else View.GONE)
        views.setViewVisibility(R.id.schedule_widget_focus_label, if (frame.largeText) View.GONE else View.VISIBLE)
        views.setInt(R.id.schedule_widget_focus_title, "setMaxLines", if (expanded || frame.largeText) 1 else 2)
        views.setInt(R.id.schedule_widget_focus_meta, "setMaxLines", if (frame.largeText) 1 else 2)
        views.setInt(R.id.schedule_widget_focus_location, "setMaxLines", 1)
        // Bound large text while allowing the ordinary summary to fit its content.
        val boundSummary = expanded && frame.largeText
        views.setViewLayoutHeight(
            R.id.schedule_widget_focus,
            if (boundSummary) EXPANDED_FOCUS_HEIGHT_DP else ViewGroup.LayoutParams.WRAP_CONTENT.toFloat(),
            if (boundSummary) TypedValue.COMPLEX_UNIT_DIP else TypedValue.COMPLEX_UNIT_PX,
        )
        views.setColorStateList(
            R.id.schedule_widget_root, "setBackgroundTintList",
            ColorStateList.valueOf(colors.surface.day), ColorStateList.valueOf(colors.surface.night),
        )
        val headerDate = if (expanded) now.toLocalDate() else focus.date
        val headerWeek = snapshot?.days?.firstOrNull { it.date == headerDate }?.week
        val dateLabel = listOfNotNull(
            headerDate.format(dateFormat), headerWeek?.let { "第 $it 周" },
        ).joinToString(" · ")
        views.setTextViewText(R.id.schedule_widget_date, dateLabel)
        views.setTextViewText(R.id.schedule_widget_account, snapshot?.accountLabel?.ifBlank { null } ?: "ZFHelper")
        views.setContentDescription(
            R.id.schedule_widget_header,
            listOfNotNull(dateLabel, snapshot?.accountLabel, snapshot?.termLabel).joinToString("，"),
        )
        views.setTextViewText(R.id.schedule_widget_focus_label, focus.label)
        views.setTextViewText(R.id.schedule_widget_focus_title, focus.title)
        var detail = if (frame.largeText) focus.shortMeta ?: focus.meta else focus.meta
        if (expanded && focus.date != now.toLocalDate()) {
            val date = if (frame.largeText) "${focus.date.monthValue}/${focus.date.dayOfMonth}" else focus.date.format(dateFormat)
            detail = "$date · $detail"
        }
        views.setTextViewText(R.id.schedule_widget_focus_meta, detail)
        views.setTextViewText(R.id.schedule_widget_focus_location, focus.location)
        views.setViewVisibility(
            R.id.schedule_widget_focus_location,
            if (expanded || frame.largeText || focus.location.isBlank()) View.GONE else View.VISIBLE,
        )
        views.setTextColor(R.id.schedule_widget_date, colors.text)
        views.setTextColor(R.id.schedule_widget_account, colors.secondary)
        views.setTextColor(R.id.schedule_widget_focus_label, colors.primary)
        views.setTextColor(R.id.schedule_widget_focus_title, colors.text)
        views.setTextColor(R.id.schedule_widget_focus_meta, colors.secondary)
        views.setTextColor(R.id.schedule_widget_focus_location, colors.secondary)
        views.setWidgetColor(R.id.schedule_widget_refresh, "setColorFilter", colors.primary)
        views.setOnClickPendingIntent(
            R.id.schedule_widget_refresh,
            PendingIntent.getBroadcast(
                context, 0, Intent(context, ScheduleWidgetProvider::class.java).setAction(SCHEDULE_WIDGET_REFRESH),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ),
        )
        views.setOnClickPendingIntent(R.id.schedule_widget_header, openDate(context, widgetId, headerDate))
        views.setOnClickPendingIntent(R.id.schedule_widget_focus, openDate(context, widgetId, focus.date))
        views.setOnClickPendingIntent(
            R.id.schedule_widget_root, openDate(context, widgetId, if (expanded) now.toLocalDate() else focus.date),
        )
        views.setContentDescription(
            R.id.schedule_widget_focus,
            listOf(focus.date.format(dateFormat), focus.label, focus.title, focus.meta, focus.location)
                .filter(String::isNotBlank).joinToString("，"),
        )
        if (expanded) {
            bindTodayList(context, widgetId, views, frame)
        }
        return views
    }

    private fun bindTodayList(
        context: Context,
        widgetId: Int,
        views: RemoteViews,
        frame: WidgetFrame,
    ) {
        val usable = frame.focus.usable
        val day = frame.day?.takeIf { usable }
        val colors = frame.colors
        val lessons = day?.lessons.orEmpty()
        val count = if (lessons.isEmpty()) "今日课表" else "今日课表 · ${lessons.size} 项"
        views.setTextViewText(R.id.schedule_widget_day_summary, if (day?.byPeriod == true) "$count · 按节次" else count)
        views.setViewVisibility(R.id.schedule_widget_day_summary, if (usable && !frame.largeText) View.VISIBLE else View.GONE)
        views.setTextColor(R.id.schedule_widget_day_summary, colors.secondary)
        views.setTextViewText(
            R.id.schedule_widget_empty,
            if (usable) "今天没有课程" else "点击打开应用，检查课表设置",
        )
        views.setTextColor(R.id.schedule_widget_empty, colors.secondary)
        views.setEmptyView(R.id.schedule_widget_list, R.id.schedule_widget_empty)
        val rows = RemoteViews.RemoteCollectionItems.Builder().setViewTypeCount(1)
        val minutes = frame.now.hour * 60 + frame.now.minute
        lessons.forEachIndexed { index, lesson ->
            rows.addItem(index.toLong(), lessonRow(context, lesson, colors, day!!.date, minutes))
        }
        views.setRemoteAdapter(R.id.schedule_widget_list, rows.build())
        val template = Intent(context, MainActivity::class.java).apply {
            action = "dev.zfhelper.app.SCHEDULE_WIDGET_OPEN_LIST"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        views.setPendingIntentTemplate(
            R.id.schedule_widget_list,
            PendingIntent.getActivity(
                context, widgetId, template, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
            ),
        )
    }

    private fun lessonRow(
        context: Context,
        lesson: ScheduleWidgetLesson,
        colors: WidgetColors,
        date: LocalDate,
        minutes: Int,
    ): RemoteViews {
        val row = RemoteViews(context.packageName, R.layout.schedule_widget_lesson)
        row.setViewLayoutWidth(
            R.id.schedule_widget_lesson_time,
            if (context.resources.configuration.fontScale > LARGE_FONT_SCALE) {
                LARGE_TIME_COLUMN_WIDTH_DP
            } else {
                TIME_COLUMN_WIDTH_DP
            },
            TypedValue.COMPLEX_UNIT_DIP,
        )
        val timed = lesson.start != null && lesson.end != null
        val phase = lesson.phaseAt(minutes)
        row.setTextViewText(
            R.id.schedule_widget_lesson_start,
            lesson.start?.let(::scheduleWidgetClock) ?: lesson.periodLabel.ifBlank { "节次未设置" },
        )
        row.setTextViewText(
            R.id.schedule_widget_lesson_end,
            lesson.end?.let(::scheduleWidgetClock) ?: if (lesson.periods.isEmpty()) "作息未设置" else "作息不完整",
        )
        row.setTextViewText(R.id.schedule_widget_lesson_title, lesson.title)
        row.setTextViewText(R.id.schedule_widget_lesson_location, lesson.location)
        row.setViewVisibility(
            R.id.schedule_widget_lesson_location, if (lesson.location.isBlank()) View.GONE else View.VISIBLE,
        )
        val detail = listOfNotNull(
            lesson.periodLabel.takeIf { timed && it.isNotBlank() },
            lesson.teacher?.takeIf(String::isNotBlank),
            phase.label.takeIf { timed || phase == ScheduleWidgetPhase.IN_CLASS },
        ).joinToString(" · ")
        row.setTextViewText(R.id.schedule_widget_lesson_detail, detail)
        row.setViewVisibility(R.id.schedule_widget_lesson_detail, if (detail.isBlank()) View.GONE else View.VISIBLE)
        row.setTextColor(R.id.schedule_widget_lesson_start, colors.primary)
        row.setTextColor(R.id.schedule_widget_lesson_end, colors.secondary)
        row.setTextColor(R.id.schedule_widget_lesson_title, colors.text)
        row.setTextColor(R.id.schedule_widget_lesson_location, colors.secondary)
        row.setTextColor(R.id.schedule_widget_lesson_detail, colors.secondary)
        row.setWidgetColor(R.id.schedule_widget_lesson_divider, "setBackgroundColor", colors.outline)
        row.setOnClickFillInIntent(
            R.id.schedule_widget_lesson_root, Intent().putExtra(SCHEDULE_WIDGET_DATE, date.toString()),
        )
        row.setContentDescription(
            R.id.schedule_widget_lesson_root,
            listOf(lesson.title, lesson.periodLabel, lesson.timeLabel, lesson.location, detail)
                .filter(String::isNotBlank).joinToString("，"),
        )
        return row
    }

    private fun focus(snapshot: ScheduleWidgetSnapshot?, failure: String?, now: ZonedDateTime): WidgetFocus {
        val today = now.toLocalDate()
        if (failure != null) return WidgetFocus(today, "同步异常", "课表暂不可用", failure)
        if (snapshot == null) return WidgetFocus(today, "桌面课表", "先同步课表", "打开 ZFHelper，完成课表设置")
        when (snapshot.status) {
            "noAccount" -> return WidgetFocus(today, "桌面课表", "尚未添加账号", "请在应用设置中添加学校与账号")
            "noSchedule" -> return WidgetFocus(today, "桌面课表", "尚未导入课表", "请在应用设置中获取并保存课表")
            "calendarMissing" -> return WidgetFocus(today, "校历待设置", "无法确定上课日期", "请在校历与作息中填写第一周周一")
        }
        val minutes = now.hour * 60 + now.minute
        val day = snapshot.days.firstOrNull { it.date == today }
        val active = day?.lessons?.firstOrNull { it.phaseAt(minutes).isActive }
        if (active != null) return lessonFocus(today, active.phaseAt(minutes).label, active)
        if (day != null && (day.byPeriod || day.lessons.any { it.start == null })) {
            val pending = day.lessons.firstOrNull { it.end == null || it.end > minutes }
            if (pending != null) {
                return lessonFocus(today, if (day.byPeriod) "今日课程 · 按节次" else "今日课程", pending)
            }
        }
        val next = day?.lessons?.firstOrNull { it.start != null && it.start > minutes }
        if (next != null) return lessonFocus(today, "下一节", next)
        val later = snapshot.days.firstOrNull { it.date > today }
        if (later != null) {
            val label = when {
                later.byPeriod -> "后续课程 · 按节次"
                later.lessons.any { it.start == null } -> "后续课程"
                else -> "下一节"
            }
            return lessonFocus(
                later.date, label, later.lessons.first(),
            )
        }
        return WidgetFocus(
            today, "今日课表", if (day == null) "今天没有课程" else "今天的课程已结束",
            "点击查看课表与日程", usable = true,
        )
    }

    private fun lessonFocus(
        date: LocalDate,
        label: String,
        lesson: ScheduleWidgetLesson,
    ): WidgetFocus {
        val timing = listOfNotNull(
            lesson.periodLabel.takeIf(String::isNotBlank),
            lesson.timeLabel,
        ).joinToString(" · ")
        val shortMeta = if (lesson.start != null) lesson.timeLabel else lesson.periodLabel.ifBlank { lesson.timeLabel }
        return WidgetFocus(date, label, lesson.title, timing, lesson.location, usable = true, shortMeta = shortMeta)
    }

    private fun openDate(context: Context, widgetId: Int, date: LocalDate): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = "dev.zfhelper.app.SCHEDULE_WIDGET_OPEN.$date"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(SCHEDULE_WIDGET_DATE, date.toString())
        }
        return PendingIntent.getActivity(
            context, widgetId, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun colors(context: Context, snapshot: ScheduleWidgetSnapshot?): WidgetColors {
        val light = snapshot?.light ?: ScheduleWidgetColors(
            context.getColor(android.R.color.system_neutral1_50),
            context.getColor(android.R.color.system_accent1_600),
            context.getColor(android.R.color.system_neutral1_900),
            context.getColor(android.R.color.system_neutral2_600),
            context.getColor(android.R.color.system_neutral2_200),
        )
        val dark = snapshot?.dark ?: ScheduleWidgetColors(
            context.getColor(android.R.color.system_neutral1_900),
            context.getColor(android.R.color.system_accent1_200),
            context.getColor(android.R.color.system_neutral1_50),
            context.getColor(android.R.color.system_neutral2_200),
            context.getColor(android.R.color.system_neutral2_700),
        )
        val day = if (snapshot?.appearance == "dark") dark else light
        val night = if (snapshot?.appearance == "light") light else dark
        return WidgetColors(
            WidgetColor(day.surface, night.surface), WidgetColor(day.primary, night.primary),
            WidgetColor(day.text, night.text), WidgetColor(day.secondary, night.secondary),
            WidgetColor(day.outline, night.outline),
        )
    }

    private fun RemoteViews.setTextColor(viewId: Int, color: WidgetColor) =
        setWidgetColor(viewId, "setTextColor", color)

    private fun RemoteViews.setWidgetColor(viewId: Int, method: String, color: WidgetColor) =
        setColorInt(viewId, method, color.day, color.night)

    private data class WidgetColor(val day: Int, val night: Int)

    private data class WidgetColors(
        val surface: WidgetColor,
        val primary: WidgetColor,
        val text: WidgetColor,
        val secondary: WidgetColor,
        val outline: WidgetColor,
    )

    private data class WidgetFrame(
        val snapshot: ScheduleWidgetSnapshot?,
        val day: ScheduleWidgetDay?,
        val focus: WidgetFocus,
        val colors: WidgetColors,
        val now: ZonedDateTime,
        val largeText: Boolean,
    )

    private data class WidgetFocus(
        val date: LocalDate,
        val label: String,
        val title: String,
        val meta: String,
        val location: String = "",
        val usable: Boolean = false,
        val shortMeta: String? = null,
    )
}
