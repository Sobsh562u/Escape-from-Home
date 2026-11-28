package com.sobsh562u.ehqmod;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.Bundle;
import android.webkit.JavascriptInterface;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.List;

/**
 * 逃家模组 · 手机版
 * 一个 WebView 壳：编辑器在 assets/index.html 里，工作区落在 App 的 data 目录。
 * 授权走设备码：App 生成 ABCD-1234 → 跳浏览器确认 → 轮询拿 token → 存本地。
 */
public class MainActivity extends Activity {

    private static final String RPC = "https://spvouajdnckiyihhccux.supabase.co/rest/v1/rpc/";
    private static final String KEY = "sb_publishable_gOcJXjEu8wVL7tDFNCL5yw_7Y7Zy7ET";

    private WebView web;
    private File ws;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        ws = new File(getExternalFilesDir(null) == null ? getFilesDir() : getExternalFilesDir(null), "workspace");
        if (!ws.exists()) ws.mkdirs();
        new File(ws, "src").mkdirs();

        web = new WebView(this);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setAllowFileAccess(true);
        s.setAllowContentAccess(true);
        s.setDatabaseEnabled(true);
        s.setTextZoom(100);
        web.setWebViewClient(new WebViewClient());
        web.addJavascriptInterface(new Bridge(), "EHQ");
        setContentView(web);
        web.loadUrl("file:///android_asset/index.html");
    }

    @Override
    public void onBackPressed() {
        if (web != null && web.canGoBack()) { web.goBack(); return; }
        super.onBackPressed();
    }

    public class Bridge {

        @JavascriptInterface
        public String workspacePath() {
            return ws.getAbsolutePath();
        }

        @JavascriptInterface
        public String listFiles() {
            JSONArray arr = new JSONArray();
            walk(ws, "", arr);
            return arr.toString();
        }

        private void walk(File dir, String prefix, JSONArray out) {
            File[] fs = dir.listFiles();
            if (fs == null) return;
            java.util.Arrays.sort(fs);
            for (File f : fs) {
                String name = prefix + f.getName();
                if (f.isDirectory()) {
                    walk(f, name + "/", out);
                } else {
                    try {
                        JSONObject o = new JSONObject();
                        o.put("name", name);
                        o.put("size", f.length());
                        out.put(o);
                    } catch (Exception ignored) {}
                }
            }
        }

        private File safe(String name) {
            if (name == null) return null;
            name = name.replace("\\", "/").trim();
            while (name.startsWith("/")) name = name.substring(1);
            if (name.isEmpty() || name.contains("..")) return null;
            return new File(ws, name);
        }

        @JavascriptInterface
        public String readFile(String name) {
            File f = safe(name);
            if (f == null || !f.exists()) return "";
            try (FileInputStream in = new FileInputStream(f)) {
                byte[] buf = new byte[in.available()];
                in.read(buf);
                return new String(buf, "UTF-8");
            } catch (Exception e) {
                return "";
            }
        }

        @JavascriptInterface
        public boolean writeFile(String name, String content) {
            File f = safe(name);
            if (f == null) return false;
            try {
                File parent = f.getParentFile();
                if (parent != null && !parent.exists()) parent.mkdirs();
                try (FileOutputStream out = new FileOutputStream(f)) {
                    out.write(content == null ? new byte[0] : content.getBytes("UTF-8"));
                }
                return true;
            } catch (Exception e) {
                return false;
            }
        }

        @JavascriptInterface
        public boolean deleteFile(String name) {
            File f = safe(name);
            return f != null && f.exists() && f.delete();
        }

        @JavascriptInterface
        public String getToken() {
            return prefs().getString("token", "");
        }

        @JavascriptInterface
        public void setToken(String token) {
            prefs().edit().putString("token", token == null ? "" : token).apply();
        }

        @JavascriptInterface
        public void clearToken() {
            prefs().edit().remove("token").apply();
        }

        private SharedPreferences prefs() {
            return getSharedPreferences("ehqmod", MODE_PRIVATE);
        }

        /** 所有服务器请求都从这里走，避免 WebView 的 file:// 跨域问题 */
        @JavascriptInterface
        public String post(String fn, String bodyJson) {
            HttpURLConnection c = null;
            try {
                URL u = new URL(RPC + fn);
                c = (HttpURLConnection) u.openConnection();
                c.setRequestMethod("POST");
                c.setConnectTimeout(20000);
                c.setReadTimeout(30000);
                c.setDoOutput(true);
                c.setRequestProperty("apikey", KEY);
                c.setRequestProperty("Authorization", "Bearer " + KEY);
                c.setRequestProperty("Content-Type", "application/json");
                try (OutputStream os = c.getOutputStream()) {
                    os.write((bodyJson == null ? "{}" : bodyJson).getBytes("UTF-8"));
                }
                int code = c.getResponseCode();
                InputStream is = (code >= 200 && code < 300) ? c.getInputStream() : c.getErrorStream();
                StringBuilder sb = new StringBuilder();
                if (is != null) {
                    try (BufferedReader br = new BufferedReader(new InputStreamReader(is, "UTF-8"))) {
                        String line;
                        while ((line = br.readLine()) != null) sb.append(line);
                    }
                }
                if (sb.length() == 0) return "{\"ok\":false,\"msg\":\"服务器返回 " + code + "\"}";
                return sb.toString();
            } catch (Exception e) {
                return "{\"ok\":false,\"msg\":\"连不上：" + e.getMessage().replace("\"", "'") + "\"}";
            } finally {
                if (c != null) c.disconnect();
            }
        }

        @JavascriptInterface
        public void openUrl(String url) {
            try {
                Intent i = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                startActivity(i);
            } catch (Exception ignored) {}
        }

        @JavascriptInterface
        public void toast(String msg) {}
    }
}
