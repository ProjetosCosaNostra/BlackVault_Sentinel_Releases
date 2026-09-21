package br.com.lafamigliaplayworks.onpcloudpreview;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.view.MotionEvent;
import android.view.View;
import java.io.InputStream;

public final class PreviewView extends View {
  private static final float RW=760f, RH=1436f;
  private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
  private final Bitmap main;
  private final Bitmap channels;
  private boolean showChannels=false;
  private float sx=1f, sy=1f;

  public PreviewView(Context c) {
    super(c);
    setBackgroundColor(Color.BLACK);
    main=load("main.webp");
    channels=load("channels.webp");
  }
  private Bitmap load(String name) {
    try (InputStream in=getContext().getAssets().open(name)) {
      Bitmap b=BitmapFactory.decodeStream(in);
      if(b==null) throw new IllegalStateException(name);
      return b;
    } catch(Exception e) { throw new RuntimeException(e); }
  }
  @Override protected void onDraw(Canvas c) {
    super.onDraw(c);
    sx=getWidth()/RW; sy=getHeight()/RH;
    c.drawBitmap(showChannels?channels:main,null,new RectF(0,0,getWidth(),getHeight()),paint);
  }
  private boolean hit(float x,float y,float l,float t,float r,float b) {
    return x>=l && x<=r && y>=t && y<=b;
  }
  @Override public boolean onTouchEvent(MotionEvent e) {
    if(e.getAction()!=MotionEvent.ACTION_UP) return true;
    float x=e.getX()/sx, y=e.getY()/sy;
    if(!showChannels && hit(x,y,28,930,732,1058)) { showChannels=true; invalidate(); return true; }
    if(showChannels && hit(x,y,28,148,88,210)) { showChannels=false; invalidate(); return true; }
    return true;
  }
}
