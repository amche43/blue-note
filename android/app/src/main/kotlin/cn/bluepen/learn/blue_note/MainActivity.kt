package cn.bluepen.learn.blue_note

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.provider.MediaStore
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File
import java.io.ByteArrayOutputStream
import java.io.ByteArrayInputStream

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private var cameraFile: File? = null
    private var backupPending: MethodChannel.Result? = null
    private var backupBytes: ByteArray? = null
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "blue_note/backup").setMethodCallHandler { call, result ->
            if (call.method != "save" && call.method != "open") { result.notImplemented(); return@setMethodCallHandler }
            if (backupPending != null) { result.error("busy", "正在处理备份文件", null); return@setMethodCallHandler }
            try {
                val saving = call.method == "save"
                backupBytes = if(saving) call.argument<ByteArray>("bytes") else null
                if(saving && (backupBytes == null || backupBytes!!.size > 64*1024*1024)) throw Exception()
                val intent = Intent(if(saving) Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = if(saving) "application/octet-stream" else "*/*"
                    if(saving) putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "blue-note.bluenote")
                }
                backupPending=result
                startActivityForResult(intent, if(saving) 502 else 503)
            } catch (_:Exception) {
                backupPending=null;backupBytes=null
                result.error("file", "无法打开文件选择器，或备份超过 64MB", null)
            }
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, "blue_note/photo").setMethodCallHandler { call, result ->
            if (call.method != "pick" && call.method != "camera") { result.notImplemented(); return@setMethodCallHandler }
            if (pending != null) { result.error("busy", "已有照片正在处理", null); return@setMethodCallHandler }
            pending = result
            try {
                val intent = if (call.method == "camera") {
                    val folder = File(cacheDir, "capture").apply { mkdirs() }
                    cameraFile = File.createTempFile("question-", ".jpg", folder)
                    val uri = FileProvider.getUriForFile(this, "$packageName.photos", cameraFile!!)
                    Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                        putExtra(MediaStore.EXTRA_OUTPUT, uri)
                        addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        clipData = android.content.ClipData.newRawUri("photo", uri)
                    }
                } else Intent(Intent.ACTION_OPEN_DOCUMENT).apply { type="image/*"; addCategory(Intent.CATEGORY_OPENABLE) }
                startActivityForResult(intent, 501)
            } catch (_: Exception) {
                pending = null; cameraFile?.delete(); cameraFile = null
                result.error("unavailable", "无法打开相机或相册，可先使用系统相机拍照", null)
            }
        }
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode,resultCode,data)
        if(requestCode==502 || requestCode==503) {
            val callback=backupPending ?: return
            if(resultCode!=Activity.RESULT_OK){backupPending=null;backupBytes=null;callback.success(null);return}
            val payload=backupBytes;backupBytes=null
            Thread {
                try {
                    val uri=data?.data ?: throw Exception()
                    val result:Any = if(requestCode==502) {
                        (contentResolver.openOutputStream(uri,"wt") ?: throw Exception()).use {it.write(payload ?: throw Exception());it.flush()}
                        true
                    } else {
                        (contentResolver.openInputStream(uri) ?: throw Exception()).use {
                            val output=ByteArrayOutputStream();val buffer=ByteArray(8192)
                            while(true){val n=it.read(buffer);if(n<0)break;if(output.size()+n>64*1024*1024)throw Exception();output.write(buffer,0,n)}
                            output.toByteArray()
                        }
                    }
                    runOnUiThread {backupPending=null;callback.success(result)}
                } catch (_:Exception) {runOnUiThread {backupPending=null;callback.error("file","文件读写失败或超过 64MB，请重试",null)}}
            }.start()
            return
        }
        if(requestCode!=501)return
        val callback=pending ?: return
        val file=cameraFile; cameraFile=null
        if(resultCode!=Activity.RESULT_OK){pending=null;file?.delete();callback.success(null);return}
        Thread {
            try {
                val bytes = (if(file!=null) file.inputStream() else contentResolver.openInputStream(data?.data ?: throw Exception()))!!.use {
                    val result=ByteArrayOutputStream();val buffer=ByteArray(8192)
                    while(true){val n=it.read(buffer);if(n<0)break;result.write(buffer,0,n);if(result.size()>24*1024*1024)throw Exception()};result.toByteArray()
                }
                val bounds=BitmapFactory.Options().apply{inJustDecodeBounds=true}
                BitmapFactory.decodeByteArray(bytes,0,bytes.size,bounds)
                if(bounds.outWidth<=0 || bounds.outHeight<=0 || bounds.outWidth.toLong()*bounds.outHeight>60000000)throw Exception()
                var sample=1;while(maxOf(bounds.outWidth,bounds.outHeight)/sample>2400)sample*=2
                val bitmap=BitmapFactory.decodeByteArray(bytes,0,bytes.size,BitmapFactory.Options().apply{inSampleSize=sample}) ?: throw Exception()
                val orientation=ExifInterface(ByteArrayInputStream(bytes)).getAttributeInt(ExifInterface.TAG_ORIENTATION,1)
                val matrix=Matrix()
                when(orientation){2->matrix.setScale(-1f,1f);3->matrix.setRotate(180f);4->matrix.setScale(1f,-1f);5->{matrix.setRotate(90f);matrix.postScale(-1f,1f)};6->matrix.setRotate(90f);7->{matrix.setRotate(270f);matrix.postScale(-1f,1f)};8->matrix.setRotate(270f)}
                val rotated=Bitmap.createBitmap(bitmap,0,0,bitmap.width,bitmap.height,matrix,true)
                val output=ByteArrayOutputStream();rotated.compress(Bitmap.CompressFormat.JPEG,90,output)
                if(rotated!==bitmap)rotated.recycle();bitmap.recycle()
                runOnUiThread{pending=null;callback.success(output.toByteArray())}
            } catch (_:Exception) { runOnUiThread{pending=null;callback.error("image", "图片无法读取或过大，请裁剪后重试",null)} }
            finally {file?.delete()}
        }.start()
    }
}
