package com.arm.aichat.internal

import android.content.Context
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.system.Os
import android.system.OsConstants
import android.system.ErrnoException
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

// JNI names match the pinned llama.cpp Android example.
internal object InferenceEngineImpl {
    private val executor = Executors.newSingleThreadExecutor()
    private var initialized = false
    private var modelLoaded = false
    private var modelDescriptor: ParcelFileDescriptor? = null
    private val generationId = AtomicLong()

    private external fun init(nativeLibDir: String)
    private external fun load(modelPath: String): Int
    private external fun loadFd(fd: Int): Int
    private external fun prepare(): Int
    private external fun configureNative(contextWindow: Int, temperature: Float, topP: Float, repeatPenalty: Float): Int
    private external fun restoreHistory(roles: Array<String>, contents: Array<String>): Int
    private external fun systemInfo(): String
    private external fun processUserPrompt(userPrompt: String, predictLength: Int): Int
    private external fun generateNextToken(): String?
    private external fun unload()

    fun modelsDirectory(context: Context): File =
        File(context.getExternalFilesDir(null) ?: context.filesDir, "models")

    fun loadModel(context: Context, modelPath: String, result: MethodChannel.Result) = submit(result) {
        val root = modelsDirectory(context).canonicalFile
        val model = File(modelPath).canonicalFile
        require(model.path.startsWith(root.path + File.separator)) { "Model must be in the app's models folder" }
        require(model.isFile && model.extension.equals("gguf", ignoreCase = true)) { "Choose a readable GGUF model" }
        require(model.canRead()) { "Model file cannot be read" }

        ensureInitialized(context)
        releaseModel()
        check(load(model.path) == 0) { "Could not load the model" }
        modelLoaded = true
        if (prepare() != 0) {
            releaseModel()
            error("Could not prepare the model")
        }
        null
    }

    fun loadDocument(context: Context, uriString: String, result: MethodChannel.Result) = submit(result) {
        val uri = Uri.parse(uriString)
        require(uri.scheme == "content") { "Choose a model from the file picker" }
        require(context.contentResolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission }) {
            "Model access has expired. Import it again"
        }
        val descriptor = context.contentResolver.openFileDescriptor(uri, "r")
            ?: error("Could not open the selected model")
        var retained = false
        try {
            try {
                Os.lseek(descriptor.fileDescriptor, 0, OsConstants.SEEK_CUR)
            } catch (_: ErrnoException) {
                throw IllegalArgumentException("This provider cannot open the GGUF in place. Choose a local download")
            }
            ensureInitialized(context)
            releaseModel()
            check(loadFd(descriptor.fd) == 0) { "Could not load the selected GGUF" }
            modelLoaded = true
            modelDescriptor = descriptor
            if (prepare() != 0) {
                releaseModel()
                error("Could not prepare the model")
            }
            retained = true
        } finally {
            if (!retained && descriptor.fileDescriptor.valid()) descriptor.close()
        }
        null
    }

    fun generate(prompt: String, maxTokens: Int, result: MethodChannel.Result) {
        val requestId = generationId.incrementAndGet()
        submit(result) {
            require(prompt.isNotBlank()) { "Message is empty" }
            require(maxTokens in 1..4096) { "Max tokens must be between 1 and 4096" }
            check(modelLoaded) { "Load a model first" }
            if (requestId != generationId.get()) return@submit ""
            check(processUserPrompt(prompt, maxTokens) == 0) { "Could not process the message" }
            val response = StringBuilder()
            while (requestId == generationId.get()) {
                val token = generateNextToken() ?: break
                response.append(token)
            }
            response.toString()
        }
    }

    fun configure(context: Context, contextWindow: Int, temperature: Double, topP: Double, repeatPenalty: Double, result: MethodChannel.Result) = submit(result) {
        require(contextWindow in listOf(2048, 4096, 8192, 16384)) { "Unsupported context window" }
        require(temperature.isFinite() && temperature in 0.0..2.0) { "Invalid temperature" }
        require(topP.isFinite() && topP in 0.0..1.0) { "Invalid Top P" }
        require(repeatPenalty.isFinite() && repeatPenalty in 1.0..2.0) { "Invalid repeat penalty" }
        ensureInitialized(context)
        val status = configureNative(contextWindow, temperature.toFloat(), topP.toFloat(), repeatPenalty.toFloat())
        if (status < 0) {
            releaseModel()
            error("Could not apply model settings")
        }
        status == 1
    }

    fun restore(messages: List<Map<String, String>>, result: MethodChannel.Result) = submit(result) {
        check(modelLoaded) { "Load a model first" }
        require(messages.all { it["fromUser"] == "true" || it["fromUser"] == "false" }) { "Invalid message role" }
        val roles = messages.map { if (it["fromUser"] == "true") "user" else "assistant" }.toTypedArray()
        val contents = messages.map { it["text"] ?: error("Message text is missing") }.toTypedArray()
        check(restoreHistory(roles, contents) == 0) { "Could not restore this chat in the current context window" }
        null
    }

    fun cancel() {
        generationId.incrementAndGet()
    }

    fun unloadModel(result: MethodChannel.Result) = submit(result) {
        releaseModel()
        null
    }

    private fun releaseModel() {
        if (modelLoaded) unload()
        modelLoaded = false
        modelDescriptor?.close()
        modelDescriptor = null
    }

    private fun ensureInitialized(context: Context) {
        if (initialized) return
        System.loadLibrary("ai-chat")
        init(context.applicationInfo.nativeLibraryDir)
        initialized = true
    }

    private fun submit(result: MethodChannel.Result, block: () -> Any?) {
        executor.execute {
            try {
                result.success(block())
            } catch (error: UnsatisfiedLinkError) {
                result.error("NATIVE_LIBRARY_ERROR", error.message ?: "Native inference library is unavailable", null)
            } catch (error: Exception) {
                result.error("INFERENCE_ERROR", error.message ?: "Local inference failed", null)
            }
        }
    }
}
