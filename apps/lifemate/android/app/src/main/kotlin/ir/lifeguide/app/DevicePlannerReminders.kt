package ir.lifeguide.app

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/** Native authority for reminders belonging only to the separate device-planner APK. */
internal object DevicePlannerReminders {
    const val LEASE_KIND = "device-planner-v1"
    const val MAX_LEASE = 31L * 24 * 60 * 60 * 1000
    private val scope = Regex("^device-planner:v1:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$")
    private val controls = Regex("[\\p{Cc}\\u202a-\\u202e\\u2066-\\u2069]")
    private const val PREFS = "lifeguide_device_planner_reminders_v1"
    private const val ENABLED = "enabled"
    @Volatile private var choiceFailedClosed = false

    fun supported(c: Context) = BuildConfig.DEVICE_PLANNER_ONLY && c.packageName == "ir.lifeguide.app.device"
    fun enabled(c: Context): Boolean {
        if (!supported(c) || choiceFailedClosed) return false
        return try { c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(ENABLED, false) }
        catch (_: Exception) { choiceFailedClosed = true; false }
    }
    @Synchronized fun setEnabled(c: Context, value: Boolean) {
        require(supported(c))
        val stored = try { c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(ENABLED, value).commit() }
        catch (_: Exception) { false }
        choiceFailedClosed = !stored
        // Cancellation still runs when persisting OFF fails. Deactivate preserves the choice.
        if (!value) LocalReminders.deactivate(c)
        if (!stored) throw IllegalStateException("Device reminder choice storage unavailable")
    }
    fun status(c: Context): Map<String, Any?> = LocalReminders.status(c) + ("enabled" to enabled(c))
    fun validScope(value: String) = scope.matches(value)
    fun unsupportedStatus(): Map<String, Any?> = mapOf(
        "supported" to false, "enabled" to false, "permissionGranted" to false, "active" to false,
        "scheduledCount" to 0, "timing" to "approximate", "activeScope" to null,
        "validUntilEpochMs" to null, "exactAlarmSupported" to false, "canScheduleExactAlarms" to false)

    fun validateArguments(args: Map<*, *>, keys: Set<String>) {
        require(args.keys.all { it in keys })
        require(validScope(args["scope"] as? String ?: throw IllegalArgumentException()))
    }

    fun validateNames(args: Map<*, *>) {
        val rows = args["reminders"] as? List<*> ?: throw IllegalArgumentException()
        require(rows.size <= 128)
        for (raw in rows) {
            val row = raw as? Map<*, *> ?: throw IllegalArgumentException()
            val name = (row["companionName"] as? String)?.trim() ?: throw IllegalArgumentException()
            require(name.isNotEmpty() && name.length <= 4096 && !controls.containsMatchIn(name))
            // Android's ICU handles combining marks and emoji clusters at the native boundary.
            val boundaries = if (Build.VERSION.SDK_INT >= 24) {
                android.icu.text.BreakIterator.getCharacterInstance(Locale.ROOT).apply { setText(name) }
            } else null
            var count = 0
            if (boundaries != null) {
                boundaries.first()
                while (boundaries.next() != android.icu.text.BreakIterator.DONE) {
                    require(++count <= 40)
                }
            } else {
                val legacy = java.text.BreakIterator.getCharacterInstance(Locale.ROOT).apply { setText(name) }
                legacy.first()
                while (legacy.next() != java.text.BreakIterator.DONE) {
                    require(++count <= 40)
                }
            }
        }
    }
}

internal class DevicePlannerReminderChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object { const val REQUEST = 8248 }
    private var permissionResult: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (!DevicePlannerReminders.supported(activity)) {
            result.success(DevicePlannerReminders.unsupportedStatus())
            return
        }
        try {
            when (call.method) {
                "setEnabled" -> {
                    val args = call.arguments as? Map<*, *> ?: throw IllegalArgumentException()
                    require(args.keys == setOf("enabled"))
                    DevicePlannerReminders.setEnabled(activity, args["enabled"] as? Boolean ?: throw IllegalArgumentException())
                    result.success(true)
                }
                "activate" -> {
                    val args = call.arguments as? Map<*, *> ?: throw IllegalArgumentException()
                    DevicePlannerReminders.validateArguments(args, setOf("scope", "validUntilEpochMs"))
                    LocalReminders.activateDevicePlanner(activity, args)
                    result.success(true)
                }
                "replace" -> {
                    val args = call.arguments as? Map<*, *> ?: throw IllegalArgumentException()
                    DevicePlannerReminders.validateArguments(args, setOf("scope", "reminders"))
                    DevicePlannerReminders.validateNames(args)
                    LocalReminders.replace(activity, args)
                    result.success(true)
                }
                "suppressPlanItems" -> {
                    val args = call.arguments as? Map<*, *> ?: throw IllegalArgumentException()
                    DevicePlannerReminders.validateArguments(args, setOf("scope", "planItemIds"))
                    LocalReminders.suppress(activity, args)
                    result.success(true)
                }
                "deactivate" -> { LocalReminders.deactivate(activity); result.success(true) }
                "status" -> result.success(DevicePlannerReminders.status(activity))
                "requestPermission" -> {
                    if (Build.VERSION.SDK_INT >= 33 && activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        if (permissionResult != null) { result.error("permission_request_pending", null, null); return }
                        permissionResult = result
                        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST)
                    } else result.success(DevicePlannerReminders.status(activity))
                }
                "openNotificationSettings" -> {
                    require(call.arguments == null)
                    LocalReminders.openNotificationSettings(activity)
                    result.success(true)
                }
                "requestExactAlarmAccess" -> {
                    if (Build.VERSION.SDK_INT >= 31 && !LocalReminders.exact(activity)) {
                        activity.startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:${activity.packageName}")))
                    }
                    result.success(DevicePlannerReminders.status(activity))
                }
                else -> result.notImplemented()
            }
        } catch (_: IllegalArgumentException) { result.error("invalid_device_planner_reminder", null, null) }
        catch (_: Exception) { result.error("device_planner_reminder_unavailable", null, null) }
    }

    fun onPermissionResult(requestCode: Int) {
        if (requestCode != REQUEST) return
        val result = permissionResult ?: return
        permissionResult = null
        try { result.success(DevicePlannerReminders.status(activity)) }
        catch (_: Exception) { result.error("device_planner_reminder_unavailable", null, null) }
    }
}
