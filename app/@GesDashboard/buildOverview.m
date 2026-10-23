function buildOverview(app, parent)
%BUILDOVERVIEW Genel Bakış: 6 KPI kartı (DC/AC güç & verim, üretim, DC bara & R_iso, L1 şebeke, termal/rüzgar, durum/gökyüzü)
%   | enerji grafiği (Hafta/Ay/Yıl) | meteoroloji/elektriksel özet, durum sayıları ve günlük/invertör performans tablosu.
g = uigridlayout(parent, [2 2], RowHeight={96, "1x"}, ColumnWidth={"2x", "1x"}, Padding=[2 2 2 2], ...
    RowSpacing=6, ColumnSpacing=6);

kp = uigridlayout(g, [1 6], ColumnWidth=repmat({"1x"}, 1, 6), Padding=[0 0 0 0], ColumnSpacing=6);
kp.Layout.Row = 1;
kp.Layout.Column = [1 2];
cards = [
    "Power"   "Anlık DC / AC Güç & Verim"       "Anlık DC/AC güç (kW), M1 beklenen güç ve evirici dönüşüm verimi (η_inv = P_ac / P_dc)."
    "Today"   "Bugünkü Üretim & Özgül Verim"    "Bugün 00:00'dan şimdiye üretilen enerji, performans (%) ve spesifik AC üretim (kWh/kWp)."
    "Month"   "DC Bara (V_dc, I_dc) & R_iso"    "DC dizi gerilimi (V), DC akımı (A), Yalıtım Direnci (R_iso kΩ) ve bu ayki enerji üretimi."
    "Total"   "L1 Şebeke Kalitesi & Röle"       "Koşullu L1 şebeke gerilimi U_L1,cond (V), frekans f_grid (Hz), k/18 röle oranı ve toplam üretim."
    "States"  "Durum (Alarm/Uyarı) & Termal"    "Aktif sağlık durumu, Faiman dinamik hücre sıcaklığı T_cell,dyn vs Ross T_mod ve rüzgar hızı."
    "Sky"     "Gökyüzü & POA Işınım"            "32° eğimli düzlem ışınımı G_poa (W/m²), yatay G_horiz ve bulutsuz gök açıklık indeksi (Kc)."];
for i = 1:size(cards, 1)
    p = uipanel(kp, BackgroundColor="w", Tooltip=cards(i, 3));
    cg = uigridlayout(p, [3 1], RowHeight={"1x", "fit", "fit"}, Padding=[10 2 10 4], RowSpacing=0, BackgroundColor="w");
    app.Ov.(cards(i, 1)) = uilabel(cg, Text="—", FontSize=17.5, FontWeight="bold", Tooltip=cards(i, 3));
    app.Ov.(cards(i, 1) + "Sub") = uilabel(cg, Text="", FontSize=11, FontColor=[0.18 0.45 0.25], Tooltip=cards(i, 3), WordWrap="on");
    uilabel(cg, Text=cards(i, 2), FontSize=10.5, FontColor=[0.42 0.47 0.52], Tooltip=cards(i, 3), WordWrap="on");
end

ep = uipanel(g, Title="Üretim: gerçek ve olması gereken (beklenen) enerji", FontWeight="bold");
ep.Layout.Row = 2;
ep.Layout.Column = 1;
eg = uigridlayout(ep, [2 1], RowHeight={"fit", "1x"}, Padding=[6 4 6 6]);
bar0 = uigridlayout(eg, [1 5], ColumnWidth={70, 70, 70, "1x", "fit"}, Padding=[0 0 0 0], ColumnSpacing=4);
modes = ["week" "month" "year"];
labels = ["Hafta" "Ay" "Yıl"];
for i = 1:3
    m = modes(i);
    app.Ov.ModeButtons.(m) = uibutton(bar0, Text=labels(i), ButtonPushedFcn=@(~, ~) app.setEnergyMode(m));
end
app.Ov.EnergyInfo = uilabel(bar0, Text="", FontColor=[0.3 0.35 0.4], HorizontalAlignment="right");
app.Ov.EnergyInfo.Layout.Column = [4 5];
app.Ov.Axes = uiaxes(eg);
disableDefaultInteractivity(app.Ov.Axes);

rg = uigridlayout(g, [3 1], RowHeight={"fit", "fit", "1x"}, Padding=[0 0 0 0], RowSpacing=6);
rg.Layout.Row = 2;
rg.Layout.Column = 2;
wp = uipanel(rg, Title="Meteoroloji, Termal İkiz (Faiman vs Ross) & L1 Şebeke Özeti", FontWeight="bold");
wg = uigridlayout(wp, [1 1], Padding=[8 4 8 4]);
app.Ov.Weather = uilabel(wg, Text="—", WordWrap="on", FontSize=11.5);
sp = uipanel(rg, Title="Durum sayıları (Anlık / Bugün / Son 7 gün)", FontWeight="bold");
sg = uigridlayout(sp, [1 1], Padding=[2 2 2 2]);
app.Ov.StatusTable = uitable(sg, ColumnName=["Durum" "Anlık" "Bugün" "Son 7 gün"], RowName={}, FontSize=11, ...
    ColumnWidth={"1x", 58, 58, 76}, Tooltip="Bugün: en az 1 saat süren en ağır durum. Son 7 gün: en az 2 günde görülen en ağır durum.");
lp = uipanel(rg, Title="Performans & Kayıp Özeti (tıklayın → Analiz)", FontWeight="bold");
app.Ov.LowPanel = lp;
lg = uigridlayout(lp, [1 1], Padding=[2 2 2 2]);
app.Ov.LowTable = uitable(lg, ColumnName=["Birim / Gün" "Durum" "Perf. %" "Kayıp" "Ana neden / R_iso"], RowName={}, ...
    FontSize=11, ColumnWidth={90, 80, 58, 70, "1x"}, SelectionType="row", ...
    SelectionChangedFcn=@(src, ~) app.onTablePick(src));
end
