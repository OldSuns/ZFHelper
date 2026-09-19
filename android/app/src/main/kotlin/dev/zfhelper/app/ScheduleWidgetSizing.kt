package dev.zfhelper.app

import android.content.Context
import android.graphics.Paint
import android.graphics.Typeface
import android.text.StaticLayout
import android.text.TextPaint
import android.util.SizeF
import kotlin.math.ceil

internal enum class ScheduleWidgetStyle { NEXT, CARD, TODAY_LIST, TWO_DAY, WEEK }

internal data class ScheduleWidgetLayout(
    val size: SizeF,
    val style: ScheduleWidgetStyle,
    val detailed: Boolean = false,
)

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
    val timeColumnWidth = ceil(maxOf(textWidth("00:00"), textWidth("待上课")) + padding)
    val headerHeight = bodyLine + captionLine + 6
    val compactRowHeight = rowTitleLine + bodyLine + 12

    fun pixels(dp: Float): Int = (dp * density).toInt()

    fun bodyHeight(text: String): Float = lineHeight(R.dimen.schedule_widget_body_text, text)

    fun variants(): List<ScheduleWidgetLayout> {
        val minimumWidth = dp(R.dimen.schedule_widget_min_width)
        // The first responsive breakpoint covers every launcher-reported narrow width.
        // Some launchers subtract host padding and report less than minResizeWidth.
        val narrowWidth = 1f
        val minimumHeight = dp(R.dimen.schedule_widget_min_height)
        val twoLines = 2 * compactPadding + stripTitleLine + bodyLine + 6
        val threeLines = twoLines + bodyLine + 2
        val cardHeight = maxOf(
            dp(R.dimen.schedule_widget_default_height),
            2 * cardPadding + captionLine + titleLine + 2 * bodyLine + 8,
        )
        val tallCardHeight = maxOf(
            cardHeight + 8,
            2 * cardPadding + captionLine + 2 * titleLine + 2 * bodyLine + 8,
        )
        val todayHeight = maxOf(
            tallCardHeight + 16,
            2 * padding + headerHeight + 2 * rowTitleLine + 4 * bodyLine + 18,
        )
        val twoDayWidth = maxOf(300f, 2 * minimumWidth + 3 * padding)
        val twoDayHeight = maxOf(150f, 2 * padding + headerHeight + 2 * compactRowHeight + captionLine + 8)
        val weekWidth = maxOf(280f, twoDayWidth)
        val weekHeight = maxOf(
            260f,
            2 * padding + maxOf(48f, headerHeight) + 7 * maxOf(28f, bodyLine + 6),
        )
        return listOf(
            ScheduleWidgetLayout(SizeF(narrowWidth, minimumHeight), ScheduleWidgetStyle.NEXT),
            ScheduleWidgetLayout(SizeF(narrowWidth, maxOf(minimumHeight + 8, twoLines)), ScheduleWidgetStyle.NEXT),
            ScheduleWidgetLayout(SizeF(narrowWidth, maxOf(minimumHeight + 16, threeLines)), ScheduleWidgetStyle.NEXT),
            ScheduleWidgetLayout(SizeF(narrowWidth, cardHeight), ScheduleWidgetStyle.CARD),
            ScheduleWidgetLayout(SizeF(narrowWidth, tallCardHeight), ScheduleWidgetStyle.CARD),
            ScheduleWidgetLayout(SizeF(narrowWidth, todayHeight), ScheduleWidgetStyle.TODAY_LIST),
            ScheduleWidgetLayout(SizeF(twoDayWidth, twoDayHeight), ScheduleWidgetStyle.TWO_DAY),
            ScheduleWidgetLayout(
                SizeF(narrowWidth, todayHeight + compactRowHeight + 2 * captionLine),
                ScheduleWidgetStyle.TODAY_LIST,
                detailed = true,
            ),
            ScheduleWidgetLayout(SizeF(weekWidth, weekHeight), ScheduleWidgetStyle.WEEK, detailed = true),
        )
    }

    fun twoDayRowLimit(height: Float): Int =
        ((height - 2 * padding - headerHeight - captionLine - 16) / compactRowHeight)
            .toInt().coerceIn(1, 4)

    // Resource dimensions use Android's SP conversion, including Android 14's
    // nonlinear font scaling. Multiplying breakpoints by fontScale is inaccurate.
    private fun dp(id: Int): Float = resources.getDimension(id) / density

    private fun lineHeight(id: Int, sample: String = "课表 Ag 00:00"): Float {
        val paint = TextPaint().apply {
            textSize = resources.getDimensionPixelSize(id).toFloat()
            typeface = if (
                id == R.dimen.schedule_widget_title_text ||
                id == R.dimen.schedule_widget_row_title_text
            ) {
                Typeface.DEFAULT_BOLD
            } else {
                Typeface.DEFAULT
            }
        }
        // Chinese fallback fonts can be taller than the Latin font metrics.
        val line = StaticLayout.Builder.obtain(
            sample,
            0,
            sample.length,
            paint,
            ceil(paint.measureText(sample)).toInt() + 1,
        ).setIncludePad(false).setUseLineSpacingFromFallbacks(true).build()
        return ceil(line.height / density)
    }

    private fun textWidth(value: String): Float = Paint().apply {
        textSize = resources.getDimensionPixelSize(R.dimen.schedule_widget_body_text).toFloat()
    }.measureText(value) / density
}
