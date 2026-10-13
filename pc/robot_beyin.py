# -*- coding: utf-8 -*-
"""Cenk beyni: yuz takibi + dinle -> anla (STT) -> dusun (LLM) -> konus (TTS) -> ESP32'ye ses akisi."""
import os, sys, time, threading, subprocess, asyncio, re, tempfile, io, wave, argparse
import numpy as np, serial, cv2

DIR = os.path.dirname(os.path.abspath(__file__))
ap = argparse.ArgumentParser()
ap.add_argument("--port", default="COM3"); ap.add_argument("--baud", type=int, default=921600)
ap.add_argument("--kamera", type=int, default=1)
ap.add_argument("--mic", default="Mikrofon (Logi C270 HD WebCam)")
ap.add_argument("--yon", type=int, default=int(os.environ.get("ROBOT_YON", "-1")), help="servo yonu (+1/-1), kafa yuzden kacarsa degistir")
ap.add_argument("--ses", default="tr-TR-AhmetNeural")
ap.add_argument("--esik", type=float, default=0, help="VAD esigi (0=otomatik)")
ap.add_argument("--yuztakip", type=int, default=1); ap.add_argument("--konusma", type=int, default=1)
ap.add_argument("--dondur", type=int, default=int(os.environ.get("ROBOT_KAMERA_DONDUR", "0")), help="kamera goruntusunu dondur: 0/90/180/270")
ap.add_argument("--goster", type=int, default=0)
ap.add_argument("--soyle", default="", help="sadece bu cumleyi soyle ve cik (test)")
ap.add_argument("--yuztest", type=float, default=0, help="N saniye sadece yuz takibi (test)")
args = ap.parse_args()

def log(*a): print(time.strftime("%H:%M:%S"), *a, flush=True)

# ---------------- Seri ----------------
ser = serial.Serial()
ser.port, ser.baudrate, ser.timeout = args.port, args.baud, 0.05
ser.dtr = False; ser.rts = False
ser.open(); time.sleep(0.3)
kilit = threading.Lock()
konusuyor = threading.Event()
def gonder(b):
    with kilit: ser.write(b)
def okuyucu():
    while True:
        try:
            l = ser.readline()
            if l:
                t = l.decode(errors="ignore").strip()
                if t == "SES_BITTI": konusuyor.clear()
        except Exception: time.sleep(0.1)
threading.Thread(target=okuyucu, daemon=True).start()

MODLAR = ["NORMAL", "MUTLU", "SASKIN", "UYKULU", "KIZGIN", "MERAKLI"]
def ifade(ad):
    if ad in MODLAR: gonder(f"E{MODLAR.index(ad)}\n".encode())

def pcm_cal(pcm: bytes):
    """8-bit unsigned 16 kHz PCM'i ESP32'ye gercek zamanli hizla akit."""
    konusuyor.set()
    gonder(f"S{len(pcm)}\n".encode()); time.sleep(0.02)
    on = 12000  # on tampon (bayt)
    gonder(pcm[:on]); t0 = time.time(); gonderilen = on
    while gonderilen < len(pcm):
        hedef = on + int((time.time() - t0) * 16000)       # cihazdaki tampon ~12 KB onde kalsin
        if gonderilen < hedef:
            p = pcm[gonderilen:min(len(pcm), hedef, gonderilen + 2048)]; gonder(p); gonderilen += len(p)
        else: time.sleep(0.02)
    bitis = time.time() + (len(pcm) - (time.time() - t0) * 16000) / 16000 + 2
    while konusuyor.is_set() and time.time() < bitis: time.sleep(0.05)
    konusuyor.clear()

def tts(metin: str) -> bytes:
    import edge_tts
    mp3 = os.path.join(tempfile.gettempdir(), "robi_tts.mp3")
    asyncio.run(edge_tts.Communicate(metin, args.ses, rate="-5%", pitch="-4Hz").save(mp3))
    r = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", mp3, "-af", "highpass=f=120,lowpass=f=4500,acompressor=threshold=0.2:ratio=3,loudnorm=I=-16,alimiter=limit=0.95",
                        "-ac", "1", "-ar", "16000", "-f", "u8", "-"], capture_output=True)
    return r.stdout

def el_anahtar():
    k = os.environ.get("ELEVENLABS_API_KEY")
    if not k:
        try:
            import winreg; k = winreg.QueryValueEx(winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment"), "ELEVENLABS_API_KEY")[0]
        except Exception: k = None
    return k

EL_SES = os.environ.get("EL_SES", "pNInz6obpgDQGcFmaJgB")   # ElevenLabs ses kimligi (Adam). Degistirmek icin EL_SES

def el_tts(metin, k):
    import urllib.request, json
    req = urllib.request.Request(f"https://api.elevenlabs.io/v1/text-to-speech/{EL_SES}?output_format=mp3_44100_128",
        data=json.dumps({"text": metin, "model_id": "eleven_flash_v2_5", "language_code": "tr"}).encode(),
        headers={"xi-api-key": k, "Content-Type": "application/json"})
    mp3 = os.path.join(tempfile.gettempdir(), "robi_el.mp3")
    open(mp3, "wb").write(urllib.request.urlopen(req, timeout=30).read())
    return mp3

def konus(metin):
    log("ROBI:", metin)
    k = el_anahtar()
    if k:
        try:
            # ElevenLabs (opsiyonel, ELEVENLABS_API_KEY). Yoksa ucretsiz edge-tts kullanilir.
            mp3 = el_tts(metin, k)
            # ElevenLabs sesi robotun hoparlorunden: 8-bit DAC icin filtre + sikistirma
            pcm = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", mp3, "-af", "highpass=f=120,lowpass=f=5000,acompressor=threshold=0.2:ratio=3,loudnorm=I=-16,alimiter=limit=0.95",
                                  "-ac", "1", "-ar", "16000", "-f", "u8", "-"], capture_output=True).stdout
            gonder(b"V120\n"); time.sleep(0.05)
            pcm_cal(pcm); return
        except Exception as e: log("ElevenLabs hatasi, eski sese geciliyor:", e)
    try: gonder(b"V120\n"); pcm_cal(tts(metin))
    except Exception as e: log("TTS hatasi:", e)

# ---------------- Yuz takibi ----------------
aci = 90.0
def yuz_takibi(sure=0):
    global aci
    cap = cv2.VideoCapture(args.kamera, cv2.CAP_DSHOW)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640); cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    det = cv2.FaceDetectorYN.create(os.path.join(DIR, "face_yunet.onnx"), "", (320, 240), 0.7)
    son_yuz = time.time(); bas = time.time(); kayip = False; sonra = 0
    while not sure or time.time() - bas < sure:
        ok, f = cap.read()
        if not ok: time.sleep(0.1); continue
        R = {90: cv2.ROTATE_90_CLOCKWISE, 180: cv2.ROTATE_180, 270: cv2.ROTATE_90_COUNTERCLOCKWISE}
        if args.dondur in R: f = cv2.rotate(f, R[args.dondur])
        g = cv2.resize(f, (320, 240))
        _, ff = det.detect(g)
        yuzler = [] if ff is None else [tuple(int(v) for v in r[:4]) for r in ff]
        if len(yuzler):
            x, y, w, h = max(yuzler, key=lambda r: r[2] * r[3])
            hata = ((x + w / 2) - 160) / 160.0          # -1..1 (sag pozitif)
            if abs(hata) > 0.08:                          # olu bolge
                aci += args.yon * hata * 6.0              # P kontrol (kare basina derece)
                aci = max(30, min(150, aci))
            son_yuz = time.time()
            if kayip: kayip = False; ifade("MUTLU")
            if time.time() - sonra > 0.05: gonder(f"A{int(aci)}\n".encode()); sonra = time.time()
            if sure: log(f"yuz x={x+w/2:.0f} hata={hata:+.2f} aci={aci:.0f}")
        elif time.time() - son_yuz > 4 and not kayip:
            kayip = True                                  # yuz yok: firmware kendi bakinir
        if args.goster:
            for (x, y, w, h) in yuzler: cv2.rectangle(g, (x, y), (x + w, y + h), (0, 255, 0), 2)
            cv2.imshow("Robi", g); cv2.waitKey(1)
    cap.release()

# ---------------- Dinleme (VAD) ----------------
def dinle_dongusu(isle):
    mesgul = threading.Event()   # cevap hazirlanirken mikrofonu okumaya devam et (tampon dolmasin)
    def calistir(veri):
        try: isle(veri)
        finally: mesgul.clear()
    cmd = ["ffmpeg", "-loglevel", "error", "-rtbufsize", "64M", "-f", "dshow", "-i", f"audio={args.mic}", "-ac", "1", "-ar", "16000", "-f", "s16le", "-"]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    CER = 480  # 30 ms
    gurultu = []; esik = args.esik; parca = []; sessiz = 0; konusma = False
    log("Kalibrasyon: 2 sn sessiz ol...")
    while True:
        b = p.stdout.read(CER * 2)
        if not b: break
        a = np.frombuffer(b, np.int16).astype(np.float32); rms = float(np.sqrt((a * a).mean()) + 1)
        if not esik:
            gurultu.append(rms)
            if len(gurultu) > 66: esik = max(300.0, np.median(gurultu) * 3.5); log(f"Dinliyorum (esik {esik:.0f}). Konus!")
            continue
        if konusuyor.is_set() or mesgul.is_set(): parca = []; konusma = False; continue   # kendi sesini duymasin
        if rms > esik:
            if not konusma: konusma = True; parca = []; log("...")
            sessiz = 0
        if konusma:
            parca.append(b); sessiz += rms <= esik
            if sessiz > 27 or len(parca) > 500:    # 0.8 sn sessizlik veya 15 sn
                konusma = False
                if len(parca) > 15: mesgul.set(); threading.Thread(target=calistir, args=(b"".join(parca),), daemon=True).start()
                # isle sirasinda biriken mikrofon verisini at
                parca = []

# ---------------- STT + LLM ----------------
def stt(pcm16: bytes) -> str:
    import speech_recognition as sr
    try: return sr.Recognizer().recognize_google(sr.AudioData(pcm16, 16000, 2), language="tr-TR")
    except sr.UnknownValueError: return ""

def llm_istemci():
    from openai import OpenAI
    # Sadece Gemini kullanilir
    k = os.environ.get("GEMINI_API_KEY")
    if not k:
        try:
            import winreg; k = winreg.QueryValueEx(winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment"), "GEMINI_API_KEY")[0]
        except Exception: k = None
    if k: log("LLM: gemini-2.5-flash"); return OpenAI(api_key=k, base_url="https://generativelanguage.googleapis.com/v1beta/openai/"), "gemini-2.5-flash"
    return None, None

gecmis = []
def dusun(soz):
    karakter = open(os.path.join(DIR, "karakter.txt"), encoding="utf-8").read()   # her seferinde okunur, canli duzenlenebilir
    istemci, model = llm_istemci()
    if not istemci: return "[SASKIN] Lan beynim yok! Bilgisayara GEMINI_API_KEY anahtarini girmen lazim kanka."
    gecmis.append({"role": "user", "content": soz})
    r = None
    for md in ["gemini-flash-lite-latest", "gemini-2.5-flash-lite", "gemini-flash-latest", "gemini-2.5-flash"]:   # kota dolunca siradakine gec
        try:
            ek = {"reasoning_effort": "none"} if md.startswith("gemini-2.5") else {}
            r = istemci.chat.completions.create(model=md, max_tokens=1500, temperature=0.9,
                messages=[{"role": "system", "content": karakter}] + gecmis[-12:], **ek); break
        except Exception as e: log("Model", md, "olmadi:", str(e)[:80])
    if r is None: gecmis.pop(); return "[SASKIN] Lan bugunluk kotam doldu kanka, yarin konusuruz."
    cevap = r.choices[0].message.content.strip(); gecmis.append({"role": "assistant", "content": cevap})
    return cevap

sohbet_son = 0  # son konusma zamani (30 sn sohbet penceresi)
def isle(pcm16):
    t = time.time(); soz = stt(pcm16)
    if not soz: return
    log("SEN:", soz, f"({time.time()-t:.1f}s)")
    # Uyandirma kelimesi: sadece "Cenk" denince cevap ver
    global sohbet_son
    cenk = re.search(r"\b(cenk|cengiz)", soz.lower())
    if not cenk and time.time() - sohbet_son > 30: log("(Cenk denmedi, cevap yok)"); return
    sohbet_son = time.time()
    try: cevap = dusun(soz)
    except Exception as e: log("LLM hatasi:", e); cevap = "[SASKIN] Lan kafam karisti, bi daha soyle."
    m = re.match(r"\s*\[(\w+)\]\s*", cevap); duygu = "NORMAL"
    if m: duygu = m.group(1).upper(); cevap = cevap[m.end():]
    ifade(duygu); konus(re.sub(r"[*_#`]", "", cevap)); sohbet_son = time.time()

if __name__ == "__main__":
    if args.soyle: konus(args.soyle); sys.exit()
    if args.yuztest: yuz_takibi(args.yuztest); sys.exit()
    if args.yuztakip: threading.Thread(target=yuz_takibi, daemon=True).start()
    if args.konusma:
        try: dinle_dongusu(isle)
        except KeyboardInterrupt: pass
    else:
        while True: time.sleep(1)
