package dev.zfhelper.app

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class ScheduleIslandReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == NotificationManager.ACTION_NOTIFICATION_CHANNEL_BLOCK_STATE_CHANGED &&
            intent.getStringExtra(NotificationManager.EXTRA_NOTIFICATION_CHANNEL_ID) != ISLAND_CHANNEL_ID) return
        val pending = goAsync()
        (context.applicationContext as ZfHelperApplication).scheduleWidgets.receiveIslandEvent(intent) {
            pending.finish()
        }
    }
}
