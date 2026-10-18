package ir.lifeguide.app

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/** Device-only generic reminders. Never persist task text, credentials or tokens here. */
internal object LocalReminders {
    private const val PREFS = "lifeguide_local_reminders_v1"
    private const val KEY = "active"
    private const val CHANNEL = "lifeguide_personal_plan_v1"
    private const val ACTION = "ir.lifeguide.app.LOCAL_REMINDER"
    private const val MAX_LEASE = 24L * 60 * 60 * 1000
    private val uuid = Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$")
    private val controls = Regex("[\\p{Cc}\\u202a-\\u202e\\u2066-\\u2069]")
    private var failedClosed = false
    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private fun alarms(c: Context) = c.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    private fun notifications(c: Context) = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    private fun read(c: Context): JSONObject? {
        if (failedClosed) return null
        val raw = prefs(c).getString(KEY, null) ?: return null
        return try { JSONObject(raw) } catch (_: Exception) { failedClosed = true; notifications(c).cancelAll(); null }
    }
    private fun store(c: Context, state: JSONObject) {
        if (!prefs(c).edit().putString(KEY, state.toString()).commit()) {
            failedClosed = true
            throw IllegalStateException("Local reminder storage unavailable")
        }
        failedClosed = false
    }
    private fun leased(s: JSONObject, now: Long = System.currentTimeMillis()) =
        s.optString("scope").isNotEmpty() && s.optString("generation").isNotEmpty() &&
        s.optLong("issuedAtEpochMs") <= now && s.optLong("validUntilEpochMs") > now &&
        s.optLong("validUntilEpochMs") - s.optLong("issuedAtEpochMs") in 1..MAX_LEASE
    fun permission(c: Context) =
        (Build.VERSION.SDK_INT < 33 || c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
        notifications(c).areNotificationsEnabled() &&
        (Build.VERSION.SDK_INT < 26 || notifications(c).getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE)
    fun exact(c: Context) = Build.VERSION.SDK_INT < 31 || alarms(c).canScheduleExactAlarms()
    private fun channel(c: Context) {
        if (Build.VERSION.SDK_INT >= 26) notifications(c).createNotificationChannel(
            NotificationChannel(CHANNEL, "یادآوری برنامهٔ شخصی", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "زمان اعلان به مجوز، باتری و تنظیمات دستگاه وابسته است."
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
                enableVibration(true)
                setSound(Settings.System.DEFAULT_NOTIFICATION_URI, null)
            })
    }
    private fun pending(c: Context, generation: String, id: String) = PendingIntent.getBroadcast(c, 0,
        Intent(c, LocalReminderReceiver::class.java).apply {
            action = ACTION
            data = Uri.Builder().scheme("lifeguide-reminder").authority("alarm").appendPath(generation).appendPath(id).build()
        }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    private fun cancelOne(c: Context, generation: String, id: String) {
        val alarm = pending(c, generation, id)
        alarms(c).cancel(alarm)
        alarm.cancel()
        notifications(c).cancel("lifeguide-plan:$id", 1)
    }
    private fun cancel(c: Context, s: JSONObject?) {
        if (s != null) {
            val rows = s.optJSONArray("reminders") ?: JSONArray()
            for (i in 0 until rows.length()) rows.optJSONObject(i)?.let { cancelOne(c, s.optString("generation"), it.optString("id")) }
            cancelOne(c, s.optString("generation"), "expiry")
        }
        notifications(c).cancelAll()
    }
    @Synchronized fun deactivate(c: Context) {
        val old = read(c)
        failedClosed = true
        cancel(c, old)
        if (!prefs(c).edit().remove(KEY).commit()) throw IllegalStateException("Local reminders could not be cleared")
        failedClosed = false
    }
    private fun expire(c: Context, s: JSONObject) {
        if (s.optBoolean("deliveryExpired")) return
        cancel(c, s)
        store(c, JSONObject(s.toString()).put("generation", UUID.randomUUID().toString()).put("deliveryExpired", true).put("reminders", JSONArray()))
    }
    @Synchronized fun activate(c: Context, args: Map<*, *>) {
        val scope = args["scope"] as? String ?: throw IllegalArgumentException()
        val until = (args["validUntilEpochMs"] as? Number)?.toLong() ?: throw IllegalArgumentException()
        val now = System.currentTimeMillis()
        require(scope.isNotEmpty() && scope.length <= 1024 && !controls.containsMatchIn(scope))
        require(until > now && until - now <= MAX_LEASE)
        val old = read(c)
        val rows = if (old != null && old.optString("scope") == scope && leased(old, now)) old.optJSONArray("reminders") ?: JSONArray() else JSONArray()
        val next = JSONObject().put("scope", scope).put("generation", UUID.randomUUID().toString()).put("issuedAtEpochMs", now)
            .put("validUntilEpochMs", until).put("reminders", rows)
        cancel(c, old)
        try { store(c, next); schedule(c, next) } catch (error: Exception) { deactivate(c); throw error }
    }
    @Synchronized fun replace(c: Context, args: Map<*, *>) {
        val old = read(c) ?: throw IllegalStateException("No reminder scope")
        require(old.optString("scope") == args["scope"] && leased(old))
        val raw = args["reminders"] as? List<*> ?: throw IllegalArgumentException()
        require(raw.size <= 128)
        val ids = mutableSetOf<String>()
        val rows = JSONArray()
        val now = System.currentTimeMillis()
        for (rawRow in raw) {
            val row = rawRow as? Map<*, *> ?: throw IllegalArgumentException()
            val id = row["id"] as? String ?: throw IllegalArgumentException()
            val plan = row["planItemId"] as? String ?: throw IllegalArgumentException()
            val at = (row["scheduledAtEpochMs"] as? Number)?.toLong() ?: throw IllegalArgumentException()
            val name = (row["companionName"] as? String)?.trim() ?: throw IllegalArgumentException()
            require(uuid.matches(id) && uuid.matches(plan) && ids.add(id))
            // Dart validates <=40 graphemes; UTF-16 bound defends this native boundary.
            require(name.isNotEmpty() && name.length <= 4096 && !controls.containsMatchIn(name))
            require(row.keys.all { it in setOf("id", "planItemId", "scheduledAtEpochMs", "companionName") })
            if (at <= now || at > old.getLong("validUntilEpochMs")) continue
            rows.put(JSONObject().put("id", id).put("planItemId", plan).put("scheduledAtEpochMs", at).put("companionName", name))
        }
        val next = JSONObject(old.toString()).put("generation", UUID.randomUUID().toString()).put("reminders", rows)
        cancel(c, old)
        try { store(c, next); schedule(c, next) } catch (error: Exception) { deactivate(c); throw error }
    }
    @Synchronized fun suppress(c: Context, args: Map<*, *>) {
        val state = read(c) ?: return
        require(state.optString("scope") == args["scope"])
        val ids = args["planItemIds"] as? List<*> ?: throw IllegalArgumentException()
        require(ids.size <= 128 && ids.all { it is String && uuid.matches(it) })
        val old = state.optJSONArray("reminders") ?: JSONArray()
        val remaining = JSONArray()
        val removed = mutableListOf<String>()
        for (i in 0 until old.length()) {
            val row = old.optJSONObject(i) ?: continue
            if (ids.contains(row.optString("planItemId"))) removed.add(row.optString("id")) else remaining.put(row)
        }
        // Receiver sees removed IDs before any OS cancellation race.
        store(c, JSONObject(state.toString()).put("reminders", remaining))
        for (id in removed) cancelOne(c, state.optString("generation"), id)
    }
    private fun setAlarm(c: Context, at: Long, alarm: PendingIntent) {
        if (exact(c)) {
            try { alarms(c).setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, alarm); return }
            catch (_: SecurityException) { /* Permission can be revoked between check and call. */ }
        }
        alarms(c).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, alarm)
    }
    private fun schedule(c: Context, s: JSONObject) {
        if (!leased(s) || !permission(c)) return
        channel(c)
        val rows = s.optJSONArray("reminders") ?: JSONArray()
        val now = System.currentTimeMillis()
        for (i in 0 until rows.length()) {
            val row = rows.optJSONObject(i) ?: continue
            val at = row.optLong("scheduledAtEpochMs")
            if (at <= now || at > s.optLong("validUntilEpochMs") || row.optBoolean("delivered")) continue
            setAlarm(c, at, pending(c, s.getString("generation"), row.getString("id")))
        }
        setAlarm(c, s.getLong("validUntilEpochMs"), pending(c, s.getString("generation"), "expiry"))
    }
    @Synchronized fun restore(c: Context) {
        val state = read(c) ?: return
        if (!leased(state) || !permission(c)) { expire(c, state); return }
        schedule(c, state)
    }
    @Synchronized fun status(c: Context): Map<String, Any?> {
        var state = read(c)
        if (state != null && (!leased(state) || !permission(c))) { expire(c, state); state = read(c) }
        val rows = state?.optJSONArray("reminders") ?: JSONArray()
        val now = System.currentTimeMillis()
        var count = 0
        for (i in 0 until rows.length()) if ((rows.optJSONObject(i)?.optLong("scheduledAtEpochMs") ?: 0) > now) count++
        return mapOf("supported" to true, "permissionGranted" to permission(c), "active" to (state != null), "scheduledCount" to count,
            "timing" to if (exact(c)) "exact" else "approximate", "activeScope" to state?.optString("scope"),
            "validUntilEpochMs" to state?.optLong("validUntilEpochMs"), "exactAlarmSupported" to (Build.VERSION.SDK_INT >= 31), "canScheduleExactAlarms" to exact(c))
    }
    @Synchronized fun deliver(c: Context, intent: Intent) {
        if (intent.action != ACTION) return
        val parts = intent.data?.pathSegments ?: return
        if (parts.size != 2) return
        val state = read(c) ?: return
        if (parts[0] != state.optString("generation")) return
        if (!leased(state) || !permission(c) || parts[1] == "expiry") { expire(c, state); return }
        val rows = state.optJSONArray("reminders") ?: return
        val now = System.currentTimeMillis()
        for (i in 0 until rows.length()) {
            val row = rows.optJSONObject(i) ?: continue
            if (row.optString("id") != parts[1] || row.optBoolean("delivered")) continue
            val at = row.optLong("scheduledAtEpochMs")
            if (now < at || now - at > 30L * 60 * 1000) return // Drop stale alarms, never claim stale tasks are current.
            row.put("delivered", true)
            store(c, state)
            channel(c)
            // Open authenticated app home; no private route/title is carried by the tap.
            val open = Intent(c, MainActivity::class.java).apply {
                action = Intent.ACTION_MAIN; addCategory(Intent.CATEGORY_LAUNCHER)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                data = Uri.Builder().scheme("lifeguide-reminder").authority("open").appendPath(row.getString("id")).build()
            }
            val tap = PendingIntent.getActivity(c, 0, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            fun builder() = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(c, CHANNEL) else Notification.Builder(c)
            val text = "برای دیدن برنامهٔ شخصی، لایف‌گاید را باز کنید."
            val notification = builder().setSmallIcon(R.drawable.lifemate_logo).setContentTitle(row.getString("companionName"))
                .setContentText(text).setContentIntent(tap).setAutoCancel(true).setVisibility(Notification.VISIBILITY_PRIVATE)
                .setPublicVersion(builder().setSmallIcon(R.drawable.lifemate_logo).setContentTitle("LifeGuide").setContentText(text).build())
                .setCategory(Notification.CATEGORY_REMINDER).apply {
                    if (Build.VERSION.SDK_INT < 26) setDefaults(Notification.DEFAULT_SOUND or Notification.DEFAULT_VIBRATE)
                }.build()
            notifications(c).notify("lifeguide-plan:${row.getString("id")}", 1, notification)
            return
        }
    }
}

class LocalReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            when (intent.action) {
                Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED, Intent.ACTION_TIME_CHANGED,
                Intent.ACTION_TIMEZONE_CHANGED, AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED -> LocalReminders.restore(context)
                else -> LocalReminders.deliver(context, intent)
            }
        } catch (_: Exception) { try { LocalReminders.deactivate(context) } catch (_: Exception) { } }
    }
}

internal class LocalReminderChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object { const val REQUEST = 8247 }
    private var permissionResult: MethodChannel.Result? = null
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "activate" -> { LocalReminders.activate(activity, call.arguments as? Map<*, *> ?: throw IllegalArgumentException()); result.success(true) }
                "replace" -> { LocalReminders.replace(activity, call.arguments as? Map<*, *> ?: throw IllegalArgumentException()); result.success(true) }
                "suppressPlanItems" -> { LocalReminders.suppress(activity, call.arguments as? Map<*, *> ?: throw IllegalArgumentException()); result.success(true) }
                "deactivate" -> { LocalReminders.deactivate(activity); result.success(true) }
                "status" -> result.success(LocalReminders.status(activity))
                "requestPermission" -> {
                    if (Build.VERSION.SDK_INT >= 33 && activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        if (permissionResult != null) { result.error("permission_request_pending", null, null); return }
                        permissionResult = result
                        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST)
                    } else result.success(LocalReminders.status(activity))
                }
                "requestExactAlarmAccess" -> {
                    if (Build.VERSION.SDK_INT >= 31 && !LocalReminders.exact(activity)) {
                        activity.startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:${activity.packageName}")))
                    }
                    result.success(LocalReminders.status(activity))
                }
                else -> result.notImplemented()
            }
        } catch (_: IllegalArgumentException) { result.error("invalid_local_reminder", null, null) }
        catch (_: Exception) { result.error("local_reminder_unavailable", null, null) }
    }
    fun onPermissionResult(requestCode: Int) {
        if (requestCode != REQUEST) return
        val result = permissionResult ?: return
        permissionResult = null
        try { result.success(LocalReminders.status(activity)) }
        catch (_: Exception) { result.error("local_reminder_unavailable", null, null) }
    }
}
