// Robot gözleri animasyonu - ESP32 + Waveshare 2" ST7789V (320x240) + SG90/MG90S kafa servosu (hedefte detach)
#include <Adafruit_GFX.h>
#include <Adafruit_ST7789.h>
#include <SPI.h>
#include <ESP32Servo.h>

// --- Pinler ---
#define TFT_CS 5
#define TFT_DC 16
#define TFT_RST 17
#define TFT_BL 4
#define SERVO_PIN 13

// --- Servo ayarları (kesin sınırlar) ---
#define SERVO_ORTA 90
#define SERVO_MIN 30
#define SERVO_MAX 150

Adafruit_ST7789 tft(TFT_CS, TFT_DC, TFT_RST);
Servo kafa;

// Her göz için küçük tuval (tam ekran tuval belleğe sığmıyor)
#define GW 130
#define GH 130
GFXcanvas16 *solC, *sagC;
#define SOL_X 22
#define SAG_X 168
#define GOZ_Y 30
// Ağız tuvali
#define AW 120
#define AH 40
GFXcanvas16 *agizC;
#define AGIZ_X 100
#define AGIZ_Y 190

#define CYAN 0x07FF
#define CYAN_KOYU 0x0451
#define BEYAZ 0xFFFF
#define SIYAH 0x0000

enum Mod { NORMAL, MUTLU, SASKIN, UYKULU, KIZGIN, MERAKLI, MOD_SAYI };
Mod mod = NORMAL;
const char *modAd[] = {"normal", "mutlu", "saskin", "uykulu", "kizgin", "merakli"};

// Bakış (yumuşak geçiş için mevcut ve hedef)
float gx = 0, gy = 0, hgx = 0, hgy = 0;
// Göz boyutu (mod geçişleri yumuşak)
float gozW = 100, gozH = 100, hW = 100, hH = 100, yaricap = 28, hR = 28;
float kapak = 0, hKapak = 0;   // uykulu göz kapağı (0..1)
float kizgin = 0, hKizgin = 0; // kızgın kaş eğimi (0..1)
float mutlu = 0, hMutlu = 0;   // alttan kavis (0..1)
float egik = 0, hEgik = 0;     // meraklı: bir göz büyük, diğeri küçük (-1..1)
float gulum = 0, hGulum = 0;   // ağız gülümseme (-1..1)

// Göz kırpma
float kirp = 1.0; // 1 açık, 0 kapalı
int kirpFaz = 0;  // 0 yok, 1 kapanıyor, 2 açılıyor
unsigned long sonrakiKirp = 0, sonrakiBakis = 0, sonrakiMod = 0;
bool ciftKirp = false;

// Servo (hedefte hold edince detach -> SG90 titreme/akım azalır)
int servoAci = SERVO_ORTA, servoHedef = SERVO_ORTA;
unsigned long sonServo = 0, servoSettledMs = 0;
bool servoAttached = true;
#define SERVO_DETACH_MS 3000

float yaklas(float a, float b, float k) { return a + (b - a) * k; }
float easeInOut(float t) { return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2; }

// Bakış geçişi (ease-in-out)
float bx0 = 0, by0 = 0, bx1 = 0, by1 = 0; unsigned long bBas = 0, bSure = 400;

void modAyarla(Mod m) {
  mod = m;
  hW = 100; hH = 100; hR = 28; hKapak = 0; hKizgin = 0; hMutlu = 0; hEgik = 0; hGulum = 0.3;
  switch (m) {
    case MUTLU: hMutlu = 1; hH = 90; hGulum = 1; break;
    case SASKIN: hW = 110; hH = 115; hR = 55; hGulum = -0.6; break; // kocaman yuvarlak
    case UYKULU: hKapak = 0.55; hH = 95; hGulum = 0; break;
    case KIZGIN: hKizgin = 1; hH = 85; hGulum = -1; break;
    case MERAKLI: hEgik = (random(2) ? 1 : -1); hGulum = 0.1; break;
    default: break;
  }
}

// Tek gözü tuvale çiz. taraf: -1 sol, +1 sağ
void gozCiz(GFXcanvas16 *c, int taraf) {
  c->fillScreen(SIYAH);
  float olcek = 1.0 + egik * 0.18 * taraf;
  float w = gozW * olcek, h = gozH * olcek * kirp;
  if (h < 6) h = 6;
  float cx = GW / 2 + gx * 12, cy = GH / 2 + gy * 10;
  int x = cx - w / 2, y = cy - h / 2;
  int r = min((int)yaricap, (int)(min(w, h) / 2) - 1);
  if (r < 2) r = 2;
  c->fillRoundRect(x, y, w, h, r, CYAN);
  // Kenarda koyu halka efekti
  c->drawRoundRect(x, y, w, h, r, CYAN_KOYU);

  if (kirp > 0.35) {
    // Göz bebeği + parlama (bakış yönüne daha çok kayar)
    int pr = (mod == SASKIN ? 16 : 22) * olcek;
    int px = cx + gx * 22, py = cy + gy * 18 * kirp;
    c->fillCircle(px, py, pr, CYAN_KOYU);
    c->fillCircle(px, py, pr * 0.6, 0x0186);
    c->fillCircle(px - pr * 0.4, py - pr * 0.45, pr * 0.32, BEYAZ);
    c->fillCircle(px + pr * 0.45, py + pr * 0.35, pr * 0.14, BEYAZ);
  }
  // Mutlu: alttan siyah daire ile ters kavis (^ ^)
  if (mutlu > 0.02) {
    int dr = w * 0.75;
    c->fillCircle(cx, y + h + dr - h * 0.45 * mutlu, dr, SIYAH);
  }
  // Uykulu: üst kapak
  if (kapak > 0.02) {
    c->fillRect(0, 0, GW, y + h * kapak, SIYAH);
    c->drawFastHLine(x + 4, y + h * kapak, w - 8, CYAN_KOYU);
  }
  // Kızgın: iç üst köşeden eğik kaş (üçgen)
  if (kizgin > 0.02) {
    int d = h * 0.55 * kizgin;
    if (taraf < 0) c->fillTriangle(x - 2, y - 2, x + w + 2, y - 2, x + w + 2, y + d, SIYAH);
    else c->fillTriangle(x - 2, y - 2, x + w + 2, y - 2, x - 2, y + d, SIYAH);
  }
}

void agizCiz() {
  agizC->fillScreen(SIYAH);
  int cx = AW / 2 + gx * 8;
  if (mod == SASKIN) { // küçük "o" ağız
    agizC->fillCircle(cx, AH / 2, 10, CYAN);
    agizC->fillCircle(cx, AH / 2, 6, SIYAH);
    return;
  }
  // Parabol şeklinde gülümseme / somurtma
  for (int i = -40; i <= 40; i++) {
    float t = i / 40.0;
    int yy = AH / 2 + gulum * 12 * (1 - t * t) * (-1) + gulum * 6;
    yy = AH / 2 - (int)(gulum * 12 * (t * t - 0.5));
    agizC->fillCircle(cx + i, yy, 2, CYAN);
  }
}

void bakisBaslat(float x, float y, unsigned long sure) {
  bx0 = hgx; by0 = hgy; bx1 = x; by1 = y; bBas = millis(); bSure = sure;
}

void setup() {
  Serial.begin(115200);
  pinMode(TFT_BL, OUTPUT); digitalWrite(TFT_BL, HIGH);
  tft.init(240, 320);
  tft.setSPISpeed(20000000);
  tft.setRotation(1);
  tft.fillScreen(SIYAH);

  solC = new GFXcanvas16(GW, GH);
  sagC = new GFXcanvas16(GW, GH);
  agizC = new GFXcanvas16(AW, AH);
  if (!solC->getBuffer() || !sagC->getBuffer() || !agizC->getBuffer()) {
    tft.setTextColor(0xF800); tft.setTextSize(2); tft.setCursor(10, 100);
    tft.print("Bellek yetersiz!");
    Serial.println("Tuval ayrilamadi"); while (1) delay(1000);
  }

  kafa.setPeriodHertz(50);
  kafa.attach(SERVO_PIN, 500, 2400);
  kafa.write(SERVO_ORTA);

  randomSeed(esp_random());
  modAyarla(NORMAL);
  sonrakiKirp = millis() + 1500; sonrakiBakis = millis() + 1000; sonrakiMod = millis() + 8000;
}

void loop() {
  unsigned long simdi = millis();

  // --- Bakış: rastgele aralıklarla yeni noktaya ease-in-out ile kay ---
  if (simdi > sonrakiBakis) {
    float x, y;
    if (random(4) == 0) { x = 0; y = 0; }
    else { x = random(-100, 101) / 100.0; y = random(-70, 71) / 100.0; }
    if (mod == UYKULU) { y = 0.4; x *= 0.5; }
    bakisBaslat(x, y, random(250, 600));
    sonrakiBakis = simdi + random(900, 3500);
  }
  float t = min(1.0f, (simdi - bBas) / (float)bSure);
  float e = easeInOut(t);
  hgx = bx0 + (bx1 - bx0) * e; hgy = by0 + (by1 - by0) * e;
  gx = yaklas(gx, hgx, 0.5); gy = yaklas(gy, hgy, 0.5);

  // Kafa bakışla birlikte döner (sınırlar 30..150); hedefte 3 sn sonra detach
  servoHedef = constrain(SERVO_ORTA + (int)(bx1 * 55), SERVO_MIN, SERVO_MAX);
  if (simdi - sonServo >= 15) { // 1 derece / 15 ms
    sonServo = simdi;
    if (servoAci != servoHedef) {
      if (servoAci < servoHedef) servoAci++;
      else servoAci--;
      if (!servoAttached) { kafa.attach(SERVO_PIN, 500, 2400); servoAttached = true; }
      kafa.write(constrain(servoAci, SERVO_MIN, SERVO_MAX));
      servoSettledMs = simdi;
    } else if (servoAttached && simdi - servoSettledMs > SERVO_DETACH_MS) {
      kafa.detach();
      servoAttached = false;
    }
  }

  // --- Doğal göz kırpma (bazen çift kırpma) ---
  if (kirpFaz == 0 && simdi > sonrakiKirp) { kirpFaz = 1; ciftKirp = random(5) == 0; }
  float kirpHiz = (mod == UYKULU) ? 0.12 : 0.28;
  if (kirpFaz == 1) { kirp -= kirpHiz; if (kirp <= 0.05) { kirp = 0.05; kirpFaz = 2; } }
  else if (kirpFaz == 2) {
    kirp += kirpHiz * 0.8;
    if (kirp >= 1) {
      kirp = 1;
      if (ciftKirp) { ciftKirp = false; kirpFaz = 1; }
      else { kirpFaz = 0; sonrakiKirp = simdi + random(2000, (mod == UYKULU) ? 3500 : 6000); }
    }
  }

  // --- Mod değişimi ---
  if (simdi > sonrakiMod) {
    Mod yeni = (random(3) == 0) ? NORMAL : (Mod)random(MOD_SAYI);
    modAyarla(yeni);
    Serial.printf("Mod: %s\n", modAd[yeni]);
    if (yeni == SASKIN) { kirpFaz = 1; } // şaşırınca hızlı kırp
    sonrakiMod = simdi + random(5000, 11000);
  }
  // Mod parametreleri yumuşak geçiş
  gozW = yaklas(gozW, hW, 0.15); gozH = yaklas(gozH, hH, 0.15); yaricap = yaklas(yaricap, hR, 0.15);
  kapak = yaklas(kapak, hKapak, 0.1); kizgin = yaklas(kizgin, hKizgin, 0.15);
  mutlu = yaklas(mutlu, hMutlu, 0.15); egik = yaklas(egik, hEgik, 0.1); gulum = yaklas(gulum, hGulum, 0.15);
  // Uykulu modda göz kapağı hafifçe salınır
  if (mod == UYKULU) kapak = hKapak + 0.08 * sin(simdi / 700.0);

  // --- Çiz ve aktar (titreşimsiz) ---
  gozCiz(solC, -1);
  tft.drawRGBBitmap(SOL_X, GOZ_Y, solC->getBuffer(), GW, GH);
  gozCiz(sagC, 1);
  tft.drawRGBBitmap(SAG_X, GOZ_Y, sagC->getBuffer(), GW, GH);
  agizCiz();
  tft.drawRGBBitmap(AGIZ_X, AGIZ_Y, agizC->getBuffer(), AW, AH);
}
