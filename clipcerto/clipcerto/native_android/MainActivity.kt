// Código nativo Android do ClipCerto (versão 2.0).
// Destino: android/app/src/main/kotlin/br/com/ludus/clipcerto/MainActivity.kt
//
// Responsabilidades (todas com APIs oficiais do Android, sem permissões amplas):
//  1. Receber links e arquivos de vídeo/áudio pelo menu "Compartilhar".
//  2. Escolher pasta de destino (permissão persistente) e escolher mídia para importar.
//  3. Gravar arquivos na pasta escolhida.
//  4. Separar a faixa de áudio de um vídeo (MediaExtractor + MediaMuxer, sem converter).
//  5. Abrir e compartilhar arquivos e textos.

package br.com.ludus.clipcerto

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer

class MainActivity : FlutterActivity() {

    private val channelName = "br.com.ludus.clipcerto/native"
    private val requestPickFolder = 4242
    private val requestPickMedia = 4243

    private var channel: MethodChannel? = null
    private var pendingFolderResult: MethodChannel.Result? = null
    private var pendingMediaResult: MethodChannel.Result? = null
    private var initialSharedText: String? = null
    private var initialSharedFile: Map<String, Any?>? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        readIncoming(intent, deliverNow = false)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialSharedText" -> {
                    result.success(initialSharedText)
                    initialSharedText = null
                }
                "getInitialSharedFile" -> {
                    result.success(initialSharedFile)
                    initialSharedFile = null
                }
                "pickFolder" -> pickFolder(result)
                "pickMedia" -> pickMedia(result)
                "describeFolder" -> {
                    val tree = call.argument<String>("treeUri")
                    result.success(if (tree == null) null else describeFolder(Uri.parse(tree)))
                }
                "hasFolderPermission" -> {
                    val tree = call.argument<String>("treeUri")
                    result.success(tree != null && hasWritePermission(Uri.parse(tree)))
                }
                "copyToFolder" -> {
                    val tree = call.argument<String>("treeUri")
                    val source = call.argument<String>("sourcePath")
                    val name = call.argument<String>("displayName")
                    val mime = call.argument<String>("mimeType") ?: "application/octet-stream"
                    if (tree == null || source == null || name == null) {
                        result.error("BAD_ARGS", "Parâmetros ausentes.", null)
                    } else {
                        runInBackground(result) {
                            copyFileToTree(Uri.parse(tree), File(source), name, mime).toString()
                        }
                    }
                }
                "copyUriToFolder" -> {
                    val tree = call.argument<String>("treeUri")
                    val source = call.argument<String>("sourceUri")
                    val name = call.argument<String>("displayName")
                    val mime = call.argument<String>("mimeType") ?: "application/octet-stream"
                    if (tree == null || source == null || name == null) {
                        result.error("BAD_ARGS", "Parâmetros ausentes.", null)
                    } else {
                        runInBackground(result) {
                            copyUriToTree(Uri.parse(tree), Uri.parse(source), name, mime).toString()
                        }
                    }
                }
                "copyUriToCache" -> {
                    val source = call.argument<String>("sourceUri")
                    val name = call.argument<String>("fileName") ?: "midia"
                    if (source == null) result.error("BAD_ARGS", "Arquivo ausente.", null)
                    else runInBackground(result) { copyUriToCache(Uri.parse(source), name) }
                }
                "extractAudio" -> {
                    val source = call.argument<String>("sourceUri")
                    val outName = call.argument<String>("outName") ?: "audio.m4a"
                    if (source == null) result.error("BAD_ARGS", "Arquivo ausente.", null)
                    else runInBackground(result) { extractAudio(Uri.parse(source), outName) }
                }
                "openUri" -> {
                    val uri = call.argument<String>("uri")
                    val mime = call.argument<String>("mimeType") ?: "*/*"
                    if (uri == null) result.error("BAD_ARGS", "Endereço ausente.", null)
                    else openUri(Uri.parse(uri), mime, result)
                }
                "shareUri" -> {
                    val uri = call.argument<String>("uri")
                    val mime = call.argument<String>("mimeType") ?: "*/*"
                    if (uri == null) result.error("BAD_ARGS", "Endereço ausente.", null)
                    else shareUri(Uri.parse(uri), mime, result)
                }
                "shareText" -> {
                    val text = call.argument<String>("text") ?: ""
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, text)
                    }
                    try {
                        startActivity(Intent.createChooser(intent, "Compartilhar texto"))
                        result.success(null)
                    } catch (e: ActivityNotFoundException) {
                        result.error("NO_APP", "Nenhum app disponível para compartilhar.", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Executa um trabalho pesado fora da tela principal e devolve o resultado ao Flutter. */
    private fun runInBackground(result: MethodChannel.Result, work: () -> Any?) {
        Thread {
            try {
                val value = work()
                mainHandler.post { result.success(value) }
            } catch (e: Exception) {
                mainHandler.post { result.error("FAILED", e.message ?: "Falha inesperada.", null) }
            }
        }.start()
    }

    // ------------------------------------------------------------------
    // 1. Compartilhar: links (texto) e arquivos (vídeo ou áudio)
    // ------------------------------------------------------------------
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readIncoming(intent, deliverNow = true)
    }

    private fun readIncoming(intent: Intent?, deliverNow: Boolean) {
        if (intent == null) return
        if (intent.action == Intent.ACTION_SEND) {
            val stream = streamUri(intent)
            val type = intent.type ?: ""
            if (stream != null && (type.startsWith("video/") || type.startsWith("audio/"))) {
                val info = mediaInfo(stream, type)
                if (deliverNow) channel?.invokeMethod("onSharedFile", info) else initialSharedFile = info
                return
            }
            val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: intent.getStringExtra(Intent.EXTRA_SUBJECT)
            if (text != null) {
                if (deliverNow) channel?.invokeMethod("onSharedText", text) else initialSharedText = text
            }
        } else if (intent.action == Intent.ACTION_VIEW && intent.dataString != null) {
            val text = intent.dataString
            if (deliverNow) channel?.invokeMethod("onSharedText", text) else initialSharedText = text
        }
    }

    private fun streamUri(intent: Intent): Uri? {
        return if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        }
    }

    /** Nome, tamanho e tipo de um arquivo content:// */
    private fun mediaInfo(uri: Uri, fallbackMime: String?): Map<String, Any?> {
        var name = "midia"
        var size = 0L
        try {
            contentResolver.query(uri, null, null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val n = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val s = c.getColumnIndex(OpenableColumns.SIZE)
                    if (n >= 0 && !c.isNull(n)) name = c.getString(n)
                    if (s >= 0 && !c.isNull(s)) size = c.getLong(s)
                }
            }
        } catch (ignored: Exception) {
        }
        val mime = contentResolver.getType(uri) ?: fallbackMime ?: "application/octet-stream"
        return mapOf("uri" to uri.toString(), "name" to name, "size" to size, "mime" to mime)
    }

    // ------------------------------------------------------------------
    // 2. Seletores: pasta de destino e mídia para importar
    // ------------------------------------------------------------------
    private fun pickFolder(result: MethodChannel.Result) {
        if (pendingFolderResult != null) {
            result.error("BUSY", "O seletor de pasta já está aberto.", null)
            return
        }
        pendingFolderResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
        }
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, requestPickFolder)
        } catch (e: ActivityNotFoundException) {
            pendingFolderResult = null
            result.error("NO_PICKER", "Este aparelho não tem seletor de pastas.", null)
        }
    }

    private fun pickMedia(result: MethodChannel.Result) {
        if (pendingMediaResult != null) {
            result.error("BUSY", "O seletor de arquivos já está aberto.", null)
            return
        }
        pendingMediaResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("video/*", "audio/*"))
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, requestPickMedia)
        } catch (e: ActivityNotFoundException) {
            pendingMediaResult = null
            result.error("NO_PICKER", "Este aparelho não tem seletor de arquivos.", null)
        }
    }

    @Deprecated("Usado para compatibilidade com FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        val uri = data?.data

        if (requestCode == requestPickFolder) {
            val result = pendingFolderResult ?: return
            pendingFolderResult = null
            if (resultCode != Activity.RESULT_OK || uri == null) {
                result.success(null)
                return
            }
            try {
                contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
                result.success(uri.toString())
            } catch (e: SecurityException) {
                result.error("PERMISSION", "O Android não liberou escrita nesta pasta. Escolha outra.", null)
            }
        } else if (requestCode == requestPickMedia) {
            val result = pendingMediaResult ?: return
            pendingMediaResult = null
            if (resultCode != Activity.RESULT_OK || uri == null) {
                result.success(null)
                return
            }
            try {
                contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } catch (ignored: Exception) {
                // Alguns provedores não oferecem permissão persistente; o acesso temporário basta.
            }
            result.success(mediaInfo(uri, null))
        }
    }

    private fun hasWritePermission(tree: Uri): Boolean =
        contentResolver.persistedUriPermissions.any { it.uri == tree && it.isWritePermission }

    private fun describeFolder(tree: Uri): String {
        return try {
            val docId = DocumentsContract.getTreeDocumentId(tree)
            val path = docId.substringAfter(":", docId)
            val volume = docId.substringBefore(":", "")
            when {
                path.isEmpty() -> "Armazenamento interno"
                volume == "primary" -> "Armazenamento interno/$path"
                else -> path
            }
        } catch (e: Exception) {
            "Pasta escolhida"
        }
    }

    // ------------------------------------------------------------------
    // 3. Gravar arquivos na pasta escolhida
    // ------------------------------------------------------------------
    private fun createInTree(tree: Uri, displayName: String, mime: String): Uri {
        if (!hasWritePermission(tree)) {
            throw SecurityException("Sem permissão para a pasta. Escolha a pasta novamente nos Ajustes.")
        }
        val parent = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        return DocumentsContract.createDocument(contentResolver, parent, mime, displayName)
            ?: throw IllegalStateException("Não foi possível criar o arquivo na pasta escolhida.")
    }

    private fun writeInto(target: Uri, write: (java.io.OutputStream) -> Unit) {
        try {
            contentResolver.openOutputStream(target)?.use { out -> write(out) }
                ?: throw IllegalStateException("Não foi possível abrir o arquivo para escrita.")
        } catch (e: Exception) {
            try { DocumentsContract.deleteDocument(contentResolver, target) } catch (ignored: Exception) {}
            throw e
        }
    }

    private fun copyFileToTree(tree: Uri, source: File, displayName: String, mime: String): Uri {
        if (!source.exists()) throw IllegalStateException("Arquivo temporário não encontrado.")
        val created = createInTree(tree, displayName, mime)
        writeInto(created) { out -> source.inputStream().use { it.copyTo(out, 64 * 1024) } }
        return created
    }

    private fun copyUriToTree(tree: Uri, source: Uri, displayName: String, mime: String): Uri {
        val created = createInTree(tree, displayName, mime)
        writeInto(created) { out ->
            val input = contentResolver.openInputStream(source)
                ?: throw IllegalStateException("Não foi possível ler o arquivo de origem.")
            input.use { it.copyTo(out, 64 * 1024) }
        }
        return created
    }

    private fun copyUriToCache(source: Uri, fileName: String): String {
        val safe = fileName.replace(Regex("[\\\\/:*?\"<>|]"), "_")
        val out = File(cacheDir, "import_${System.currentTimeMillis()}_$safe")
        val input = contentResolver.openInputStream(source)
            ?: throw IllegalStateException("Não foi possível ler o arquivo.")
        input.use { inp -> out.outputStream().use { inp.copyTo(it, 64 * 1024) } }
        return out.absolutePath
    }

    // ------------------------------------------------------------------
    // 4. Separar o áudio de um vídeo (sem perder qualidade, sem converter)
    // ------------------------------------------------------------------
    private fun extractAudio(source: Uri, outName: String): Map<String, Any?> {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(this, source, null)
        } catch (e: Exception) {
            extractor.release()
            throw IllegalStateException("Não consegui ler este arquivo de vídeo.")
        }

        var track = -1
        var format: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val f = extractor.getTrackFormat(i)
            val mime = f.getString(MediaFormat.KEY_MIME) ?: ""
            if (mime.startsWith("audio/")) {
                track = i
                format = f
                break
            }
        }
        val fmt = format
        if (track < 0 || fmt == null) {
            extractor.release()
            throw IllegalStateException("Este vídeo não tem som.")
        }
        val audioMime = fmt.getString(MediaFormat.KEY_MIME) ?: ""
        if (audioMime != MediaFormat.MIMETYPE_AUDIO_AAC) {
            extractor.release()
            throw IllegalStateException(
                "O som deste vídeo está no formato $audioMime, que o celular não separa sem converter. " +
                    "Vídeos gravados no celular, do TikTok e do Instagram normalmente funcionam."
            )
        }

        extractor.selectTrack(track)
        val out = File(cacheDir, "audio_${System.currentTimeMillis()}_$outName")
        val muxer = MediaMuxer(out.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        try {
            val dst = muxer.addTrack(fmt)
            muxer.start()
            val maxInput = if (fmt.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                fmt.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)
            } else {
                0
            }
            val buffer = ByteBuffer.allocate(maxOf(maxInput, 512 * 1024))
            val info = MediaCodec.BufferInfo()
            while (true) {
                info.offset = 0
                info.size = extractor.readSampleData(buffer, 0)
                if (info.size < 0) break
                info.presentationTimeUs = extractor.sampleTime
                info.flags = if ((extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC) != 0) {
                    MediaCodec.BUFFER_FLAG_KEY_FRAME
                } else {
                    0
                }
                muxer.writeSampleData(dst, buffer, info)
                extractor.advance()
            }
            muxer.stop()
        } catch (e: Exception) {
            out.delete()
            throw IllegalStateException("Falha ao separar o áudio: ${e.message}")
        } finally {
            try { muxer.release() } catch (ignored: Exception) {}
            extractor.release()
        }

        val durationMs = if (fmt.containsKey(MediaFormat.KEY_DURATION)) fmt.getLong(MediaFormat.KEY_DURATION) / 1000 else 0L
        return mapOf("path" to out.absolutePath, "durationMs" to durationMs, "size" to out.length())
    }

    // ------------------------------------------------------------------
    // 5. Abrir e compartilhar arquivos
    // ------------------------------------------------------------------
    private fun openUri(uri: Uri, mime: String, result: MethodChannel.Result) {
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            startActivity(Intent.createChooser(intent, "Abrir com"))
            result.success(null)
        } catch (e: ActivityNotFoundException) {
            result.error("NO_APP", "Nenhum app instalado consegue abrir este arquivo.", null)
        } catch (e: SecurityException) {
            result.error("NO_ACCESS", "O arquivo foi movido ou apagado.", null)
        }
    }

    private fun shareUri(uri: Uri, mime: String, result: MethodChannel.Result) {
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mime
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            startActivity(Intent.createChooser(intent, "Compartilhar com"))
            result.success(null)
        } catch (e: ActivityNotFoundException) {
            result.error("NO_APP", "Nenhum app disponível para compartilhar.", null)
        }
    }
}
