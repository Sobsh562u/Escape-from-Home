package com.ehgame.escape;

import android.app.Activity;
import android.content.ContentValues;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Base64;
import android.view.KeyEvent;
import android.view.Window;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

public class MainActivity extends Activity {

    private WebView web;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN,
                WindowManager.LayoutParams.FLAG_FULLSCREEN);

        if (android.os.Build.VERSION.SDK_INT >= 21) {
            getWindow().setStatusBarColor(0xFF11141A);
            getWindow().setNavigationBarColor(0xFF11141A);
        }

        web = new WebView(this);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setAllowFileAccess(true);
        s.setAllowContentAccess(true);
        s.setLoadWithOverviewMode(true);
        s.setUseWideViewPort(true);
        s.setSupportZoom(false);
        s.setBuiltInZoomControls(false);
        if (android.os.Build.VERSION.SDK_INT >= 21) {
            s.setMixedContentMode(WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE);
        }
        web.setWebViewClient(new WebViewClient());
        web.setBackgroundColor(0xFF11141A);
        web.addJavascriptInterface(new SaveBridge(), "EscapeBridge");
        web.loadUrl("file:///android_asset/index.html");

        setContentView(web);
    }

    /** 网页里的导出按钮调用：把存档文件落到手机的「下载」目录。 */
    private class SaveBridge {
        @JavascriptInterface
        public String saveFile(String name, String base64) {
            try {
                byte[] data = Base64.decode(base64, Base64.DEFAULT);
                String safe = name == null || name.trim().length() == 0
                        ? "逃家游戏存档-" + stamp() + ".zip"
                        : name.replaceAll("[/\\\\:*?\"<>|]", "_");
                Uri uri = writeToDownloads(safe, data);
                final String msg = "存档已保存到「下载」：" + safe;
                runOnUiThread(new Runnable() {
                    public void run() { Toast.makeText(MainActivity.this, msg, Toast.LENGTH_LONG).show(); }
                });
                return uri == null ? "" : uri.toString();
            } catch (Exception e) {
                final String msg = "保存失败：" + e.getClass().getSimpleName();
                runOnUiThread(new Runnable() {
                    public void run() { Toast.makeText(MainActivity.this, msg, Toast.LENGTH_LONG).show(); }
                });
                return "";
            }
        }

        private String stamp() {
            return new SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(new Date());
        }

        private Uri writeToDownloads(String name, byte[] data) throws Exception {
            if (Build.VERSION.SDK_INT >= 29) {
                ContentValues cv = new ContentValues();
                cv.put(MediaStore.Downloads.DISPLAY_NAME, name);
                cv.put(MediaStore.Downloads.MIME_TYPE, mime(name));
                cv.put(MediaStore.Downloads.IS_PENDING, 1);
                Uri item = getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, cv);
                if (item == null) throw new IllegalStateException("无法创建下载条目");
                OutputStream os = getContentResolver().openOutputStream(item);
                os.write(data);
                os.close();
                cv.clear();
                cv.put(MediaStore.Downloads.IS_PENDING, 0);
                getContentResolver().update(item, cv, null, null);
                return item;
            }
            File dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);
            if (dir == null) dir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS);
            if (!dir.exists()) dir.mkdirs();
            File out = new File(dir, name);
            FileOutputStream fos = new FileOutputStream(out);
            fos.write(data);
            fos.close();
            return Uri.fromFile(out);
        }

        private String mime(String name) {
            String lower = name.toLowerCase(Locale.US);
            if (lower.endsWith(".zip")) return "application/zip";
            if (lower.endsWith(".json")) return "application/json";
            return "text/plain";
        }
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK && web != null && web.canGoBack()) {
            web.goBack();
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    @Override
    protected void onDestroy() {
        if (web != null) {
            web.destroy();
            web = null;
        }
        super.onDestroy();
    }
}
