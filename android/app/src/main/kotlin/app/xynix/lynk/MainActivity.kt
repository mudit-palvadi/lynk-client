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
            val parent = DocumentsContract.buildDocumentUriUsingTree(
                tree,
                DocumentsContract.getTreeDocumentId(tree),
            )
            val document = DocumentsContract.createDocument(
                contentResolver,
                parent,
                mimeType ?: "application/octet-stream",
                fileName,
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
