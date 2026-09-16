package dev.zfhelper.app

import android.content.Context
import android.graphics.Paint
import android.graphics.Typeface
import android.text.StaticLayout
import android.text.TextPaint
import android.util.SizeF
import kotlin.math.ceil

internal enum class ScheduleWidgetStyle { STRIP, CARD, STACKED_LIST, COLUMNS_LIST }

internal data class ScheduleWidgetLayout(
    val size: SizeF,
    val style: ScheduleWidgetStyle,
    val detailed: Boolean = false,
) {
    val list: Boolean
        get() = style == ScheduleWidgetStyle.STACKED_LIST || style == ScheduleWidgetStyle.COLUMNS_LIST

    val columns: Boolean
        get() = style == ScheduleWidgetStyle.COLUMNS_LIST
}

/** Size thresholds describe content that actually fits, including the user's text size. */
internal class ScheduleWidgetSizing(context: Context) {
    private val resources = context.resources
    private val density = resources.displayMetrics.density
    val padding = dp(R.dimen.schedule_widget_padding)
    val compactPadding = dp(R.dimen.schedule_widget_compact_padding)
    val cardPadding = dp(R.dimen.schedule_widget_card_padding)
    val titleLine = lineHeight(R.dimen.schedule_widget_title_text)
    val bodyLine = lineHeight(R.dimen.schedule_widget_body_text)
    val captionLine = lineHeight(R.dimen.schedule_widget_caption_text)
    private val rowTitleLine = lineHeight(R.dimen.schedule_widget_row_title_text)
    val stripTitleLine = rowTitleLine
    val titlePixels = resources.getDimensionPixelSize(R.dimen.schedule_widget_title_text).toFloat()
    val stripTitlePixels = resources.getDimensionPixelSize(R.dimen.schedule_widget_row_title_text).toFloat()
    val timeColumnWidth = ceil(
        maxOf(textWidth("00:00"), textWidth("待上课")) + padding,
    )
    private val columnLayoutWidth = maxOf(
        240f, 2 * padding + timeColumnWidth + dp(R.dimen.schedule_widget_row_title_text) * 8,
    )

    fun pixels(dp: Float): Int = (dp * density).toInt()

    fun bodyHeight(text: String): Float = lineHeight(R.dimen.schedule_widget_body_text, text)

    fun variants(futureSummary: Boolean): List<ScheduleWidgetLayout> {
        val width = dp(R.dimen.schedule_widget_min_width)
        val minimumHeight = dp(R.dimen.schedule_widget_min_height)
        val twoLines = 2 * compactPadding + stripTitleLine + bodyLine + 6
        val threeLines = twoLines + bodyLine + 2
        val cardHeight = maxOf(
            dp(R.dimen.schedule_widget_default_height),
            2 * cardPadding + captionLine + titleLine + 2 * bodyLine + 8,
        )
        val tallCardHeight = maxOf(cardHeight + 8, 2 * cardPadding + captionLine + 2 * titleLine + 2 * bodyLine + 8)
        val summaryHeight = if (futureSummary) twoLines + padding else 0f
        val headerHeight = bodyLine + captionLine + 6
        val stackedRowHeight = 2 * rowTitleLine + 4 * bodyLine + 18
        val columnsRowHeight = maxOf(3 * bodyLine, 2 * rowTitleLine + 2 * bodyLine + 2) + 14
        val stackedHeight = maxOf(tallCardHeight + 16, 2 * padding + headerHeight + stackedRowHeight + summaryHeight)
        val columnsHeight = maxOf(tallCardHeight + 16, 2 * padding + maxOf(48f, headerHeight) + columnsRowHeight + summaryHeight)
        return listOf(
            ScheduleWidgetLayout(SizeF(width, minimumHeight), ScheduleWidgetStyle.STRIP),
            ScheduleWidgetLayout(SizeF(width, maxOf(minimumHeight + 8, twoLines)), ScheduleWidgetStyle.STRIP),
            ScheduleWidgetLayout(SizeF(width, maxOf(minimumHeight + 16, threeLines)), ScheduleWidgetStyle.STRIP),
            ScheduleWidgetLayout(SizeF(width, cardHeight), ScheduleWidgetStyle.CARD),
            ScheduleWidgetLayout(SizeF(width, tallCardHeight), ScheduleWidgetStyle.CARD),
            ScheduleWidgetLayout(SizeF(width, stackedHeight), ScheduleWidgetStyle.STACKED_LIST),
            ScheduleWidgetLayout(SizeF(columnLayoutWidth, columnsHeight), ScheduleWidgetStyle.COLUMNS_LIST),
            ScheduleWidgetLayout(
                SizeF(width, stackedHeight + stackedRowHeight + 2 * captionLine),
                ScheduleWidgetStyle.STACKED_LIST, detailed = true,
            ),
            ScheduleWidgetLayout(
                SizeF(columnLayoutWidth, columnsHeight + columnsRowHeight + 2 * captionLine),
                ScheduleWidgetStyle.COLUMNS_LIST, detailed = true,
            ),
        )
    }

    // Resource dimensions use Android's SP conversion, including Android 14's
    // nonlinear font scaling. Multiplying breakpoints by fontScale is inaccurate.
    private fun dp(id: Int): Float = resources.getDimension(id) / density

    private fun lineHeight(id: Int, sample: String = "课表 Ag 00:00"): Float {
        val paint = TextPaint().apply {
            textSize = resources.getDimensionPixelSize(id).toFloat()
            typeface = if (id == R.dimen.schedule_widget_title_text || id == R.dimen.schedule_widget_row_title_text) {
                Typeface.DEFAULT_BOLD
            } else {
                Typeface.DEFAULT
            }
        }
        // Chinese fallback fonts can be taller than the Latin font metrics.
        // Measure them as TextView does; otherwise the final line gets clipped.
        val line = StaticLayout.Builder.obtain(sample, 0, sample.length, paint, ceil(paint.measureText(sample)).toInt() + 1)
            .setIncludePad(false).setUseLineSpacingFromFallbacks(true).build()
        return ceil(line.height / density)
    }

    private fun textWidth(value: String): Float = Paint().apply {
        textSize = resources.getDimensionPixelSize(R.dimen.schedule_widget_body_text).toFloat()
    }.measureText(value) / density
}
