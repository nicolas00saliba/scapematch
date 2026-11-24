package br.com.escapematch.teste;

import android.Manifest;
import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.webkit.CookieManager;
import android.webkit.GeolocationPermissions;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;

/**
 * Casca de teste: abre o app web real numa WebView. Cada conta fantasma é
 * um applicationId diferente, então sessão e armazenamento ficam separados.
 * Não guarda senha nem token. O login é feito na tela do próprio app.
 */
public class MainActivity extends Activity {
    private static final int FILE_REQUEST = 41;
    private static final int LOCATION_REQUEST = 42;

    private static final String[] INTERNAL_HOSTS = {
        "escapematch.com.br",
        "supabase.co",
        "pagbank.com.br",
        "pagseguro.com.br",
        "pagseguro.uol.com.br",
        "uol.com.br",
    };

    private WebView web;
    private ValueCallback<Uri[]> pendingFiles;
    private String pendingGeoOrigin;
    private GeolocationPermissions.Callback pendingGeoCallback;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        int badgeColor = Color.parseColor(BuildConfig.BADGE_COLOR);
        getWindow().setStatusBarColor(badgeColor);

        web = new WebView(this);
        setContentView(web);

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setMediaPlaybackRequiresUserGesture(true);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(true);
        s.setGeolocationEnabled(true);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        s.setUserAgentString(s.getUserAgentString() + " EscapeMatchTeste/" + BuildConfig.SLUG);

        CookieManager cookies = CookieManager.getInstance();
        cookies.setAcceptCookie(true);
        cookies.setAcceptThirdPartyCookies(web, true);

        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                return openOutside(request.getUrl());
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                injectBadge();
            }
        });

        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback,
                    FileChooserParams params) {
                if (pendingFiles != null) pendingFiles.onReceiveValue(null);
                pendingFiles = callback;
                try {
                    startActivityForResult(params.createIntent(), FILE_REQUEST);
                } catch (ActivityNotFoundException e) {
                    pendingFiles = null;
                    return false;
                }
                return true;
            }

            @Override
            public void onGeolocationPermissionsShowPrompt(String origin,
                    GeolocationPermissions.Callback callback) {
                if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)
                        == PackageManager.PERMISSION_GRANTED) {
                    callback.invoke(origin, true, false);
                    return;
                }
                pendingGeoOrigin = origin;
                pendingGeoCallback = callback;
                requestPermissions(new String[] {
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION,
                }, LOCATION_REQUEST);
            }
        });

        web.setDownloadListener((url, ua, disposition, mime, length) ->
            openOutside(Uri.parse(url), true));

        if (state != null) {
            web.restoreState(state);
        } else {
            web.loadUrl(BuildConfig.START_URL);
        }
    }

    /** Links de fora do EscapeMatch e do PagBank abrem no app certo do celular. */
    private boolean openOutside(Uri uri) {
        return openOutside(uri, false);
    }

    private boolean openOutside(Uri uri, boolean force) {
        String scheme = uri.getScheme() == null ? "" : uri.getScheme();
        String host = uri.getHost() == null ? "" : uri.getHost();
        if (!force && scheme.equals("https") && isInternal(host)) return false;
        try {
            Intent intent;
            if (scheme.equals("intent")) {
                intent = Intent.parseUri(uri.toString(), Intent.URI_INTENT_SCHEME);
                intent.addCategory(Intent.CATEGORY_BROWSABLE);
                intent.setComponent(null);
                intent.setSelector(null);
            } else {
                intent = new Intent(Intent.ACTION_VIEW, uri);
            }
            startActivity(intent);
        } catch (Exception e) {
            Toast.makeText(this, "Não deu pra abrir este link.", Toast.LENGTH_SHORT).show();
        }
        return true;
    }

    private static boolean isInternal(String host) {
        for (String allowed : INTERNAL_HOSTS) {
            if (host.equals(allowed) || host.endsWith("." + allowed)) return true;
        }
        return false;
    }

    private void injectBadge() {
        String js = "(function(){var id='em-teste-selo';if(document.getElementById(id))return;"
            + "var d=document.createElement('div');d.id=id;d.textContent='TESTE · "
            + BuildConfig.BADGE + "';"
            + "d.style.cssText='position:fixed;left:50%;transform:translateX(-50%);"
            + "top:0;z-index:2147483647;pointer-events:none;font:700 10px/16px sans-serif;"
            + "letter-spacing:.06em;color:#fff;background:" + BuildConfig.BADGE_COLOR + ";"
            + "padding:0 8px;border-radius:0 0 6px 6px;opacity:.9';"
            + "document.documentElement.appendChild(d);})();";
        web.evaluateJavascript(js, null);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == FILE_REQUEST) {
            if (pendingFiles != null) {
                pendingFiles.onReceiveValue(
                    WebChromeClient.FileChooserParams.parseResult(resultCode, data));
                pendingFiles = null;
            }
            return;
        }
        super.onActivityResult(requestCode, resultCode, data);
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions,
            int[] results) {
        if (requestCode == LOCATION_REQUEST && pendingGeoCallback != null) {
            boolean granted = results.length > 0
                && results[0] == PackageManager.PERMISSION_GRANTED;
            pendingGeoCallback.invoke(pendingGeoOrigin, granted, false);
            pendingGeoCallback = null;
            pendingGeoOrigin = null;
        }
    }

    @Override
    public void onBackPressed() {
        if (web.canGoBack()) {
            web.goBack();
        } else {
            super.onBackPressed();
        }
    }

    @Override
    protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        web.saveState(out);
    }

    @Override
    protected void onPause() {
        super.onPause();
        CookieManager.getInstance().flush();
    }
}
