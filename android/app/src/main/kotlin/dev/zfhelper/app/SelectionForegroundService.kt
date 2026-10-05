package dev.zfhelper.app

import android.annotation.SuppressLint
import android.app.ForegroundServiceStartNotAllowedException
import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import android.os.PowerManager

private const val NOTIFICATION_ID = 4101
private const val STOP_ACTION = "dev.zfhelper.app.STOP_SELECTION"

class SelectionForegroundService : Service() {
    private val host: SelectionRuntimeHost
        get() = (application as ZfHelperApplication).selectionRuntime
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP_ACTION) {
            host.stopFromNotification()
            stopFromHost()
            return START_NOT_STICKY
        }
        val count = host.requestedWorkCount()
        if (count == 0) {
            stopFromHost()
            return START_NOT_STICKY
        }
        try {
            updateWorkCount(count)
            holdCpuWhileRunning()
            host.serviceStarted(this)
        } catch (_: ForegroundServiceStartNotAllowedException) {
            host.serviceFailed("foreground_service_not_allowed", "Android 暂不允许后台同步，捡漏未开始")
            stopFromHost()
        } catch (_: SecurityException) {
            host.serviceFailed("foreground_service_permission", "系统未允许后台运行所需的权限，捡漏未开始")
            stopFromHost()
        } catch (_: RuntimeException) {
            host.serviceFailed("foreground_service_failed", "后台运行宿主启动失败，捡漏未开始")
            stopFromHost()
        }
        // A killed process never restarts school requests by itself.
        return START_NOT_STICKY
    }

    fun updateWorkCount(count: Int) {
        startForeground(
            NOTIFICATION_ID,
            notification(count),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
        )
    }

    @SuppressLint("WakelockTimeout")
    private fun holdCpuWhileRunning() {
        // Only the foreground service owns this lock. Stop, timeout and destroy
        // all release it; the service does not own another task executor.
        if (wakeLock?.isHeld == true) return
        wakeLock = requireNotNull(getSystemService(PowerManager::class.java))
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ZFHelper:selection")
            .apply {
                setReferenceCounted(false)
                acquire()
            }
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        host.serviceTimedOut()
        stopFromHost()
    }

    fun stopFromHost() {
        releaseCpu()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        releaseCpu()
        host.serviceDestroyed(this)
        super.onDestroy()
    }

    private fun releaseCpu() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }

    private fun notification(count: Int): Notification {
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stop = PendingIntent.getService(
            this,
            1,
            Intent(this, SelectionForegroundService::class.java).setAction(STOP_ACTION),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Builder(this, SELECTION_NOTIFICATION_CHANNEL)
            .setSmallIcon(android.R.drawable.ic_popup_sync)
            .setContentTitle("捡漏正在运行")
            .setContentText("正在检查 $count 项捡漏的课程余量")
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
            .addAction(Notification.Action.Builder(null, "停止捡漏", stop).build())
            .build()
    }
}
