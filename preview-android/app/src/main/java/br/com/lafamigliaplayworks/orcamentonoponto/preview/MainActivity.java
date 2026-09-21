package br.com.lafamigliaplayworks.orcamentonoponto.preview;

import android.app.Activity;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.MotionEvent;
import android.view.View;

public class MainActivity extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().setStatusBarColor(Color.rgb(2,3,3));
        getWindow().setNavigationBarColor(Color.rgb(2,3,3));
        getWindow().getDecorView().setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                        | View.SYSTEM_UI_FLAG_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                        | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                        | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        );
        setContentView(new PreviewView());
    }

    final class PreviewView extends View {
        private static final float RW = 760f;
        private static final float RH = 1436f;
        private static final float NAV_TOP = 1311f;

        private final Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final RectF r = new RectF();
        private float scale = 1f, ox = 0f, oy = 0f;
        private int page = 0; // 0 ecosystem, 1 channels, 2 support

        private final int BG = Color.rgb(2,3,3);
        private final int GOLD = Color.rgb(246,193,59);
        private final int WHITE = Color.WHITE;
        private final int MUTED = Color.rgb(205,205,205);

        PreviewView() {
            super(MainActivity.this);
            setBackgroundColor(BG);
            setClickable(true);
        }

        private int c(String hex) { return Color.parseColor(hex); }

        private void reset() {
            p.reset();
            p.setAntiAlias(true);
            p.setStyle(Paint.Style.FILL);
            p.setTextAlign(Paint.Align.LEFT);
        }

        private void font(float size, int color, boolean bold) {
            reset();
            p.setTextSize(size);
            p.setColor(color);
            p.setTypeface(Typeface.create(bold ? "sans-serif-medium" : "sans-serif",
                    bold ? Typeface.BOLD : Typeface.NORMAL));
        }

        private void text(Canvas cv, String s, float x, float y, float size, int color, boolean bold) {
            font(size, color, bold);
            cv.drawText(s, x, y, p);
        }

        private void centered(Canvas cv, String s, float cx, float y, float size, int color, boolean bold) {
            font(size, color, bold);
            cv.drawText(s, cx - p.measureText(s)/2f, y, p);
        }

        private void round(Canvas cv, float l, float t, float rr, float b, float radius, int fill, int stroke) {
            reset();
            r.set(l,t,rr,b);
            p.setColor(fill);
            cv.drawRoundRect(r, radius, radius, p);
            if (stroke != Color.TRANSPARENT) {
                p.setStyle(Paint.Style.STROKE);
                p.setStrokeWidth(1.2f);
                p.setColor(stroke);
                cv.drawRoundRect(r, radius, radius, p);
            }
        }

        private void gradient(Canvas cv, float l, float t, float rr, float b, float radius,
                              int start, int end, int stroke) {
            reset();
            r.set(l,t,rr,b);
            p.setShader(new LinearGradient(l,t,rr,b,start,end, Shader.TileMode.CLAMP));
            cv.drawRoundRect(r, radius, radius, p);
            p.setShader(null);
            if (stroke != Color.TRANSPARENT) {
                p.setStyle(Paint.Style.STROKE);
                p.setStrokeWidth(1.2f);
                p.setColor(stroke);
                cv.drawRoundRect(r, radius, radius, p);
            }
        }

        private void title(Canvas cv, String title, String subtitle) {
            text(cv, "ORÇAMENTO", 28, 43, 24, GOLD, true);
            text(cv, "NO PONTO", 28, 68, 24, GOLD, true);

            round(cv, 650, 20, 728, 88, 30, c("#090A0A"), c("#735820"));
            centered(cv, "‹", 689, 67, 36, GOLD, false);

            text(cv, title, 30, 136, 31, WHITE, true);
            text(cv, subtitle, 30, 168, 14.5f, c("#D1D1D1"), false);

            reset();
            p.setColor(GOLD);
            cv.drawRoundRect(new RectF(30,182,82,186),2,2,p);
        }

        private void hero(Canvas cv, String kicker, String l1, String l2, String sub) {
            gradient(cv, 30, 212, 730, 443, 22, c("#4A3207"), c("#070808"), c("#AA7D1E"));

            reset();
            p.setColor(c("#231707"));
            cv.drawCircle(646, 324, 90, p);
            p.setColor(c("#5F4010"));
            cv.drawCircle(646, 324, 66, p);
            p.setColor(c("#0B0C0C"));
            cv.drawCircle(646, 324, 44, p);
            centered(cv, "BG", 646, 335, 23, GOLD, true);

            text(cv, kicker, 54, 252, 13.5f, GOLD, true);
            text(cv, l1, 54, 306, 29, WHITE, true);
            text(cv, l2, 54, 346, 29, WHITE, true);
            text(cv, sub, 54, 401, 15.5f, c("#E0E0E0"), false);

            round(cv, 54, 409, 292, 434, 12, c("#080909"), c("#6D5B37"));
            text(cv, "✓  Manifesto oficial verificado", 68, 427, 11.4f, GOLD, true);
        }

        private void projectCard(Canvas cv, float l, float t, float rr, float b,
                                 String code, String label, String desc) {
            gradient(cv,l,t,rr,b,17,c("#1E1B15"),c("#070808"),c("#80611F"));
            round(cv,l+17,t+18,l+88,t+89,15,c("#090A0A"),c("#8C6820"));
            centered(cv,code,l+52.5f,t+61,code.length()>2?12.5f:15f,GOLD,true);
            text(cv,label,l+107,t+45,18.5f,WHITE,true);
            text(cv,desc,l+107,t+73,11.8f,MUTED,false);
            text(cv,"›",rr-28,t+67,28,GOLD,false);
        }

        private void ecosystem(Canvas cv) {
            title(cv, "Ecossistema BlackGold", "Tudo que conecta seu negócio, em um só lugar.");
            hero(cv, "BLACKGOLD  •  ECOSSISTEMA",
                    "Tudo conectado.",
                    "Mais força para o seu negócio.",
                    "Projetos, canais e suporte oficial em uma experiência premium.");

            text(cv,"Projetos conectados",30,490,22,WHITE,true);
            text(cv,"Produtos e experiências do ecossistema.",30,516,12.5f,c("#AFAFAF"),false);

            projectCard(cv,30,539,372,653,"LO","Loja Oficial","Hub oficial da BlackGold");
            projectCard(cv,388,539,730,653,"ONP","Preço no Ponto","Ferramenta de precificação");
            projectCard(cv,30,669,372,783,"FN","FitNexus Coach","Saúde, treino e bem-estar");
            projectCard(cv,388,669,730,783,"AE","AppEvidex","Registros e produtividade");

            gradient(cv,30,822,730,958,19,c("#332607"),c("#070808"),c("#946D20"));
            round(cv,50,845,120,916,15,c("#090A0A"),c("#8B6720"));
            centered(cv,"◎",85,890,25,GOLD,true);
            text(cv,"Canais oficiais",143,866,21,WHITE,true);
            text(cv,"Instagram, TikTok, YouTube, Facebook e mais.",143,898,13.2f,MUTED,false);
            text(cv,"Ver canais  ›",570,922,14.8f,GOLD,true);

            gradient(cv,30,979,730,1115,19,c("#2D2107"),c("#070808"),c("#8C6720"));
            round(cv,50,1002,120,1073,15,c("#090A0A"),c("#8B6720"));
            centered(cv,"✉",85,1048,22,GOLD,true);
            text(cv,"Contato e suporte",143,1024,21,WHITE,true);
            text(cv,"Atendimento oficial da equipe BlackGold.",143,1056,13.2f,MUTED,false);
            text(cv,"Abrir  ›",618,1080,14.8f,GOLD,true);

            round(cv,30,1146,730,1235,16,c("#080909"),c("#49412E"));
            centered(cv,"“  Conecte. Organize. Faça seu negócio crescer.  ”",
                    380,1198,13.6f,c("#D7D7D7"),false);

            text(cv,"Destinos oficiais • manifesto verificado",30,1274,12.5f,GOLD,true);
        }

        private void channelCard(Canvas cv,float l,float t,float rr,float b,
                                 String code,String label,String desc) {
            gradient(cv,l,t,rr,b,16,c("#161715"),c("#070808"),c("#655020"));
            round(cv,l+16,t+17,l+78,b-17,13,c("#090A0A"),c("#82601F"));
            centered(cv,code,l+47,t+56,12.5f,GOLD,true);
            text(cv,label,l+96,t+42,17.5f,WHITE,true);
            text(cv,desc,l+96,t+69,11.5f,MUTED,false);
            text(cv,"›",rr-27,t+63,26,GOLD,false);
        }

        private void channels(Canvas cv) {
            title(cv,"Canais oficiais","Presença BlackGold nas plataformas oficiais.");
            hero(cv,"BLACKGOLD  •  CANAIS",
                    "Acompanhe. Conecte.",
                    "Fique por dentro das novidades.",
                    "Todos os destinos oficiais em um só lugar.");

            float top=474;
            channelCard(cv,30,top,372,top+122,"IG","Instagram","Acompanhe nossas novidades");
            channelCard(cv,388,top,730,top+122,"TT","TikTok","Conteúdos rápidos");
            channelCard(cv,30,top+140,372,top+262,"YT","YouTube","Tutoriais e conteúdo completo");
            channelCard(cv,388,top+140,730,top+262,"FB","Facebook","Canal oficial");
            channelCard(cv,30,top+280,372,top+402,"KW","Kwai","Conteúdo oficial");
            channelCard(cv,388,top+280,730,top+402,"TG","Telegram","Comunidade e avisos");
            channelCard(cv,30,top+420,372,top+542,"GH","GitHub","Nossos projetos");
            channelCard(cv,388,top+420,730,top+542,"IN","LinkedIn","Conexões profissionais");

            gradient(cv,30,1050,730,1178,18,c("#2D2107"),c("#070808"),c("#88641E"));
            text(cv,"Precisa de ajuda?",53,1095,20,WHITE,true);
            text(cv,"Abra o suporte oficial sem sair do Ecossistema.",53,1126,13,MUTED,false);
            text(cv,"Suporte  ›",610,1140,14.5f,GOLD,true);

            round(cv,30,1200,730,1265,15,c("#080909"),c("#49412E"));
            centered(cv,"✓  Destinos oficiais e verificados",380,1242,12.8f,GOLD,true);
        }

        private void support(Canvas cv) {
            title(cv,"Contato e suporte","Ajuda oficial dentro do Ecossistema BlackGold.");
            hero(cv,"BLACKGOLD  •  SUPORTE",
                    "Fale com a equipe.",
                    "Canal oficial e verificado.",
                    "A abertura do contato fica sempre sob seu controle.");

            gradient(cv,30,510,730,675,20,c("#181713"),c("#070808"),c("#81621F"));
            round(cv,54,545,132,623,17,c("#090A0A"),c("#8E6920"));
            centered(cv,"✉",93,597,24,GOLD,true);
            text(cv,"Atendimento oficial",160,560,21,WHITE,true);
            text(cv,"Fale diretamente com a equipe BlackGold.",160,594,13.3f,MUTED,false);
            gradient(cv,482,612,704,658,12,c("#FFD865"),c("#EBAE28"),c("#FFD76A"));
            centered(cv,"Abrir contato  →",593,642,14.5f,c("#211705"),true);

            text(cv,"O que você encontra aqui",30,735,22,WHITE,true);

            String[][] cards = {
                    {"✓","Canal oficial","Destino vindo do manifesto verificado."},
                    {"↗","Abertura sob seu controle","Nenhum redirecionamento automático."},
                    {"BG","Ecossistema integrado","Navegação consistente com o restante do app."}
            };
            float y=770;
            for(String[] item:cards){
                gradient(cv,30,y,730,y+104,16,c("#141513"),c("#070808"),c("#5F4D24"));
                round(cv,48,y+19,112,y+83,14,c("#090A0A"),c("#775A20"));
                centered(cv,item[0],80,y+60,13.5f,GOLD,true);
                text(cv,item[1],136,y+41,17.5f,WHITE,true);
                text(cv,item[2],136,y+70,12.3f,MUTED,false);
                y+=120;
            }

            round(cv,30,1145,730,1235,16,c("#080909"),c("#49412E"));
            centered(cv,"“  Atendimento oficial, simples e transparente.  ”",
                    380,1198,13.4f,c("#D7D7D7"),false);
        }

        private void nav(Canvas cv) {
            reset();
            p.setColor(c("#030404"));
            cv.drawRect(0,NAV_TOP,RW,RH,p);
            p.setStyle(Paint.Style.STROKE);
            p.setStrokeWidth(1f);
            p.setColor(c("#5B4C2A"));
            cv.drawRoundRect(new RectF(0,NAV_TOP,RW,1460),34,34,p);
            p.setStyle(Paint.Style.FILL);

            String[] icons={"⌂","▤","♟","•••"};
            String[] labels={"Início","Orçamentos","Clientes","Mais"};
            float[] x={95,285,475,665};

            for(int i=0;i<4;i++){
                centered(cv,icons[i],x[i],1365,25,i==3?GOLD:c("#D0D0D0"),i==3);
                centered(cv,labels[i],x[i],1410,16,i==3?GOLD:c("#D0D0D0"),i==3);
            }

            p.setColor(GOLD);
            cv.drawRoundRect(new RectF(632,1422,698,1426),2,2,p);
        }

        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            scale=Math.min(getWidth()/RW,getHeight()/RH);
            ox=(getWidth()-RW*scale)/2f;
            oy=(getHeight()-RH*scale)/2f;

            canvas.drawColor(Color.BLACK);
            canvas.save();
            canvas.translate(ox,oy);
            canvas.scale(scale,scale);

            reset();
            p.setColor(BG);
            canvas.drawRect(0,0,RW,RH,p);

            if(page==0) ecosystem(canvas);
            else if(page==1) channels(canvas);
            else support(canvas);

            nav(canvas);
            canvas.restore();
        }

        private boolean hit(float x,float y,float l,float t,float rr,float b){
            return x>=l&&x<=rr&&y>=t&&y<=b;
        }

        @Override
        public boolean onTouchEvent(MotionEvent event) {
            if(event.getAction()!=MotionEvent.ACTION_UP) return true;
            float x=(event.getX()-ox)/scale;
            float y=(event.getY()-oy)/scale;

            if(hit(x,y,650,20,735,95)) {
                if(page==0) finish();
                else { page=0; invalidate(); }
                return true;
            }
            if(page==0 && hit(x,y,30,822,730,958)) {
                page=1; invalidate(); return true;
            }
            if(page==0 && hit(x,y,30,979,730,1115)) {
                page=2; invalidate(); return true;
            }
            if(page==1 && hit(x,y,30,1050,730,1178)) {
                page=2; invalidate(); return true;
            }
            return true;
        }
    }
}
