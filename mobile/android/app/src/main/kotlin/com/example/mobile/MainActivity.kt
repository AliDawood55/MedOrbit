package com.example.mobile

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

private const val REPORT_FILE_PICKER_CHANNEL = "medorbit/report_file_picker"
private const val PICK_REPORT_FILE_REQUEST_CODE = 9201
private val ALLOWED_REPORT_EXTENSIONS = setOf("pdf", "png", "jpg", "jpeg")

/**
 * Report Summarizer's PDF/image picker, wired directly into MainActivity
 * rather than as a standalone plugin — it is used from exactly one screen
 * and isn't meant to be reused elsewhere.
 *
 * This replaces the `file_picker` package, removed because its bundled
 * Android `build.gradle` depended on the long-retired `jcenter()`
 * repository and could not be made to build against this project's
 * Gradle/AGP setup. Everything else that picks media (Profile's avatar
 * upload) still goes through `image_picker`, whose own Android plugin is
 * unaffected and untouched here.
 *
 * Flow: `ACTION_OPEN_DOCUMENT` returns a `content://` URI, which is only
 * valid for the lifetime of this grant — Dio's `MultipartFile.fromFile`
 * needs a real filesystem path, so the picked document is copied into
 * `cacheDir/report_uploads/` immediately and that path is what's returned
 * to Dart, never the URI itself.
 */
class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, REPORT_FILE_PICKER_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "pickReportFile") {
                    startReportFilePick(result)
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun startReportFilePick(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("ALREADY_ACTIVE", "A file pick is already in progress.", null)
            return
        }

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf("application/pdf", "image/png", "image/jpeg")
            )
        }

        try {
            pendingResult = result
            startActivityForResult(intent, PICK_REPORT_FILE_REQUEST_CODE)
        } catch (e: Exception) {
            pendingResult = null
            result.error("PICKER_UNAVAILABLE", "Could not open the file picker.", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_REPORT_FILE_REQUEST_CODE) return

        val result = pendingResult ?: return
        pendingResult = null

        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            // User backed out of the picker — not an error.
            result.success(null)
            return
        }

        try {
            val picked = copyToReportCache(uri)
            if (picked == null) {
                result.error("NO_STREAM", "Could not read the selected file.", null)
            } else {
                result.success(
                    mapOf(
                        "path" to picked.path,
                        "name" to picked.name,
                        "sizeBytes" to picked.sizeBytes
                    )
                )
            }
        } catch (e: Exception) {
            result.error("PICK_FAILED", e.message, null)
        }
    }

    private data class CachedReportFile(val path: String, val name: String, val sizeBytes: Long)

    /**
     * Copies [uri]'s bytes into `cacheDir/report_uploads/<random>.<ext>` and
     * returns that real path alongside the document's original display name
     * (used only for the UI label and the multipart `filename` field, never
     * as the on-disk filename — an arbitrary user-supplied name isn't
     * trusted as a filesystem path component).
     *
     * Only one report is ever "selected" in the app's UI at a time, so the
     * simplest correct cleanup is clearing this directory before writing the
     * new pick rather than tracking file age.
     */
    private fun copyToReportCache(uri: Uri): CachedReportFile? {
        val displayName = queryDisplayName(uri)
        val extension = extensionFromName(displayName)
            ?: extensionFromMimeType(contentResolver.getType(uri))
            ?: "bin"

        val dir = File(cacheDir, "report_uploads")
        dir.deleteRecursively()
        dir.mkdirs()
        val destination = File(dir, "report_${UUID.randomUUID()}.$extension")

        val input = contentResolver.openInputStream(uri) ?: return null
        var bytesCopied = 0L
        input.use { stream ->
            FileOutputStream(destination).use { output ->
                bytesCopied = stream.copyTo(output)
            }
        }

        val name = when {
            displayName.isNullOrBlank() -> "report.$extension"
            displayName.contains('.') -> displayName
            else -> "$displayName.$extension"
        }

        return CachedReportFile(path = destination.absolutePath, name = name, sizeBytes = bytesCopied)
    }

    private fun queryDisplayName(uri: Uri): String? {
        return contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (!cursor.moveToFirst()) return@use null
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index < 0) null else cursor.getString(index)
            }
    }

    private fun extensionFromName(name: String?): String? {
        if (name.isNullOrBlank() || !name.contains('.')) return null
        val extension = name.substringAfterLast('.').lowercase()
        return if (extension in ALLOWED_REPORT_EXTENSIONS) extension else null
    }

    private fun extensionFromMimeType(mimeType: String?): String? = when (mimeType) {
        "application/pdf" -> "pdf"
        "image/png" -> "png"
        "image/jpeg" -> "jpg"
        else -> null
    }
}
