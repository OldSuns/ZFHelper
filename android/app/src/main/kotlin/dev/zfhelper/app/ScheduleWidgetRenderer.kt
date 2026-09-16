package dev.zfhelper.app

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup
import android.widget.RemoteViews
import java.time.LocalDate
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

internal object ScheduleWidgetRenderer {
    private val dateFormat = DateTimeFormatter.ofPattern("M月d日 EEE", Locale.SIMPLIFIED_CHINESE)
    private val shortDateFormat = DateTimeFormatter.ofPattern("M/d EEE", Locale.SIMPLIFIED_CHINESE)

    fun render(
        context: Context,
        widgetId: Int,
        snapshot: ScheduleWidgetSnapshot?,
        failure: String?,
        now: ZonedDateTime,
    ): RemoteViews {
        val today = now.toLocalDate()
        val day = snapshot?.days?.firstOrNull { it.date == today }
        val frame = WidgetFrame(snapshot, day, focus(snapshot, failure, now), colors(context, snapshot), now)
        val sizing = ScheduleWidgetSizing(context)
        val futureSummary = frame.focus.date != today && day?.lessons?.isNotEmpty() == true
        return RemoteViews(
            sizing.variants(futureSummary).associate { variant ->
                variant.size to layout(context, widgetId, variant, sizing, frame)
            },
        )
    }

    private fun layout(
        context: Context,
        widgetId: Int,
        variant: ScheduleWidgetLayout,
        sizing: ScheduleWidgetSizing,
        frame: WidgetFrame,
    ): RemoteViews {
        val (snapshot, _, focus, colors, now) = frame
        val views = RemoteViews(context.packageName, R.layout.schedule_widget)
        val showList = variant.list && focus.usable && frame.day?.lessons?.isNotEmpty() == true
        val futureSummary = showList && focus.date != now.toLocalDate()
        val strip = variant.style == ScheduleWidgetStyle.STRIP || futureSummary
        val padding = sizing.pixels(sizing.padding)
        val verticalPadding = sizing.pixels(when {
            showList -> sizing.padding
            strip -> sizing.compactPadding
            else -> sizing.cardPadding
        })
        views.setViewPadding(R.id.schedule_widget_root, padding, verticalPadding, padding, verticalPadding)
        views.visible(R.id.schedule_widget_header, showList)
        views.visible(R.id.schedule_widget_refresh, showList && variant.columns)
        views.visible(R.id.schedule_widget_list, showList)
        // The active/next course is already in today's list. Only a course on a
        // later date needs a separate summary above it.
        views.visible(R.id.schedule_widget_focus, !showList || futureSummary)
        bindFocus(views, frame, variant, sizing, strip, showList)
        views.setColorStateList(
            R.id.schedule_widget_root, "setBackgroundTintList",
            ColorStateList.valueOf(colors.surface.day), ColorStateList.valueOf(colors.surface.night),
        )
        val headerDate = if (showList) now.toLocalDate() else focus.date
        val headerWeek = snapshot?.days?.firstOrNull { it.date == headerDate }?.week
        val dateLabel = headerDate.format(if (variant.columns) dateFormat else shortDateFormat)
        views.setTextViewText(R.id.schedule_widget_date, dateLabel)
        val summary = listOfNotNull(
            headerWeek?.let { "第 $it 周" },
            frame.day?.lessons?.size?.let { "$it 门课" },
            "按节次".takeIf { frame.day?.byPeriod == true },
        ).joinToString(" · ")
        views.setTextViewText(R.id.schedule_widget_context, summary)
        views.setContentDescription(
            R.id.schedule_widget_header,
            listOfNotNull(dateLabel, summary, snapshot?.accountLabel, snapshot?.termLabel).joinToString("，"),
        )
        views.setTextColor(R.id.schedule_widget_date, colors.text)
        views.setTextColor(R.id.schedule_widget_context, colors.secondary)
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
        views.setOnClickPendingIntent(
            R.id.schedule_widget_header,
            if (variant.columns) openDate(context, widgetId, headerDate) else null,
        )
        views.setOnClickPendingIntent(R.id.schedule_widget_focus, openDate(context, widgetId, focus.date))
        views.setOnClickPendingIntent(
            R.id.schedule_widget_root, openDate(context, widgetId, headerDate),
        )
        views.setContentDescription(
            R.id.schedule_widget_focus,
            listOf(focus.date.format(dateFormat), focus.label, focus.title, focus.meta, focus.location)
                .filter(String::isNotBlank).joinToString("，"),
        )
        if (showList) {
            bindTodayList(context, widgetId, views, frame, variant, sizing)
        }
        return views
    }

    private fun bindFocus(
        views: RemoteViews,
        frame: WidgetFrame,
        variant: ScheduleWidgetLayout,
        sizing: ScheduleWidgetSizing,
        strip: Boolean,
        showList: Boolean,
    ) {
        val focus = frame.focus
        val metaFits = !strip || showList ||
            sizing.stripTitleLine + sizing.bodyLine + 2 * sizing.compactPadding + 6 <= variant.size.height
        val locationFits = !strip || (!showList &&
            sizing.stripTitleLine + 2 * sizing.bodyLine + 2 * sizing.compactPadding + 8 <= variant.size.height)
        val showLocation = locationFits && focus.location.isNotBlank()
        val shortMeta = focus.shortMeta ?: focus.meta
        val datedMeta = if (focus.date != frame.now.toLocalDate()) {
            "${focus.date.monthValue}/${focus.date.dayOfMonth} · $shortMeta"
        } else {
            shortMeta
        }
        val meta = listOfNotNull(
            if (strip) datedMeta else shortMeta,
            focus.location.takeIf { strip && !showLocation && it.isNotBlank() },
        ).joinToString(" · ")
        views.visible(R.id.schedule_widget_focus_label, !strip)
        views.visible(R.id.schedule_widget_focus_meta, metaFits)
        views.visible(R.id.schedule_widget_focus_location, showLocation)
        val titleLines = if (strip) 1 else {
            val metaHeight = sizing.bodyHeight(shortMeta) * if (focus.usable) 1 else 2
            val locationHeight = if (showLocation) sizing.bodyLine + 2 else 0f
            ((variant.size.height - 2 * sizing.cardPadding - sizing.captionLine - metaHeight - locationHeight - 4) / sizing.titleLine)
                .toInt().coerceIn(1, 2)
        }
        views.setTextViewTextSize(
            R.id.schedule_widget_focus_title, TypedValue.COMPLEX_UNIT_PX,
            if (strip) sizing.stripTitlePixels else sizing.titlePixels,
        )
        views.setInt(R.id.schedule_widget_focus_title, "setMaxLines", titleLines)
        views.setInt(R.id.schedule_widget_focus_meta, "setMaxLines", if (strip || focus.usable) 1 else 2)
        views.setInt(R.id.schedule_widget_focus_location, "setMaxLines", 1)
        views.setTextViewText(R.id.schedule_widget_focus_label, "${focus.date.format(shortDateFormat)} · ${focus.label}")
        views.setTextViewText(
            R.id.schedule_widget_focus_title,
            if (metaFits) focus.title else "${focus.title} · $datedMeta",
        )
        views.setTextViewText(R.id.schedule_widget_focus_meta, meta)
        views.setTextViewText(R.id.schedule_widget_focus_location, focus.location)
        views.setViewLayoutHeight(
            R.id.schedule_widget_focus,
            (if (showList) ViewGroup.LayoutParams.WRAP_CONTENT else ViewGroup.LayoutParams.MATCH_PARENT).toFloat(),
            TypedValue.COMPLEX_UNIT_PX,
        )
        views.setViewPadding(R.id.schedule_widget_focus, 0, 0, 0, if (showList) sizing.pixels(sizing.padding) else 0)
    }

    private fun bindTodayList(
        context: Context,
        widgetId: Int,
        views: RemoteViews,
        frame: WidgetFrame,
        variant: ScheduleWidgetLayout,
        sizing: ScheduleWidgetSizing,
    ) {
        val day = frame.day!!
        val colors = frame.colors
        val rows = RemoteViews.RemoteCollectionItems.Builder().setViewTypeCount(1)
        val minutes = frame.now.hour * 60 + frame.now.minute
        day.lessons.forEachIndexed { index, lesson ->
            rows.addItem(index.toLong(), lessonRow(context, lesson, colors, day.date, minutes, variant, sizing))
        }
        views.setRemoteAdapter(R.id.schedule_widget_list, rows.build())
        val focusedIndex = day.lessons.indexOfFirst { it.id == frame.focus.lessonId }
        if (focusedIndex >= 0) views.setScrollPosition(R.id.schedule_widget_list, focusedIndex)
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
        variant: ScheduleWidgetLayout,
        sizing: ScheduleWidgetSizing,
    ): RemoteViews {
        val row = RemoteViews(context.packageName, R.layout.schedule_widget_lesson)
        val timed = lesson.start != null && lesson.end != null
        val columns = variant.columns && timed
        row.setViewLayoutWidth(
            R.id.schedule_widget_lesson_time,
            sizing.timeColumnWidth,
            TypedValue.COMPLEX_UNIT_DIP,
        )
        row.visible(R.id.schedule_widget_lesson_time, columns)
        row.visible(R.id.schedule_widget_lesson_when, !columns)
        val phase = lesson.phaseAt(minutes)
        row.setTextViewText(
            R.id.schedule_widget_lesson_start,
            lesson.start?.let(::scheduleWidgetClock),
        )
        row.setTextViewText(
            R.id.schedule_widget_lesson_end,
            lesson.end?.let { "${scheduleWidgetClock(it)}\n${phase.label}" },
        )
        row.setInt(R.id.schedule_widget_lesson_end, "setMaxLines", 2)
        row.setTextViewText(
            R.id.schedule_widget_lesson_when,
            listOf(
                if (timed) lesson.timeLabel else lesson.periodLabel.ifBlank { "节次未设置" },
                phase.label,
            ).joinToString(" · "),
        )
        row.setTextViewText(R.id.schedule_widget_lesson_title, lesson.title)
        row.setTextViewText(R.id.schedule_widget_lesson_location, lesson.location)
        row.setViewVisibility(
            R.id.schedule_widget_lesson_location, if (lesson.location.isBlank()) View.GONE else View.VISIBLE,
        )
        val detail = listOfNotNull(
            lesson.periodLabel.takeIf { timed && it.isNotBlank() },
            lesson.teacher?.takeIf(String::isNotBlank),
        ).joinToString(" · ")
        row.setTextViewText(R.id.schedule_widget_lesson_detail, detail)
        row.visible(R.id.schedule_widget_lesson_detail, variant.detailed && detail.isNotBlank())
        row.setTextColor(R.id.schedule_widget_lesson_when, colors.primary)
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
            listOf(lesson.title, lesson.periodLabel, lesson.timeLabel, lesson.location, detail, phase.label)
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
        return WidgetFocus(date, label, lesson.title, timing, lesson.location, usable = true, shortMeta = shortMeta, lessonId = lesson.id)
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

    private fun RemoteViews.visible(viewId: Int, visible: Boolean) =
        setViewVisibility(viewId, if (visible) View.VISIBLE else View.GONE)

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
    )

    private data class WidgetFocus(
        val date: LocalDate,
        val label: String,
        val title: String,
        val meta: String,
        val location: String = "",
        val usable: Boolean = false,
        val shortMeta: String? = null,
        val lessonId: String? = null,
    )
}
