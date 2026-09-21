package br.com.lafamigliaplayworks.onpcloudpreview;

import android.app.Activity;
import android.os.Bundle;
import android.view.Window;
import android.view.WindowManager;

public final class MainActivity extends Activity {
  @Override protected void onCreate(Bundle state) {
    super.onCreate(state);
    requestWindowFeature(Window.FEATURE_NO_TITLE);
    getWindow().setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN,
        WindowManager.LayoutParams.FLAG_FULLSCREEN);
    setContentView(new PreviewView(this));
  }
}
