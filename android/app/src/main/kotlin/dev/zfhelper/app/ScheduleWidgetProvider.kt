package dev.zfhelper.app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.os.Bundle

class ScheduleWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = refresh(context)

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) = refresh(context)

    override fun onDisabled(context: Context) = refresh(context)

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            SCHEDULE_WIDGET_REFRESH,
            SCHEDULE_WIDGET_BOUNDARY,
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_LOCALE_CHANGED -> refresh(context)
            else -> super.onReceive(context, intent)
        }
    }

    private fun refresh(context: Context) {
        val pending = goAsync()
        // Accessing this host does not instantiate the application's lazy FlutterEngine.
        (context.applicationContext as ZfHelperApplication).scheduleWidgets.refreshInBackground {
            pending.finish()
        }
    }
}
