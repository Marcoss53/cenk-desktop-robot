// =====================================================================
//  Masaüstü Robot v1 (sabit gövde, kafa sadece sağ-sol döner)
//  Batuhan için - Bambu Lab A2L - OpenSCAD parametrik model
//  Koordinatlar: robot çerçevesi, mm. Ön = -Y, yukarı = +Z.
//  part = "assembly" | "exploded" | parça adı (baskı yönünde)
// =====================================================================
part = "assembly";
pan  = 0;          // kafa dönüş açısı (derece), -90..+90
explode = 0;       // patlatılmış görünüm mesafesi
$fn = 72;

// ---------------- genel ----------------
clr   = 0.3;       // montaj boşluğu
wall  = 2.5;       // gövde duvarı
hwall = 2.4;       // kafa kabuğu duvarı
ins_d = 2.6;       // M3 kendinden kılavuzlu (self-tap) kılavuz delik (eskiden 4.0 insert)
ins_h = 8.0;       // vida tutunma derinliği (~6-8 mm)
m3    = 3.4;       // M3 geçiş deliği (clearance, değişmedi)
m3_tap= 2.6;       // M3 kendinden kılavuzlu delik (ins_d ile aynı)
m2_tap= 1.7;       // M2 vida kılavuz delik

// ---------------- gövde (body) ----------------
bw = 88; bd = 74; bh = 56;     // dış ölçü
br = 18;                       // dikey köşe yarıçapı
bchamf = 6;                    // üst kenar pahı (ters baskı için)
ceil_t = 3;                    // tavan kalınlığı
zc = bh - ceil_t;              // tavanın alt yüzü (61)
// kolonlar (taban plakası vidaları, kendinden kılavuzlu)
cols = [[-33,-26],[33,-26],[-33,26],[6,30.4]];

// ---------------- MG90S (TowerPro çizimi) ----------------
sv_L = 22.8; sv_W = 12.2;      // gövde
sv_tabL = 32.5; sv_tab_t = 2.5; sv_tab_z = 15.9; // tab alt yüzü gövde altından
sv_hole = 27.8;                // tab delik aralığı
sv_body_h = 22.7;              // kutu yüksekliği
sv_tower_h = 4.0;              // dişli kulesi (kutunun üstünde)
sv_spline_h = 2.8;             // mil (kulenin üstünde)
sv_shaft_off = 5.9;            // milin gövde merkezinden kaçıklığı
standoff = 5;                  // tavandan servo tablarına ayak
sv_tabtop = zc - standoff;                       // 56
sv_bottom = sv_tabtop - sv_tab_z - sv_tab_t;     // 37.6
sv_spline_top = sv_bottom + sv_body_h + sv_tower_h + sv_spline_h; // 67.1

// ---------------- boyun göbeği (neck_hub) ----------------
hub_d = 52; hub_h = 10;
hub_z0 = bh + 1;               // 65
hub_z1 = hub_z0 + hub_h;       // 75
horn_len = 33; horn_pocket = 3.6;
slot_r = 18.5; slot_w = 10;    // kablo kanalı (tavan) / göbek kablo deliği
hub_screw_r = 22;
hub_screw_a = [190, 210, 330, 350];

// ---------------- kafa ----------------
hW = 104; hD = 88; hH = 84;    // elipsoid tam ölçü
hexp = 2.8;                    // süper-elipsoid üssü (2=küre, büyüdükçe dolgun)
hflat_y = -38;               // ön düz yüz (vizör)
hbot = -35;                    // kafa altı (düz)
head_z = hub_z1 - hbot;        // kafa merkezinin yüksekliği (111)
vis_w = 62; vis_h = 36; vis_r = 10; vis_z = -6; vis_t = 1.6;
win_w = 42; win_h = 32;        // vizör penceresi (aktif alan 40.8x30.6)
// Ekran: 2.0" ST7789 240x320 IPS (Waveshare tipi) PCB 58x35, aktif alan 40.8x30.6
d_pcb_w = 58; d_pcb_h = 35; d_mod_t = 4.0; d_conn = 6;
d_front = hflat_y + vis_t + hwall;   // -38 : camın ön yüzü
cam_z = 21;                    // kamera lensi yüksekliği (kafa merkezine göre)
// Kamera: Logitech C270 kartı 21x58 (lens bölgesi 23.5 genişlik), lens ekseni kartın bir ucundan 13 mm
c_w = 23.5; c_L = 58; c_up = 13; c_pcb = 1.6; c_lens = 9; c_lens_d = 8.5;
c_front = -22.5;               // kart ön yüzü (y)
// Ekran ve kamera braket kolonları
dcols = [[-34,vis_z],[34,vis_z]];
ccols = [[-6,30],[6,30]];
// yan 'kulak' diskleri
ear_d = 30; ear_z = -4; ear_out = 2.5;
// Kafa arka kapak vidaları (y=0 bölme düzlemi)
hcols = [[-40,10],[40,10],[-30,-27],[30,-27]];

// ======================= yardımcılar =======================
module rrect(w,h,r){ offset(r) square([w-2*r,h-2*r],center=true); }
module rbox(w,d,h,r){ linear_extrude(h) rrect(w,d,r); }
module oblong(r_c, a, rad_w, tan_w, h){
  // kutupsal oblong delik (r_c yarıçapında, a açısında)
  rotate([0,0,a]) translate([r_c,0,0])
    linear_extrude(h) hull(){ for(s=[-1,1]) translate([0,s*(tan_w-rad_w)/2]) circle(d=rad_w); }
}

// ======================= GÖVDE =======================
module body_outer(){
  hull(){
    rbox(bw,bd,bh-bchamf,br);
    translate([0,0,bh-bchamf]) rbox(bw-2*bchamf,bd-2*bchamf,bchamf,br-bchamf);
  }
}
module body_inner(){
  translate([0,0,-1]) rbox(bw-2*wall,bd-2*wall,zc+1,br-wall);
}
module body_shell(){
  difference(){
    union(){
      difference(){ body_outer(); body_inner(); }
      // kolonlar (tavandan plakaya kadar)
      intersection(){
        union(){ for(c=cols) translate([c[0],c[1],0]) cylinder(d=9,h=zc+0.1); }
        body_outer();
      }
      // servo ayakları
      difference(){
        for(s=[-1,1]) translate([0,sv_shaft_off+s*sv_hole/2,sv_tabtop]) cylinder(d=6.5,h=standoff+0.1);
        translate([-(sv_W+2*clr)/2,sv_shaft_off-(sv_L+2*clr)/2,sv_tabtop-1]) cube([sv_W+2*clr,sv_L+2*clr,standoff+2]);
      }
      // hoparlör yuvası halkası (ön duvar içinde)
      translate([0,-bd/2+wall-0.1,spk_z]) rotate([-90,0,0]) difference(){ cylinder(d=spk_d+0.6+2.4,h=2.6); translate([0,0,-1]) cylinder(d=spk_d+0.6,h=5); }
      // alt merkezleme dudağı (kaide güvertesindeki açıklığa girer)
      difference(){
        translate([0,0,-deck_t]) linear_extrude(deck_t+0.1) difference(){ rrect(bw-2*wall-2*clr,bd-2*wall-2*clr,br-wall-clr); rrect(bw-2*wall-2*clr-2.4,bd-2*wall-2*clr-2.4,br-wall-clr-1.2); }
        for(c=cols) translate([c[0],c[1],-5]) cylinder(d=boss_d+2*clr,h=10);
      }
    }
    // kolon kılavuz delikleri (M3 self-tap)
    for(c=cols) translate([c[0],c[1],-0.1]) cylinder(d=ins_d,h=ins_h);
    // servo ayak kılavuz delikleri (M2 servo vidası)
    for(s=[-1,1]) translate([0,sv_shaft_off+s*sv_hole/2,sv_tabtop-1]) cylinder(d=m2_tap,h=standoff);
    // tavan: servo kulesi deliği
    translate([0,0,zc-1]) linear_extrude(ceil_t+2) hull(){ circle(d=14); translate([0,7]) circle(d=9); }
    // tavan: kablo kanalı (önde, ±90°)
    translate([0,0,zc-1]) linear_extrude(ceil_t+2) cable_arc2d();
    // hoparlör ızgarası
    translate([0,-bd/2-1,spk_z]) rotate([-90,0,0]) grille_holes(wall+2);
  }
}
module cable_arc2d(){
  difference(){
    union(){
      intersection(){
        difference(){ circle(r=slot_r+slot_w/2); circle(r=slot_r-slot_w/2); }
        translate([-50,-100]) square([100,100]);
      }
      for(a=[180,360]) rotate(a) translate([slot_r,0]) circle(d=slot_w);
    }
  }
}
module grille_holes(h){
  for(i=[-3:3]) for(j=[-3:3]){
    x = i*4.2 + (j%2==0?0:2.1); y=j*3.7;
    if (x*x/(15*15) + y*y/(11*11) <= 1) translate([x,y,0]) cylinder(d=2.2,h=h,$fn=16);
  }
}
// hoparlör (40 mm 4R 3W, 40x20)
spk_d = 40; spk_h = 20; spk_z = zc - spk_d/2 - 0.5;   // 40.5
// ---------------- KAİDE (yuvarlak, LED + USB hub) ----------------
ped_r = 57; ped_h = 16; ped_wall = 3; deck_t = 2.4; floor_t = 3;
ped_in = ped_r - ped_wall;          // 54
floor_r = ped_in + 1.0;             // taban plakası yarıçapı (55)
ftop = -ped_h + floor_t;            // taban üst yüzü (-13)
boss_d = 8;
// LED çubuk (WS2812B 8'li, 57x10.3x3.4) - önde, dik
led_len = 57; led_w = 10.3; led_t = 3.4;
led_y1 = -44.8;                     // çubuğun ön yüzü
led_zc = ftop + led_w/2 + 0.2;
// ESP32 30 pin (51.5 x 28.3) - uzun ekseni X, bileşen yüzü yukarı, pinler aşağı (dupont altta)
esp_L = 51.5; esp_W = 28.3; esp_cx = -4; esp_cy = -4;
esp_z = 6;                          // PCB alt yüzü
// MAX98357A (18x19) tepsisi
amp_c = [-39, 9];
// USB hub: Adafruit CH334F 4 port (31.6 x 20.4), USB-C arkaya bakar
hub_c = [-8.5, 32.2]; hub_L = 31.6; hub_W = 20.4; hub_so = 3;
hub_holes = [[-7.66,-13.26],[7.66,-13.26],[-7.66,13.26],[7.66,13.26]];
usbc_z = ftop + hub_so + 1.6 + 1.6;  // USB-C ağzı merkezi (-6.8)
// opsiyonel harici 5V girişi: USB-C PCB dönüştürücü (20.3 x 15.2)
pwr_c = [20, 36]; pwr_L = 20.3; pwr_W = 15.2;
// ağırlık kabı
wcup = [52, 17.9, 9]; wcup_y = -29.95;
// lastik ayaklar
feet = [[44,0],[-44,0],[0,44],[0,-44]];

module ped_profile(){ // r-z profili (dış). Üst kenar 45° pah + küçük yuvarlatma: ters baskıda desteksiz
  offset(r=1) offset(delta=-1) polygon([[0,-ped_h],[ped_r-0.8,-ped_h],[ped_r,-ped_h+0.8],[ped_r,-5],[ped_r-5,0],[0,0]]);
}
module pedestal(){
  difference(){
    rotate_extrude($fn=144) ped_profile();
    // iç boşluk (güverte altı)
    translate([0,0,-ped_h-1]) cylinder(r=ped_in,h=ped_h+1-deck_t,$fn=144);
    // taban plakası yuvası
    translate([0,0,-ped_h-1]) cylinder(r=floor_r+clr,h=floor_t+1,$fn=144);
    // güverte açıklığı = gövde iç çizgisi
    translate([0,0,-5]) linear_extrude(10) rrect(bw-2*wall,bd-2*wall,br-wall);
    // ön LED yarığı (dış yüzeyde yay gibi görünür)
    translate([0,-ped_r-2,led_zc]) rotate([-90,0,0]) linear_extrude(12) rrect(44,3.5,1.7);
    // arka: USB hub USB-C (PC'ye giden tek kablo)
    translate([hub_c[0],ped_in-6,usbc_z]) rotate([-90,0,0]) linear_extrude(12) rrect(13,7.5,3.2);
    // arka: opsiyonel harici 5V USB-C
    translate([pwr_c[0],ped_in-6,usbc_z]) rotate([-90,0,0]) linear_extrude(12) rrect(13,7.5,3.2);
    // ikon çentikleri: hub portu üstünde küçük nokta
    translate([hub_c[0],ped_r-1.2,usbc_z+6.2]) rotate([-90,0,0]) cylinder(d=1.6,h=3);
  }
}
module base_plate(){
  difference(){
    union(){
      translate([0,0,-ped_h]) cylinder(r=floor_r,h=floor_t,$fn=144);
      // gövde kolonlarına çıkan burçlar
      for(c=cols) translate([c[0],c[1],ftop-0.1]) cylinder(d=boss_d,h=-ftop+0.1);
      // ESP32 köprüsü: iki ince duvar (başlıklar arasında) + uç durdurucu
      for(yy=[-6.5,4.5]) translate([esp_cx-21,esp_cy+yy-1,ftop-0.1]) cube([42,2,esp_z-ftop+0.1]);
      translate([esp_cx-esp_L/2-2.4,esp_cy-3,ftop-0.1]) cube([2.2,6,esp_z+4.5-ftop]);
      // amfi tepsisi
      translate([amp_c[0],amp_c[1],ftop-0.1]) difference(){ rbox(19.6+3.2,20.6+3.2,3.1,1.5); translate([0,0,1.1]) rbox(19.6,20.6,10,0.5); }
      // hub ayakları
      for(h=hub_holes) translate([hub_c[0]+h[0],hub_c[1]+h[1],ftop-0.1]) cylinder(d=5,h=hub_so+0.1);
      // güç kartı pabuçları + yan kılavuzlar
      for(sx=[-1,1]) for(sy=[-1,1]) translate([pwr_c[0]+sx*(pwr_W/2-2)-2,pwr_c[1]+sy*(pwr_L/2-2)-2,ftop-0.1]) cube([4,4,hub_so+0.1]);
      for(sx=[-1,1]) translate([pwr_c[0]+sx*(pwr_W/2+clr+0.8)-0.8,pwr_c[1]-6,ftop-0.1]) cube([1.6,12,hub_so+3]);
      // ağırlık kabı
      translate([0,wcup_y,ftop-0.1]) difference(){ rbox(wcup[0],wcup[1],wcup[2],2); translate([0,0,1]) rbox(wcup[0]-3.2,wcup[1]-3.2,20,1.2); }
      // LED rayları
      translate([-25,led_y1-1.0,ftop-0.1]) cube([50,1.0,2.1]);
      translate([-25,led_y1+led_t+0.5,ftop-0.1]) cube([50,1.5,5.1]);
    }
    // kolon vidaları: M3 geçiş + alttan vida başı cebi
    for(c=cols) translate([c[0],c[1],-ped_h-1]) { cylinder(d=m3,h=ped_h+2); cylinder(d=6.6,h=1+3.5); }
    // hub vida kılavuzları (M2.5 kendinden kılavuzlu)
    for(h=hub_holes) translate([hub_c[0]+h[0],hub_c[1]+h[1],ftop-1]) cylinder(d=2.1,h=hub_so+2,$fn=16);
    // lastik ayak yuvaları
    for(f=feet) translate([f[0],f[1],-ped_h-0.1]) cylinder(d=10.6,h=1.3);
    // ESP32 köprüsünde kablo bağı yuvası
    translate([esp_cx-2,esp_cy-10,esp_z-6]) cube([4,20,3]);
  }
}

// ======================= BOYUN GÖBEĞİ =======================
module neck_hub(){
  translate([0,0,hub_z0]) difference(){
    cylinder(d=hub_d,h=hub_h);
    // alt: servo kolu (çift kol horn) cebi
    translate([0,0,-0.1]) linear_extrude(horn_pocket+0.1) hull(){ for(s=[-1,1]) translate([s*(horn_len/2-2.5),0]) circle(d=6.2); circle(d=8); }
    translate([0,0,-0.1]) cylinder(d=9,h=horn_pocket+0.1);
    // horn vidaları için kılavuz delikler
    for(x=[-14,-10,10,14]) translate([x,0,horn_pocket-0.5]) cylinder(d=1.5,h=5,$fn=12);
    // orta vida erişim deliği
    translate([0,0,-1]) cylinder(d=7,h=hub_h+2);
    // kablo deliği (önde)
    translate([0,0,-1]) oblong(slot_r,270,slot_w,18,hub_h+2);
    // kafa vidaları için kılavuz delikleri (M3 self-tap, üstten)
    for(a=hub_screw_a) rotate([0,0,a]) translate([hub_screw_r,0,hub_h-ins_h]) cylinder(d=ins_d,h=ins_h+1);
    // üst kenar pahı
    translate([0,0,hub_h-0.8]) difference(){ cylinder(d=hub_d+2,h=2); cylinder(d1=hub_d,d2=hub_d-2,h=1); }
  }
}

// ======================= KAFA =======================
function spow(v,m) = (v<0?-1:1)*pow(abs(v),m);
module superellipsoid(a,b,c,n=2.8,N=64){
  m = 2/n;
  pts = [ for(i=[0:N]) for(j=[0:N-1])
          let(ph=-90+180*i/N, th=360*j/N)
          [a*spow(cos(ph),m)*spow(cos(th),m), b*spow(cos(ph),m)*spow(sin(th),m), c*spow(sin(ph),m)] ];
  faces = [ for(i=[0:N-1]) for(j=[0:N-1])
            let(a0=i*N+j, a1=i*N+(j+1)%N, b0=(i+1)*N+j, b1=(i+1)*N+(j+1)%N)
            [a0,b0,b1,a1] ];
  polyhedron(points=pts, faces=faces, convexity=4);
}
module head_solid(s=0){
  // s: içe ofset (kabuk iç yüzeyi için)
  if (s<=0) for(sx=[-1,1]) translate([sx*(hW/2-8),0,ear_z]) rotate([0,sx*90,0])
    hull(){ cylinder(d=ear_d,h=8+ear_out-1); cylinder(d=ear_d-2,h=8+ear_out); }
  intersection(){
    superellipsoid(hW/2-s,hD/2-s,hH/2-s,hexp,72);
    translate([-100,hflat_y+(s>0?vis_t+hwall:0),hbot+(s>0?3:0)]) cube([200,200,200]);
  }
}
module head_shell(front=true){
  difference(){
    union(){
      difference(){ head_solid(0); head_solid(hwall); }
      // braket kolonları (y=0 bölme düzleminden öne doğru) + kabuğa bağlayan kanatlar
      if (front) intersection(){ head_solid(0.5); union(){
        for(c=dcols) { col_y(c,8,-dbr_y1); web(c,[sign(c[0]),0],-dbr_y1); }
        for(c=ccols) { col_y(c,8,-cbr_y1); web(c,[0,1],-cbr_y1); }
        for(c=hcols) { col_y(c,9,10); web(c, abs(c[1])>20 ? [0,-1] : [sign(c[0]),0], 10); }
      }}
      // arka kapak için kolonlar (y>0) - head_back tarafı
      if (!front) intersection(){ head_solid(0.5); for(c=hcols) translate([c[0],0,c[1]]) rotate([-90,0,0]) cylinder(d=9,h=60); }
    }
    // vizör cebi
    translate([0,hflat_y-1,vis_z]) rotate([-90,0,0]) linear_extrude(1+vis_t) rrect(vis_w,vis_h,vis_r);
    // ekran penceresi
    translate([0,hflat_y-1,vis_z]) rotate([-90,0,0]) linear_extrude(10) rrect(win_w+2,win_h+1,2.5);
    // kamera deliği + pah
    translate([0,-60,cam_z]) rotate([-90,0,0]) cylinder(d=c_lens_d+0.6,h=40);
    translate([0,hflat_y-0.5,cam_z]) rotate([-90,0,0]) cylinder(d1=13,d2=c_lens_d+0.6,h=2.6);
    // boyun: kablo deliği + vida delikleri
    translate([0,0,hbot-1]) oblong(slot_r,270,slot_w,18,6);
    for(a=hub_screw_a) rotate([0,0,a]) translate([hub_screw_r,0,hbot-1]) cylinder(d=m3,h=6);
    // kolon delikleri
    for(c=dcols) translate([c[0],1,c[1]]) rotate([90,0,0]) { cylinder(d=m3,h=1-dbr_y1+0.5); cylinder(d=6.2,h=6); }
    for(c=ccols) translate([c[0],1,c[1]]) rotate([90,0,0]) { cylinder(d=m3,h=1-cbr_y1+0.5); cylinder(d=6.2,h=6); }
    // arka kapak vidası: ön yarıda kılavuz (self-tap), arka yarıda havşa/derin oyuk
    for(c=hcols) translate([c[0],0,c[1]]) rotate([90,0,0]) translate([0,0,-0.1]) cylinder(d=ins_d,h=ins_h);
    for(c=hcols) translate([c[0],0,c[1]]) rotate([-90,0,0]) { translate([0,0,-1]) cylinder(d=m3,h=70); translate([0,0,8]) cylinder(d=6.4,h=70); }
    // arka havalandırma yarıkları
    for(i=[-1:1]) translate([0,40,8+i*7]) rotate([-90,0,0]) linear_extrude(20) rrect(36,3,1.4);
  }
}
module col_y(c,d,L){ translate([c[0],0,c[1]]) rotate([90,0,0]) cylinder(d=d,h=L); }
module web(c,dir,L){ // kolonu en yakın kabuk duvarına bağlayan 3 mm kanat
  translate([c[0],0,c[1]]) rotate([0,-atan2(dir[1],dir[0]),0]) translate([0,-L,-1.5]) cube([40,L,3]); }
module head_front(){ intersection(){ head_shell(); translate([-100,-100,-100]) cube([200,100,200]); } }
module head_back(){  intersection(){ head_shell(false); translate([-100,0,-100]) cube([200,100,200]); } }

module visor(){
  // siyah vizör plakası (cebe oturur, 0.3 boşluk)
  translate([0,hflat_y,vis_z]) rotate([-90,0,0]) difference(){
    linear_extrude(vis_t) rrect(vis_w-0.6,vis_h-0.6,vis_r-0.3);
    translate([0,0,-1]) linear_extrude(vis_t+2) rrect(win_w,win_h,2);
  }
}

// ekran braketi: ekranı ön duvara bastıran tepsi
dbr_y1 = d_front + d_mod_t + d_conn + 1;   // braket plakası arka yüzü (-27)
module display_bracket(){
  ty0 = d_front + 0.5;               // tepsi duvarlarının ön ucu
  py0 = d_front + d_mod_t + d_conn - 2; // plaka ön yüzü
  intersection(){ head_solid(hwall+0.4);
  difference(){
    union(){
      // plaka
      translate([0,py0,vis_z]) rotate([-90,0,0]) linear_extrude(dbr_y1-py0) rrect(76,d_pcb_h+3,3);
      // PCB'yi kuşatan tepsi duvarları
      translate([0,ty0,vis_z]) rotate([-90,0,0]) linear_extrude(py0-ty0+0.1) difference(){ rrect(d_pcb_w+2*clr+2.4,d_pcb_h+2*clr+2.4,1.5); rrect(d_pcb_w+2*clr,d_pcb_h+2*clr,0.3); }
      // köşe baskı pabuçları (PCB arka köşelerine)
      for(sx=[-1,1]) for(sz=[-1,1]) translate([sx*(d_pcb_w/2-3),d_front+d_mod_t,vis_z+sz*(d_pcb_h/2-3)]) rotate([-90,0,0]) translate([-3,-3,0]) cube([6,6,py0-(d_front+d_mod_t)+0.1]);
      // vida kulakları
      for(c=dcols) translate([c[0],dbr_y1,c[1]]) rotate([90,0,0]) cylinder(d=8,h=6);
    }
    // kablo/konnektör penceresi
    translate([0,py0-1,vis_z]) rotate([-90,0,0]) linear_extrude(20) rrect(44,22,3);
    // vida + somun yuvası
    for(c=dcols) translate([c[0],dbr_y1+1,c[1]]) rotate([90,0,0]) { cylinder(d=m3,h=20); translate([0,0,1+3.6]) cylinder(d=6.4,h=10,$fn=6); }
    // tepsinin alt kenarında kablo çentiği
    translate([0,ty0-1,vis_z-d_pcb_h/2-3]) cube([20,30,6],center=true);
  }
  }
}

// kamera braketi (C270 kartı)
cbr_y0 = c_front + c_pcb;            // kart arka yüzü (-22.9)
cbr_rail = 3.5;                      // arka bileşenler için ray yüksekliği
cbr_y1 = cbr_y0 + cbr_rail + 3;      // plaka arka yüzü (-16.4)
module camera_bracket(){
  zt = cam_z + c_up + 2;            // üst kenar
  zm = -18;                         // bu seviyenin altı sadece orta ayak
  zf = hbot + 3 + clr;              // kafa tabanına basan ayak
  pw2 = c_w/2 + 2.6;
  difference(){
    union(){
      // plaka (üst geniş kısım + orta ayak)
      translate([-pw2,cbr_y0+cbr_rail,zm]) cube([2*pw2,3,zt-zm]);
      // iki yan ayak (ortadaki kablo deliğini ve boyun vidalarını boş bırakır)
      for(s=[-1,1]) translate([s>0?10:-15.5,0,0]) {
        translate([0,cbr_y0+cbr_rail,zf]) cube([5.5,3,zm-zf+1]);
        translate([0,cbr_y0+0.5,zf]) cube([5.5,cbr_rail+2.5,3]);      // taban pabucu
      }
      // raylar: kartın arka yüzü bunlara dayanır
      for(s=[-1,1]) translate([s*(c_w/2-1)-1,cbr_y0,cam_z-(c_L-c_up)]) cube([2,cbr_rail+0.1,c_L]);
      // yan dudaklar (kartın sağa-sola kaymasını önler)
      for(s=[-1,1]) translate([s*(c_w/2+clr+1)-1,cbr_y0-2,zm]) cube([2,2+cbr_rail+0.1,zt-zm]);
    }
    // kolon vidaları (M3 kendinden kılavuz)
    for(c=ccols) translate([c[0],cbr_y1+1,c[1]]) rotate([90,0,0]) cylinder(d=m3_tap,h=12);
    // kart kıskaç vidaları (M2 + pul), dudakların üstünden
    for(p=[[-1,zt-7],[1,zt-7],[-1,zm+4],[1,zm+4]]) translate([p[0]*(c_w/2+clr+1),cbr_y0-3,p[1]]) rotate([-90,0,0]) cylinder(d=m2_tap,h=10,$fn=12);
    // lens bölgesi için boşluk (kartın ön yüzü serbest)
  }
}

// ======================= REFERANS PARÇALAR (sadece görsel) =======================
module ref_servo(){
  color([0.15,0.25,0.55]) translate([0,sv_shaft_off,sv_bottom]){
    translate([-sv_W/2,-sv_L/2,0]) cube([sv_W,sv_L,sv_body_h]);
    translate([-sv_W/2,-sv_tabL/2,sv_tab_z]) cube([sv_W,sv_tabL,sv_tab_t]);
    translate([0,-sv_shaft_off,sv_body_h]) cylinder(d=11.8,h=sv_tower_h);
    translate([0,-sv_shaft_off+6,sv_body_h]) cylinder(d=5.5,h=sv_tower_h);
    color("white") translate([0,-sv_shaft_off,sv_body_h+sv_tower_h]) cylinder(d=4.8,h=sv_spline_h);
  }
  color("white") rotate([0,0,pan]) translate([0,0,sv_spline_top-1.6]) linear_extrude(1.6) hull(){ for(s=[-1,1]) translate([s*(horn_len/2-3),0]) circle(d=4.5); circle(d=7); }
}
module ref_speaker(){
  color([0.2,0.2,0.22]) translate([0,-bd/2+wall+0.1,spk_z]) rotate([-90,0,0]) {
    cylinder(d=spk_d,h=4); translate([0,0,4]) cylinder(d1=spk_d-4,d2=24,h=7); translate([0,0,11]) cylinder(d=22,h=spk_h-11);
  }
}
module ref_esp32(){
  translate([esp_cx,esp_cy,esp_z]){
    color([0.1,0.1,0.12]) translate([-esp_L/2,-esp_W/2,0]) cube([esp_L,esp_W,1.6]);
    color([0.75,0.75,0.78]) translate([-esp_L/2+0.5,-9,1.6]) cube([25.5,18,3.2]);   // WROOM modül (-X ucu)
    color([0.7,0.7,0.7]) translate([esp_L/2-5,-4,1.6]) cube([6,8,3]);              // micro-USB (+X ucu)
    color([0.05,0.05,0.05]) for(s=[-1,1]) translate([-19,s*(esp_W/2-1.3)-1.25,-11]) cube([38.1,2.5,11]);
  }
}
module ref_amp(){ color([0.45,0.2,0.6]) translate([amp_c[0]-9,amp_c[1]-9.5,ftop+1.1]) cube([18,19,1.6]); }
module ref_led(){ color([0.1,0.9,1]) translate([-led_len/2,led_y1+0.15,ftop+0.2]) cube([led_len,led_t,led_w]); }
module ref_led_glow(){ // sadece görsel: yarıktaki ışık
  color([0.2,0.95,1]) render() intersection(){ translate([0,-ped_r-1,led_zc]) rotate([-90,0,0]) linear_extrude(4) rrect(43.6,3.0,1.4); rotate_extrude($fn=144) translate([ped_r-0.6,-ped_h]) square([0.9,ped_h]); } }
module ref_hub(){
  translate([hub_c[0],hub_c[1],ftop+hub_so]){
    color([0.08,0.08,0.1]) translate([-hub_W/2,-hub_L/2,0]) cube([hub_W,hub_L,1.6]);
    color([0.8,0.8,0.82]) translate([-4.5,hub_L/2-6.0,1.6]) cube([9,7.5,3.2]);      // USB-C (1.5 mm taşar)
  }
}
module ref_pwr(){
  translate([pwr_c[0],pwr_c[1],ftop+hub_so]){
    color([0.6,0.1,0.1]) translate([-pwr_W/2,-pwr_L/2,0]) cube([pwr_W,pwr_L,1.6]);
    color([0.8,0.8,0.82]) translate([-4.5,pwr_L/2-6.5,1.6]) cube([9,7.5,3.2]);
  }
}
module ref_display(){
  translate([0,d_front,vis_z]) rotate([-90,0,0]){
    color([0.03,0.03,0.04]) linear_extrude(d_mod_t) rrect(d_pcb_w,d_pcb_h,1);
    color([0.1,0.1,0.1]) translate([0,0,d_mod_t]) linear_extrude(d_conn) square([12,6],center=true);
  }
  // camgöbeği gözler (yer tutucu)
  color([0.1,0.95,1.0]) for(s=[-1,1]) translate([s*10,d_front-0.6,vis_z+1]) rotate([90,0,0]) linear_extrude(0.5)
    difference(){ circle(d=13); translate([0,-1.5]) circle(d=9); translate([-10,-20]) square([20,17]); }
}
module ref_camera(){
  translate([0,c_front,cam_z]) {
    color([0.1,0.35,0.15]) translate([-c_w/2,0,-(c_L-c_up)]) cube([c_w,c_pcb,c_L]);
    color([0.08,0.08,0.08]) rotate([90,0,0]) { translate([-7,-7,0]) cube([14,14,4]); cylinder(d=c_lens_d,h=c_lens); }
  }
}

// ======================= MONTAJ =======================
WHITE=[0.95,0.95,0.94]; GREY=[0.78,0.79,0.81]; BLACK=[0.07,0.07,0.08];
module head_assembly(e=0){
  translate([0,0,head_z+e*1.2]) rotate([0,0,pan]) {
    color(WHITE) head_front();
    color(WHITE) translate([0,e*1.6,0]) head_back();
    color(BLACK) translate([0,-e*1.2,0]) visor();
    color([0.6,0.62,0.65]) translate([0,e*0.5,0]) display_bracket();
    color([0.55,0.57,0.6]) translate([0,e*0.9,0]) camera_bracket();
    if (e==0 || true) { translate([0,-e*0.6,0]) ref_display(); translate([0,e*0.2,0]) ref_camera(); }
  }
}
module assembly(e=0){
  translate([0,0,ped_h]) assembly0(e);
}
module assembly0(e=0){
  color(WHITE) translate([0,0,0]) body_shell();
  color(WHITE) translate([0,0,-e*0.9]) pedestal();
  color(GREY) translate([0,0,-e*1.6]) base_plate();
  translate([0,0,-e*1.6]) { ref_esp32(); ref_amp(); ref_led(); ref_hub(); ref_pwr(); }
  if (e==0) ref_led_glow();
  ref_speaker();
  translate([0,0,e*0.25]) ref_servo();
  color(GREY) translate([0,0,e*0.55]) rotate([0,0,pan]) neck_hub();
  head_assembly(e);
}

// ======================= BASKI YÖNLERİ =======================
if (part=="assembly") assembly(0);
else if (part=="exploded") assembly(explode);
else if (part=="body_shell") translate([0,0,bh]) rotate([180,0,0]) body_shell();          // üst tabla üstünde
else if (part=="base_plate") translate([0,0,ped_h]) base_plate();
else if (part=="pedestal") rotate([180,0,0]) pedestal();                                  // güverte tablada
else if (part=="neck_hub") translate([0,0,hub_z1]) rotate([180,0,0]) neck_hub();          // üst yüz tablada
else if (part=="head_front") rotate([-90,0,0]) head_front();                              // bölme yüzü tablada, ön yukarı
else if (part=="head_back") rotate([90,0,0]) head_back();                                 // bölme yüzü tablada
else if (part=="visor") rotate([90,0,0]) translate([0,-hflat_y,-vis_z]) visor();           // düz
else if (part=="display_bracket") rotate([-90,0,0]) translate([0,-dbr_y1,-vis_z]) display_bracket(); // arka yüz tablada
else if (part=="camera_bracket") rotate([-90,0,0]) translate([0,-cbr_y1,0]) camera_bracket();

// ---- çakışma kontrolü için montaj konumunda tek parça çıktıları ----
module inhead(){ translate([0,0,head_z]) rotate([0,0,pan]) children(); }
if (part=="A_body_shell") body_shell();
if (part=="A_base_plate") base_plate();
if (part=="A_pedestal") pedestal();
if (part=="A_hub") ref_hub();
if (part=="A_pwr") ref_pwr();
if (part=="A_neck_hub") rotate([0,0,pan]) neck_hub();
if (part=="A_head_front") inhead() head_front();
if (part=="A_head_back") inhead() head_back();
if (part=="A_visor") inhead() visor();
if (part=="A_display_bracket") inhead() display_bracket();
if (part=="A_camera_bracket") inhead() camera_bracket();
if (part=="A_servo") ref_servo();
if (part=="A_speaker") ref_speaker();
if (part=="A_esp32") ref_esp32();
if (part=="A_amp") ref_amp();
if (part=="A_led") ref_led();
if (part=="A_display") inhead() ref_display();
if (part=="A_camera") inhead() ref_camera();
