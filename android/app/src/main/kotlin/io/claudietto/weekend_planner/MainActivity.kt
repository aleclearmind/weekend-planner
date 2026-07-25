package io.claudietto.weekend_planner

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.CalendarContract.Calendars
import android.provider.CalendarContract.Instances
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingCalendarPermission: MethodChannel.Result? = null
    private var pendingExport: MethodChannel.Result? = null
    private var pendingExportContent: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PLATFORM_CHANNEL,
        ).setMethodCallHandler(::handlePlatformCall)
    }

    private fun handlePlatformCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "exportDatabase" -> exportDatabase(call, result)
            "openUrl" -> result.success(openUrl(call.argument<String>("url")))
            "openOsmAnd" -> result.success(openOsmAnd(call))
            "hasCalendarAccess" -> result.success(hasCalendarPermission())
            "requestCalendarAccess" -> requestCalendarAccess(result)
            "queryCalendars" -> queryCalendars(result)
            "queryCalendarEvents" -> queryCalendarEvents(call, result)
            else -> result.notImplemented()
        }
    }

    private fun exportDatabase(call: MethodCall, result: MethodChannel.Result) {
        if (pendingExport != null) {
            result.error("export_in_progress", "Another export is already open.", null)
            return
        }
        val content = call.argument<String>("content")
        if (content == null) {
            result.error("missing_content", "No database content was provided.", null)
            return
        }
        pendingExport = result
        pendingExportContent = content
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/json"
            putExtra(
                Intent.EXTRA_TITLE,
                call.argument<String>("filename") ?: "weekend-planner.json",
            )
        }
        startActivityForResult(intent, EXPORT_REQUEST_CODE)
    }

    @Deprecated("Deprecated in Android; retained for FlutterActivity compatibility.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != EXPORT_REQUEST_CODE) return
        val result = pendingExport
        val content = pendingExportContent
        pendingExport = null
        pendingExportContent = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result?.error("export_cancelled", "The database export was cancelled.", null)
            return
        }
        try {
            contentResolver.openOutputStream(data.data!!)?.use { stream ->
                stream.write(content.orEmpty().toByteArray(Charsets.UTF_8))
            } ?: throw IllegalStateException("Could not open the selected file.")
            result?.success(null)
        } catch (error: Exception) {
            result?.error("export_failed", error.message, error.toString())
        }
    }

    private fun openUrl(value: String?): Boolean {
        if (value.isNullOrBlank()) return false
        return try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(value)))
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun openOsmAnd(call: MethodCall): Boolean {
        val latitude = call.argument<Number>("latitude")?.toDouble() ?: return false
        val longitude = call.argument<Number>("longitude")?.toDouble() ?: return false
        val label = call.argument<String>("label").orEmpty()
        val query = Uri.encode("$latitude,$longitude($label)")
        val geoUri = Uri.parse("geo:$latitude,$longitude?q=$query")
        for (packageName in listOf("net.osmand.plus", "net.osmand")) {
            try {
                startActivity(
                    Intent(Intent.ACTION_VIEW, geoUri).apply {
                        setPackage(packageName)
                    },
                )
                return true
            } catch (_: Exception) {
                // Try the other OsmAnd package before falling back to its map site.
            }
        }
        val webUri = Uri.Builder()
            .scheme("https")
            .authority("osmand.net")
            .path("/map")
            .appendQueryParameter("pin", "$latitude,$longitude")
            .appendQueryParameter("name", label)
            .build()
        return openUrl(webUri.toString())
    }

    private fun hasCalendarPermission(): Boolean =
        checkSelfPermission(Manifest.permission.READ_CALENDAR) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestCalendarAccess(result: MethodChannel.Result) {
        if (hasCalendarPermission()) {
            result.success(true)
            return
        }
        if (pendingCalendarPermission != null) {
            result.error(
                "permission_in_progress",
                "A calendar permission request is already open.",
                null,
            )
            return
        }
        pendingCalendarPermission = result
        requestPermissions(
            arrayOf(Manifest.permission.READ_CALENDAR),
            CALENDAR_PERMISSION_REQUEST_CODE,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != CALENDAR_PERMISSION_REQUEST_CODE) return
        val granted =
            grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingCalendarPermission?.success(granted)
        pendingCalendarPermission = null
    }

    private fun queryCalendars(result: MethodChannel.Result) {
        if (!hasCalendarPermission()) {
            result.error("calendar_permission", "Calendar access is not granted.", null)
            return
        }
        try {
            val projection = arrayOf(
                Calendars._ID,
                Calendars.CALENDAR_DISPLAY_NAME,
                Calendars.ACCOUNT_NAME,
            )
            val calendars = mutableListOf<Map<String, Any>>()
            contentResolver.query(
                Calendars.CONTENT_URI,
                projection,
                "${Calendars.VISIBLE} = 1",
                null,
                "${Calendars.CALENDAR_DISPLAY_NAME} COLLATE NOCASE ASC",
            )?.use { cursor ->
                val idIndex = cursor.getColumnIndexOrThrow(Calendars._ID)
                val nameIndex =
                    cursor.getColumnIndexOrThrow(Calendars.CALENDAR_DISPLAY_NAME)
                val accountIndex = cursor.getColumnIndexOrThrow(Calendars.ACCOUNT_NAME)
                while (cursor.moveToNext()) {
                    calendars.add(
                        mapOf(
                            "id" to cursor.getLong(idIndex).toString(),
                            "name" to (
                                cursor.getString(nameIndex) ?: "(unnamed calendar)"
                            ),
                            "accountName" to (cursor.getString(accountIndex) ?: ""),
                        ),
                    )
                }
            }
            result.success(calendars)
        } catch (error: Exception) {
            result.error("calendar_list", error.message, error.toString())
        }
    }

    private fun queryCalendarEvents(call: MethodCall, result: MethodChannel.Result) {
        if (!hasCalendarPermission()) {
            result.error("calendar_permission", "Calendar access is not granted.", null)
            return
        }
        val start = call.argument<Number>("start")?.toLong()
        val end = call.argument<Number>("end")?.toLong()
        if (start == null || end == null || end <= start) {
            result.error("invalid_window", "Invalid calendar query window.", null)
            return
        }
        val calendarIds = call.argument<List<String>>("calendarIds")
            ?.mapNotNull { it.toLongOrNull() }
            .orEmpty()
        if (calendarIds.isEmpty()) {
            result.success(emptyList<Map<String, Any>>())
            return
        }
        try {
            val uriBuilder = Instances.CONTENT_URI.buildUpon()
            android.content.ContentUris.appendId(uriBuilder, start)
            android.content.ContentUris.appendId(uriBuilder, end)
            val projection = arrayOf(
                Instances.TITLE,
                Instances.BEGIN,
                Instances.END,
                Instances.CALENDAR_ID,
            )
            val placeholders = calendarIds.joinToString(",") { "?" }
            val events = mutableListOf<Map<String, Any>>()
            contentResolver.query(
                uriBuilder.build(),
                projection,
                "${Instances.CALENDAR_ID} IN ($placeholders)",
                calendarIds.map(Long::toString).toTypedArray(),
                "${Instances.BEGIN} ASC",
            )?.use { cursor ->
                val titleIndex = cursor.getColumnIndexOrThrow(Instances.TITLE)
                val startIndex = cursor.getColumnIndexOrThrow(Instances.BEGIN)
                val endIndex = cursor.getColumnIndexOrThrow(Instances.END)
                val calendarIndex =
                    cursor.getColumnIndexOrThrow(Instances.CALENDAR_ID)
                while (cursor.moveToNext()) {
                    events.add(
                        mapOf(
                            "title" to (cursor.getString(titleIndex) ?: "(untitled event)"),
                            "start" to cursor.getLong(startIndex),
                            "end" to cursor.getLong(endIndex),
                            "calendarId" to cursor.getLong(calendarIndex).toString(),
                        ),
                    )
                }
            }
            result.success(events)
        } catch (error: Exception) {
            result.error("calendar_query", error.message, error.toString())
        }
    }

    companion object {
        private const val PLATFORM_CHANNEL =
            "io.claudietto.weekend_planner/platform"
        private const val CALENDAR_PERMISSION_REQUEST_CODE = 4101
        private const val EXPORT_REQUEST_CODE = 4102
    }
}
