package br.com.lafamigliaplayworks.orcamentonoponto.recovery;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.view.MotionEvent;
import android.view.View;
import java.util.HashMap;
import java.util.Map;

public final class RecoveryView extends View {
  private static final float RW=760f, RH=1436f;
  private final Paint paint=new Paint();
  private final Map<String,Bitmap> screens=new HashMap<>();
  private String screen="home";
  private float sx=1f, sy=1f;

  public RecoveryView(Context context) {
    super(context);
    setBackgroundColor(Color.BLACK);
    paint.setAntiAlias(false);
    paint.setFilterBitmap(false);
    paint.setDither(false);
    setLayerType(View.LAYER_TYPE_HARDWARE,null);
    screens.put("home",load(R.drawable.screen_home));
    screens.put("home_empty",load(R.drawable.screen_home_empty));
    screens.put("clients",load(R.drawable.screen_clients));
    screens.put("catalog",load(R.drawable.screen_catalog));
    screens.put("history",load(R.drawable.screen_history));
    screens.put("quote",load(R.drawable.screen_quote));
    screens.put("more",load(R.drawable.screen_more));
    screens.put("pro",load(R.drawable.screen_pro));
    screens.put("ecosystem",load(R.drawable.screen_ecosystem));
    screens.put("channels",load(R.drawable.screen_channels));
    screens.put("contact",load(R.drawable.screen_contact));
  }

  private Bitmap load(int id){
    BitmapFactory.Options o=new BitmapFactory.Options();
    o.inScaled=false; o.inDither=false; o.inPreferredConfig=Bitmap.Config.ARGB_8888;
    return BitmapFactory.decodeResource(getResources(),id,o);
  }

  @Override protected void onDraw(Canvas c){
    super.onDraw(c);
    sx=getWidth()/RW; sy=getHeight()/RH;
    Bitmap b=screens.get(screen);
    if(b!=null)c.drawBitmap(b,null,new RectF(0,0,getWidth(),getHeight()),paint);
  }

  private boolean hit(float x,float y,float l,float t,float r,float b){return x>=l&&x<=r&&y>=t&&y<=b;}
  private void go(String s){if(screens.containsKey(s)){screen=s;invalidate();}}

  @Override public boolean onTouchEvent(MotionEvent e){
    if(e.getAction()!=MotionEvent.ACTION_UP)return true;
    float x=e.getX()/sx,y=e.getY()/sy;
    if(y>=1340){if(x<190)go("home");else if(x<380)go("history");else if(x<570)go("clients");else go("more");return true;}
    if("home".equals(screen)){
      if(hit(x,y,30,395,375,540))go("quote");
      else if(hit(x,y,385,395,732,540))go("clients");
      else if(hit(x,y,30,540,375,690))go("catalog");
      else if(hit(x,y,385,540,732,690))go("history");
    }else if("more".equals(screen)){
      if(hit(x,y,25,760,735,865))go("ecosystem");
      else if(hit(x,y,25,855,735,960))go("catalog");
      else if(hit(x,y,500,230,735,390))go("pro");
    }else if("ecosystem".equals(screen)){
      if(hit(x,y,20,125,125,245))go("more");
      else if(hit(x,y,20,990,740,1205))go("channels");
      else if(hit(x,y,20,1190,740,1365))go("contact");
    }else if("channels".equals(screen)){
      if(hit(x,y,20,135,110,235))go("ecosystem");
      else if(hit(x,y,20,1140,740,1300))go("contact");
    }else if("contact".equals(screen)){
      if(hit(x,y,20,135,110,235))go("ecosystem");
    }else if(hit(x,y,0,115,120,275)){go("home");}
    return true;
  }
}
