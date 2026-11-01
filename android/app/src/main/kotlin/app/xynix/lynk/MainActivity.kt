package app.xynix.lynk

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Lets the user choose a download folder and writes finished files into it.
 *
 * Android's scoped storage does not let the app write into a public folder by
 * path, so the folder is picked once through the storage access framework and
 * the grant is kept. Every later download is copied into that tree.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "lynk/storage"
    private val pickRequestCode = 0x5949
    private var pendingPick: MethodChannel.Result? = null

    private companion object {
        /** The longest name most filesystems accept, in UTF-8 bytes. */
        const val MAX_NAME_BYTES = 255
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickFolder" -> pickFolder(result)
                    "publish" -> publish(
                        treeUri = call.argument<String>("treeUri"),
                        sourcePath = call.argument<String>("sourcePath"),
                        fileName = call.argument<String>("fileName"),
                        mimeType = call.argument<String>("mimeType"),
                        result = result,
                    )
                    "open" -> openDocument(call.argument<String>("uri"), result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun pickFolder(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "A folder picker is already open", null)
            return
        }
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
        }
        try {
            startActivityForResult(intent, pickRequestCode)
        } catch (e: Exception) {
            pendingPick = null
            result.error("unavailable", e.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != pickRequestCode) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingPick ?: return
        pendingPick = null

        val tree = data?.data
        if (resultCode != Activity.RESULT_OK || tree == null) {
            result.success(null)
            return
        }
        // The grant only survives a restart when it is persisted.
        try {
            contentResolver.takePersistableUriPermission(
                tree,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (_: SecurityException) {
            // Some providers do not offer a persistable grant; the folder
            // still works for this session.
        }
        result.success(tree.toString())
    }

    private fun publish(
        treeUri: String?,
        sourcePath: String?,
        fileName: String?,
        mimeType: String?,
        result: MethodChannel.Result,
    ) {
        if (treeUri == null || sourcePath == null || fileName == null) {
            result.error("bad_args", "treeUri, sourcePath and fileName are required", null)
            return
        }
        try {
            val tree = Uri.parse(treeUri)
            val parentId = DocumentsContract.getTreeDocumentId(tree)
            val parent = DocumentsContract.buildDocumentUriUsingTree(tree, parentId)
            // A second file with the same name would replace the first one in
            // folders whose provider does not rename it, so the name is made
            // unique against the children the folder already has.
            val uniqueName = uniqueChildName(tree, parentId, fileName)
            val document = DocumentsContract.createDocument(
                contentResolver,
                parent,
                mimeType ?: "application/octet-stream",
                uniqueName,
            ) ?: throw IllegalStateException("The folder refused the file")

            contentResolver.openOutputStream(document, "w").use { output ->
                if (output == null) throw IllegalStateException("The folder is not writable")
                File(sourcePath).inputStream().use { input -> input.copyTo(output) }
            }
            result.success(document.toString())
        } catch (e: Exception) {
            result.error("publish_failed", e.message, null)
        }
    }

    /**
     * A name no child of [parentId] already uses.
     *
     * [desired] is returned unchanged when the folder has no such child and
     * also when its children cannot be listed: a failed lookup must not cost
     * the user the file. The counter goes before the extension, so
     * `report.pdf` becomes `report (1).pdf`, and the stem is shortened to keep
     * the 255-byte name limit.
     */
    private fun uniqueChildName(tree: Uri, parentId: String, desired: String): String {
        val taken = existingChildNames(tree, parentId) ?: return desired
        if (taken.none { it.equals(desired, ignoreCase = true) }) return desired

        val dot = desired.lastIndexOf('.')
        val hasExtension = dot > 0 && dot < desired.length - 1
        val stem = if (hasExtension) desired.substring(0, dot) else desired
        val extension = if (hasExtension) desired.substring(dot) else ""

        var index = 1
        while (true) {
            val tail = " ($index)$extension"
            val budget = MAX_NAME_BYTES - tail.toByteArray(Charsets.UTF_8).size
            val candidate = fitUtf8(stem, budget.coerceAtLeast(0)) + tail
            if (taken.none { it.equals(candidate, ignoreCase = true) }) return candidate
            index++
        }
    }

    /**
     * The display names of the children of [parentId], or null when the
     * provider cannot answer. Callers treat null as "do not rename".
     */
    private fun existingChildNames(tree: Uri, parentId: String): Set<String>? {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId)
        return try {
            contentResolver.query(
                children,
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                val column = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                if (column < 0) return null
                val names = mutableSetOf<String>()
                while (cursor.moveToNext()) {
                    val name = cursor.getString(column)
                    if (!name.isNullOrEmpty()) names.add(name)
                }
                names
            }
        } catch (_: Exception) {
            null
        }
    }

    /** The longest prefix of [value] that fits in [maxBytes] UTF-8 bytes. */
    private fun fitUtf8(value: String, maxBytes: Int): String {
        val result = StringBuilder()
        var used = 0
        var index = 0
        while (index < value.length) {
            val codePoint = value.codePointAt(index)
            val piece = String(Character.toChars(codePoint))
            val size = piece.toByteArray(Charsets.UTF_8).size
            if (used + size > maxBytes) break
            result.append(piece)
            used += size
            index += Character.charCount(codePoint)
        }
        return result.toString()
    }

    private fun openDocument(uri: String?, result: MethodChannel.Result) {
        if (uri == null) {
            result.error("bad_args", "uri is required", null)
            return
        }
        try {
            val parsed = Uri.parse(uri)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(parsed, contentResolver.getType(parsed) ?: "*/*")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("open_failed", e.message, null)
        }
    }
}
