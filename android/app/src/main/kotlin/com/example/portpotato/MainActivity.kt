package com.example.portpotato

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import com.arm.aichat.internal.InferenceEngineImpl
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingImport: MethodChannel.Result? = null

    private fun displayName(uri: Uri): String? =
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 4017) return
        val reply = pendingImport ?: return
        pendingImport = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            reply.success(null)
            return
        }
        try {
            val name = displayName(uri)
            require(name != null && name.endsWith(".gguf", ignoreCase = true)) { "Choose a GGUF file" }
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            reply.success(mapOf("uri" to uri.toString(), "name" to name))
        } catch (error: Exception) {
            reply.error("IMPORT_ERROR", error.message ?: "Could not open the selected model", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val preferences = getSharedPreferences("portpotato", MODE_PRIVATE)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "portpotato/theme")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "read" -> result.success(preferences.getString("theme", null))
                    "readSettings" -> result.success(preferences.getString("settings", null))
                    "writeSettings" -> {
                        val value = call.arguments as? String
                        if (value == null) result.error("INVALID_SETTINGS", "Settings must be text", null)
                        else {
                            preferences.edit().putString("settings", value).apply()
                            result.success(null)
                        }
                    }
                    "write" -> {
                        val theme = call.arguments as? String
                        if (theme == null) {
                            result.error("INVALID_THEME", "Theme must be a string", null)
                        } else {
                            preferences.edit().putString("theme", theme).apply()
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "portpotato/chats")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "read" -> result.success(preferences.getString("chats", null))
                    "write" -> {
                        val value = call.arguments as? String
                        // shortcut: one JSON preference is capped at 4 MB; use a database for larger archives.
                        if (value == null || value.length > 4_000_000)
                            result.error("INVALID_CHATS", "Chat archive is invalid or too large", null)
                        else {
                            preferences.edit().putString("chats", value).apply()
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "portpotato/inference")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "modelsDirectory" -> {
                        val folder = InferenceEngineImpl.modelsDirectory(this)
                        if (folder.isDirectory || folder.mkdirs()) result.success(folder.absolutePath)
                        else result.error("STORAGE_ERROR", "Could not create models folder", null)
                    }
                    "loadModel" -> {
                        val path = call.argument<String>("path")
                        if (path == null) result.error("INVALID_MODEL", "Model path is required", null)
                        else InferenceEngineImpl.loadModel(this, path, result)
                    }
                    "loadDocument" -> {
                        val uri = call.argument<String>("uri")
                        if (uri == null) result.error("INVALID_MODEL", "Model document is required", null)
                        else InferenceEngineImpl.loadDocument(this, uri, result)
                    }
                    "listModels" -> {
                        val models = contentResolver.persistedUriPermissions.mapNotNull { permission ->
                            if (!permission.isReadPermission) return@mapNotNull null
                            try {
                                val name = displayName(permission.uri)
                                if (name?.endsWith(".gguf", ignoreCase = true) == true)
                                    mapOf("uri" to permission.uri.toString(), "name" to name)
                                else null
                            } catch (_: Exception) { null }
                        }
                        result.success(models)
                    }
                    "importModel" -> {
                        if (pendingImport != null) {
                            result.error("PICKER_BUSY", "Finish the current model selection", null)
                        } else {
                            pendingImport = result
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "*/*"
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            try {
                                startActivityForResult(intent, 4017)
                            } catch (error: Exception) {
                                pendingImport = null
                                result.error("IMPORT_ERROR", error.message ?: "Could not open the file picker", null)
                            }
                        }
                    }
                    "generate" -> {
                        val prompt = call.argument<String>("prompt")
                        val maxTokens = call.argument<Int>("maxTokens")
                        if (prompt == null || maxTokens == null)
                            result.error("INVALID_PROMPT", "Prompt and max tokens are required", null)
                        else InferenceEngineImpl.generate(prompt, maxTokens, result)
                    }
                    "configure" -> {
                        val contextWindow = call.argument<Int>("contextWindow")
                        val temperature = call.argument<Double>("temperature")
                        val topP = call.argument<Double>("topP")
                        val repeatPenalty = call.argument<Double>("repeatPenalty")
                        if (contextWindow == null || temperature == null || topP == null || repeatPenalty == null)
                            result.error("INVALID_SETTINGS", "Model settings are required", null)
                        else InferenceEngineImpl.configure(this, contextWindow, temperature, topP, repeatPenalty, result)
                    }
                    "restoreHistory" -> {
                        val messages = (call.argument<List<Map<String, String>>>("messages"))
                        if (messages == null) result.error("INVALID_HISTORY", "Messages are required", null)
                        else InferenceEngineImpl.restore(messages, result)
                    }
                    "cancel" -> {
                        InferenceEngineImpl.cancel()
                        result.success(null)
                    }
                    "unloadModel" -> InferenceEngineImpl.unloadModel(result)
                    else -> result.notImplemented()
                }
            }
    }
}
