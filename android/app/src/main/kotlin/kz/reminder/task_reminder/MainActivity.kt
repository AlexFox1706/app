package kz.reminder.task_reminder

import android.Manifest
import android.annotation.SuppressLint
import android.content.pm.PackageManager
import android.app.Activity
import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "task_reminder/device"
    private val pickSoundRequest = 4711
    private var pendingPickResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        applyLockScreenMode(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        applyLockScreenMode(intent)
        super.onNewIntent(intent)
    }

    /**
     * Поверх экрана блокировки показываемся ТОЛЬКО когда нас открыло
     * уведомление (в т.ч. полноэкранное). Обычный запуск приложения
     * на заблокированном телефоне задачи не покажет.
     */
    private fun applyLockScreenMode(intent: Intent?) {
        if (intent?.action == "SELECT_NOTIFICATION") setShowOverLockScreen(true)
    }

    @Suppress("DEPRECATION")
    private fun setShowOverLockScreen(show: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(show)
            setTurnScreenOn(show)
        } else {
            val flags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            if (show) window.addFlags(flags) else window.clearFlags(flags)
        }
        if (show) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    private fun isKeyguardLocked(): Boolean =
        (getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager).isKeyguardLocked

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickSound" -> pickSound(call.argument<String>("kind"), call.argument<String>("current"), result)
                    "isIgnoringBatteryOptimizations" -> result.success(isIgnoringBattery())
                    "requestIgnoreBatteryOptimizations" -> { requestIgnoreBattery(); result.success(null) }
                    "openAppSettings" -> { openAppSettings(); result.success(null) }
                    "isDeviceLocked" -> result.success(isKeyguardLocked())
                    "canUseFullScreenIntent" -> result.success(
                        if (Build.VERSION.SDK_INT >= 34)
                            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).canUseFullScreenIntent()
                        else true
                    )
                    // Для своих мелодий из памяти телефона нужен доступ к аудио,
                    // иначе система не сможет проиграть выбранный файл.
                    "ensureAudioPermission" -> result.success(ensureAudioPermission())
                    // Экран напоминания закрыт: больше не показываемся поверх блокировки.
                    // Если телефон заблокирован — уходим в фон, чтобы не открыть приложение без пароля.
                    "releaseLockScreen" -> {
                        val locked = isKeyguardLocked()
                        setShowOverLockScreen(false)
                        if (locked) moveTaskToBack(true)
                        result.success(locked)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ---------- Выбор звука ----------

    private fun pickSound(kind: String?, current: String?, result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("busy", "Выбор звука уже открыт", null)
            return
        }
        val type = when (kind) {
            "alarm" -> RingtoneManager.TYPE_ALARM
            "ringtone" -> RingtoneManager.TYPE_RINGTONE
            else -> RingtoneManager.TYPE_NOTIFICATION
        }
        val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
            putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, type)
            putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE, "Звук напоминания")
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
            putExtra(RingtoneManager.EXTRA_RINGTONE_DEFAULT_URI, RingtoneManager.getDefaultUri(type))
            if (current != null) putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, Uri.parse(current))
        }
        pendingPickResult = result
        try {
            startActivityForResult(intent, pickSoundRequest)
        } catch (e: Exception) {
            pendingPickResult = null
            result.error("no_picker", e.message, null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == pickSoundRequest) {
            val result = pendingPickResult
            pendingPickResult = null
            if (resultCode != Activity.RESULT_OK || data == null) {
                result?.success(null)
                return
            }
            val uri: Uri? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                data.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                data.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
            }
            if (uri == null) {
                result?.success(null)
                return
            }
            val title = try {
                RingtoneManager.getRingtone(this, uri)?.getTitle(this) ?: "Звук"
            } catch (e: Exception) {
                "Звук"
            }
            result?.success(mapOf("uri" to uri.toString(), "title" to title))
            return
        }
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun ensureAudioPermission(): Boolean {
        val perm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
            Manifest.permission.READ_MEDIA_AUDIO
        else
            Manifest.permission.READ_EXTERNAL_STORAGE
        if (checkSelfPermission(perm) == PackageManager.PERMISSION_GRANTED) return true
        requestPermissions(arrayOf(perm), 4712)
        return false
    }

    // ---------- Батарея и настройки ----------

    private fun isIgnoringBattery(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    @SuppressLint("BatteryLife")
    private fun requestIgnoreBattery() {
        try {
            startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))
            )
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        }
    }

    private fun openAppSettings() {
        startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }
}
