// HOPARLÖR TESTİ - goz_animasyon + PAM8403 ses testi (ESP32 DAC GPIO25 -> PAM8403 L-IN)
// Gözler/servo aynen goz_animasyon gibi çalışır, üstüne ses testi eklendi.
// Seri Monitör (115200) komutları:
//   1 = 1 kHz bip      2 = kısa melodi      3 = frekans taraması (200 Hz -> 4 kHz)
//   + = ses aç         - = ses kıs          0 = sustur
// Açılışta 3 notalı "merhaba" sesi çalar. Ses çalarken ağız sesle birlikte açılıp kapanır.
// Bağlantı: GPIO25 -> PAM8403 L-IN, ESP32 GND -> PAM8403 GND (ses girişi GND'si), PAM8403 5V/GND -> 5V (VIN)/GND,
//           hoparlör -> L+ / L-  (L- 'yi asla GND'ye bağlama, köprü çıkış).
#include <Adafruit_GFX.h>
#include <Adafruit_ST7789.h>
#include <SPI.h>
#include <ESP32Servo.h>
#include <driver/dac_continuous.h>

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

// Servo
int servoAci = SERVO_ORTA, servoHedef = SERVO_ORTA;
unsigned long sonServo = 0;


// ===================== SES (dahili DAC, GPIO25) =====================
#define SAMPLE_RATE 16000
volatile int sesSwing = 120;          // genlik: 128 ± sesSwing (8..120). Cızırtı/bozulma varsa kıs
volatile float sesSeviye = 0;        // 0..1, ağız animasyonu için
dac_continuous_handle_t dacHandle = nullptr;

struct Nota { uint16_t f; uint16_t ms; };   // f=0 -> sus (es), ms=0 -> bitti
const Nota ACILIS[] = {{784,110},{988,110},{1319,220},{0,0}};
const Nota BIP[]    = {{1000,500},{0,0}};
const Nota MELODI[] = {{523,180},{659,180},{784,180},{1047,300},{0,90},{784,160},{1047,420},{0,0}};

volatile const Nota* istekNota = nullptr;
volatile bool istekVar = false, istekSweep = false, istekDur = false;

void sesCal(const Nota* n) { istekNota = n; istekSweep = false; istekDur = false; istekVar = true; }
void sesSweep()            { istekNota = nullptr; istekSweep = true; istekDur = false; istekVar = true; }
void sesDur()              { istekNota = nullptr; istekSweep = false; istekDur = true; istekVar = true; }

#include "merhaba_ses.h"
volatile bool istekMerhaba = false;
// ---- Akış (PC'den gelen 8-bit 16 kHz PCM) halka tamponu ----
#define RING_N 32768
uint8_t ring[RING_N];
volatile uint32_t ringW = 0, ringR = 0;      // tek yazan (loop) / tek okuyan (ses görevi)
volatile uint32_t akisKalan = 0;             // seriden beklenen bayt
volatile bool akisCal = false;               // ses görevi akışı çalıyor
inline uint32_t ringDolu() { return ringW - ringR; }
void dacYaz(uint8_t* b, size_t n) {
  // Basit yontem: her ornegi dacWrite ile yaz (calisan bip testindeki gibi)
  static uint32_t t = micros();
  for (size_t i = 0; i < n; i++) { while ((int32_t)(micros() - t) < 62) {} t += 62; dacWrite(25, b[i]); }
  vTaskDelay(1); t = micros();
}

void sesGorevi(void*) {
  uint8_t buf[256];
  // Açılış "pat" sesini önle: 0 -> 128 yumuşak geçiş
  for (int blk = 0; blk < 4; blk++) { for (int i = 0; i < 256; i++) buf[i] = (blk * 256 + i) * 128 / 1024; dacYaz(buf, 256); }

  const Nota* n = nullptr;
  uint32_t notaKalan = 0, notaTop = 0, sweepKalan = 0;
  const uint32_t SWEEP_TOP = SAMPLE_RATE * 3;
  const uint32_t ZARF = SAMPLE_RATE / 200;   // 5 ms giriş/çıkış (tık sesi olmasın)
  float f = 0, faz = 0;
  for (;;) {
    if (istekVar) {
      istekVar = false;
      n = (const Nota*)istekNota; notaKalan = 0; notaTop = 0;
      sweepKalan = istekSweep ? SWEEP_TOP : 0;
      if (istekDur) { n = nullptr; sweepKalan = 0; }
    }
    if (istekMerhaba) {   // "Merhaba" kaydini cal, agiz ses seviyesine gore oynar
      istekMerhaba = false;
      for (uint32_t p = 0; p < MERHABA_LEN; p += 256) {
        int m = min((uint32_t)256, MERHABA_LEN - p); float tp = 0;
        for (int i = 0; i < m; i++) { int d = (int)pgm_read_byte(&MERHABA[p + i]) - 128; buf[i] = constrain(128 + d * sesSwing / 120, 0, 255); tp = max(tp, abs(d) / 128.0f); }
        sesSeviye = tp; dacYaz(buf, m);
      }
      sesSeviye = 0;
    }
    if (akisCal || ringDolu() > 0) {    // PC akışı
      // önce biraz tampon dolsun (underrun olmasın)
      if (!akisCal) { if (ringDolu() < 4096 && akisKalan > 0) { vTaskDelay(2); continue; } akisCal = true; }
      uint32_t d = ringDolu(); float tp = 0;
      if (d == 0) { if (akisKalan == 0) { akisCal = false; sesSeviye = 0; continue; }
        for (int i = 0; i < 64; i++) buf[i] = 128; dacYaz(buf, 64); continue; }
      int m = min((uint32_t)256, d);
      for (int i = 0; i < m; i++) { int v = (int)ring[(ringR + i) % RING_N] - 128; buf[i] = constrain(128 + v * sesSwing / 120, 0, 255); tp = max(tp, abs(v) / 100.0f); }
      ringR += m; sesSeviye = min(1.0f, tp); dacYaz(buf, m);
      if (ringDolu() == 0 && akisKalan == 0) { akisCal = false; sesSeviye = 0; Serial.println("SES_BITTI"); }
      continue;
    }
    float tepe = 0;
    for (int i = 0; i < 256; i++) {
      float amp = 0;
      if (sweepKalan) {
        float p = 1.0f - sweepKalan / (float)SWEEP_TOP;
        f = 200.0f * powf(20.0f, p);                       // 200 Hz -> 4000 Hz (logaritmik)
        uint32_t gecen = SWEEP_TOP - sweepKalan;
        amp = min(1.0f, min(gecen, sweepKalan) / (float)ZARF);
        sweepKalan--;
      } else if (n) {
        if (notaKalan == 0) {
          if (n->ms == 0) { n = nullptr; }
          else { f = n->f; notaTop = notaKalan = (uint32_t)n->ms * SAMPLE_RATE / 1000; n++; }
        }
        if (notaKalan) {
          uint32_t gecen = notaTop - notaKalan;
          amp = (f > 0) ? min(1.0f, min(gecen, notaKalan) / (float)ZARF) : 0;
          notaKalan--;
        }
      }
      int v = 128;
      if (amp > 0) {
        faz += 2.0f * PI * f / SAMPLE_RATE; if (faz > 2.0f * PI) faz -= 2.0f * PI;
        v = 128 + (int)(sesSwing * amp * sinf(faz));
      }
      if (amp > tepe) tepe = amp;
      buf[i] = (uint8_t)constrain(v, 0, 255);
    }
    sesSeviye = tepe;
    dacYaz(buf, 256);
  }
}

void sesKur() {
  dac_continuous_config_t cfg = {};
  cfg.chan_mask = DAC_CHANNEL_MASK_CH0;      // CH0 = GPIO25
  cfg.desc_num  = 4;
  cfg.buf_size  = 512;
  cfg.freq_hz   = SAMPLE_RATE;
  cfg.offset    = 0;
  cfg.clk_src   = DAC_DIGI_CLK_SRC_DEFAULT;   // varsayilan saat (APLL cizirti yapti)
  cfg.chan_mode = DAC_CHANNEL_MODE_SIMUL;
  if (true) { dacWrite(25,128);
    Serial.println("DAC basit mod (GPIO25)");
  } else Serial.println("DAC hazir (GPIO25)");
  xTaskCreatePinnedToCore(sesGorevi, "ses", 4096, nullptr, 3, nullptr, 0);   // çekirdek 0, gözler çekirdek 1'de
}

int disAci = -1; unsigned long disZaman = 0;   // PC'den gelen kafa açısı (yüz takibi)
char satir[24]; int satirN = 0;
void satirIsle();
void seriKomut() {
  while (Serial.available()) {
    if (akisKalan > 0) {   // ham ses baytları
      uint32_t bos = RING_N - ringDolu(); if (bos == 0) return;
      int n = min((uint32_t)Serial.available(), min((uint32_t)akisKalan, bos));
      uint32_t w = ringW % RING_N; n = min(n, (int)(RING_N - w));
      n = Serial.readBytes(ring + w, n); ringW += n; akisKalan -= n; continue;
    }
    char c = Serial.read();
    if (satirN > 0 || c == 'A' || c == 'E' || c == 'S' || c == 'V') {
      if (c == '\n' || c == '\r') { satir[satirN] = 0; if (satirN) satirIsle(); satirN = 0; }
      else if (satirN < 23) satir[satirN++] = c;
      continue;
    }
    switch (c) {
      case '1': sesCal(BIP);    Serial.println("Bip 1 kHz"); break;
      case '2': sesCal(MELODI); Serial.println("Melodi"); break;
      case '3': sesSweep();     Serial.println("Tarama 200 Hz -> 4 kHz"); break;
      case 'm': istekMerhaba = true; Serial.println("Merhaba"); break;
      case '0': sesDur();       Serial.println("Sus"); break;
      case '+': sesSwing = min(120, sesSwing + 12); Serial.printf("Ses: %d/120\n", sesSwing); break;
      case '-': sesSwing = max(8, sesSwing - 12);   Serial.printf("Ses: %d/120\n", sesSwing); break;
      default: break;
    }
  }
}

void modAyarla(Mod m);
void satirIsle() {
  int v = atoi(satir + 1);
  switch (satir[0]) {
    case 'A': disAci = constrain(v, SERVO_MIN, SERVO_MAX); disZaman = millis(); break;   // A<aci>
    case 'E': if (v >= 0 && v < MOD_SAYI) { modAyarla((Mod)v); sonrakiMod = millis() + 15000; } break;  // E<mod>
    case 'V': sesSwing = constrain(v, 0, 120); break;   // V<genlik>
    case 'S': if (v > 0) { akisKalan = v; Serial.println("AKIS_OK"); } break;  // S<uzunluk> + ham PCM
  }
}
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
  if (sesSeviye > 0.05) { // ses çalarken ağız konuşur gibi açılır
    int ah = 6 + (int)(sesSeviye * (12 + 10 * sin(millis() / 45.0)));
    agizC->fillRoundRect(cx - 30, AH / 2 - ah / 2, 60, max(6, ah), 6, CYAN);
    if (ah > 12) agizC->fillRoundRect(cx - 24, AH / 2 - ah / 2 + 3, 48, ah - 6, 4, SIYAH);
    return;
  }
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
  Serial.setRxBufferSize(16384);
  Serial.begin(921600);
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
//SERVO IPTAL   kafa.attach(SERVO_PIN, 500, 2400);
//SERVO IPTAL   kafa.write(SERVO_ORTA);

  sesKur();
  delay(300); istekMerhaba = true;   // acilista "Merhaba" der
  Serial.println("Komutlar: 1=bip 2=melodi 3=tarama +/-=ses 0=sus");

  randomSeed(esp_random());
  modAyarla(NORMAL);
  sonrakiKirp = millis() + 1500; sonrakiBakis = millis() + 1000; sonrakiMod = millis() + 8000;
}

void loop() {
  seriKomut();
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

  // Kafa bakışla birlikte döner (sınırlar 30..150)
  bool dis = disAci >= 0 && simdi - disZaman < 3000;
  if (dis) { servoHedef = disAci; hgx = 0; gx = yaklas(gx, 0, 0.3); }
  else servoHedef = constrain(SERVO_ORTA + (int)(bx1 * 55), SERVO_MIN, SERVO_MAX);
  if (simdi - sonServo >= (dis ? 8 : 15)) { // 1 derece / 15 ms
    sonServo = simdi;
    if (servoAci < servoHedef) servoAci++;
    else if (servoAci > servoHedef) servoAci--;
//SERVO IPTAL     kafa.write(constrain(servoAci, SERVO_MIN, SERVO_MAX));
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
