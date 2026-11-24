// Código nativo Android do ClipCerto.
// Destino: android/app/src/main/kotlin/br/com/ludus/clipcerto/MainActivity.kt
//
// Responsabilidades (todas usando APIs oficiais do Android, sem permissões amplas):
//  1. Receber links pelo menu "Compartilhar" (Intent ACTION_SEND).
//  2. Abrir o seletor de pastas do sistema (ACTION_OPEN_DOCUMENT_TREE) e guardar
//     a permissão da pasta (takePersistableUriPermission) para os próximos downloads.
//  3. Gravar o arquivo baixado na pasta escolhida (DocumentsContract).
//  4. Abrir e compartilhar o arquivo salvo com outros apps.

package br.com.ludus.clipcerto

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private val channelName = "br.com.ludus.clipcerto/native"
    private val requestPickFolder = 4242

    private var channel: MethodChannel? = null
    private var pendingFolderResult: MethodChannel.Result? = null
    private var initialSharedText: String? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        initialSharedText = extractSharedText(intent)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialSharedText" -> {
                    result.success(initialSharedText)
                    initialSharedText = null // entrega só uma vez
                }
                "pickFolder" -> pickFolder(result)
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
                        // Cópia em segundo plano para não travar a tela.
                        Thread {
                            try {
                                val uri = copyToTree(Uri.parse(tree), File(source), name, mime)
                                mainHandler.post { result.success(uri.toString()) }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error("SAVE_FAILED", e.message ?: "Falha ao gravar na pasta.", null)
                                }
                            }
                        }.start()
                    }
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
                else -> result.notImplemented()
            }
        }
    }

    // ------------------------------------------------------------------
    // 1. Compartilhar: o app já aberto recebe um novo link
    // ------------------------------------------------------------------
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        extractSharedText(intent)?.let { channel?.invokeMethod("onSharedText", it) }
    }

    private fun extractSharedText(intent: Intent?): String? {
        if (intent == null) return null
        return when (intent.action) {
            Intent.ACTION_SEND -> {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
                text ?: subject
            }
            Intent.ACTION_VIEW -> intent.dataString
            else -> null
        }
    }

    // ------------------------------------------------------------------
    // 2. Seletor de pasta com permissão persistente
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

    @Deprecated("Usado para compatibilidade com FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != requestPickFolder) return
        val result = pendingFolderResult ?: return
        pendingFolderResult = null

        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null) // usuário cancelou
            return
        }
        try {
            // Guarda a permissão mesmo depois de reiniciar o celular.
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
            result.success(uri.toString())
        } catch (e: SecurityException) {
            result.error("PERMISSION", "O Android não liberou escrita nesta pasta. Escolha outra.", null)
        }
    }

    private fun hasWritePermission(tree: Uri): Boolean =
        contentResolver.persistedUriPermissions.any { it.uri == tree && it.isWritePermission }

    private fun describeFolder(tree: Uri): String {
        return try {
            // Ex.: "primary:Movies/ClipCerto" -> "Movies/ClipCerto"
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
    // 3. Gravar o arquivo na pasta escolhida
    // ------------------------------------------------------------------
    private fun copyToTree(tree: Uri, source: File, displayName: String, mime: String): Uri {
        if (!source.exists()) throw IllegalStateException("Arquivo temporário não encontrado.")
        if (!hasWritePermission(tree)) {
            throw SecurityException("Sem permissão para a pasta. Escolha a pasta novamente nos Ajustes.")
        }
        val parent = DocumentsContract.buildDocumentUriUsingTree(
            tree, DocumentsContract.getTreeDocumentId(tree)
        )
        // Se já existir um arquivo com o mesmo nome, o Android cria "nome (1).mp4".
        val created = DocumentsContract.createDocument(contentResolver, parent, mime, displayName)
            ?: throw IllegalStateException("Não foi possível criar o arquivo na pasta escolhida.")

        try {
            contentResolver.openOutputStream(created)?.use { out ->
                source.inputStream().use { input -> input.copyTo(out, 64 * 1024) }
            } ?: throw IllegalStateException("Não foi possível abrir o arquivo para escrita.")
        } catch (e: Exception) {
            // Remove o arquivo incompleto para não deixar lixo na pasta.
            try { DocumentsContract.deleteDocument(contentResolver, created) } catch (ignored: Exception) {}
            throw e
        }
        return created
    }

    // ------------------------------------------------------------------
    // 4. Abrir e compartilhar o arquivo salvo
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
