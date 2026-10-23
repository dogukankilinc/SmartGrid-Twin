function buildDataPage(app, parent)
%BUILDDATAPAGE Veri: SMA Sunny Portal / Data Manager birleşik CSV ve Huawei SmartLogger dosya yükleme,
%   21-sütun doğrulama özeti, işleme (ges.ingest.buildWorkspace) ve veri seti seçimi.
g = uigridlayout(parent, [3 2], RowHeight={"fit", "1x", "fit"}, ColumnWidth={360, "1x"}, Padding=[2 2 2 2], ...
    RowSpacing=6, ColumnSpacing=6);

req = uipanel(g, Title="Desteklenen Veri Biçimleri (SmartGrid-Twin SMA & Huawei SmartLogger)", FontWeight="bold");
req.Layout.Row = 1;
req.Layout.Column = [1 2];
rg = uigridlayout(req, [1 1], Padding=[8 4 8 4]);
uilabel(rg, WordWrap="on", FontSize=11.5, Text= ...
    "• SmartGrid-Twin (SMA Sunny Portal / Data Manager M — Birleşik CSV): 'Analysis Pro - Week - Data Manager Smart Grid Laboratory - *.csv' " + ...
    "(UTF-8, sep=;, 14 satır üstveri + 21 sütun). Tek dosyada hem WR13TL22-8231 evirici (P_ac, V_dc, I_dc, U_L1, I_L1, f_grid, R_iso), " + ...
    "hem Satellite/SmartGridLab meteoroloji (G_horiz, T_amb, T_mod, WindSpeed), hem de tesis sayacı (P_ac,sys, SchedP_Pct) yer alır.   " + ...
    "• Huawei SmartLogger (Çoklu CSV): Meteoroloji + Kabin/İnvertör + SmartLogger + Tesis sayacı dosyaları (UTF-16LE, TAB ayraçlı).");

lp = uipanel(g, Title="Dosya ekle", FontWeight="bold");
lp.Layout.Row = 2;
lp.Layout.Column = 1;
lg = uigridlayout(lp, [12 1], RowHeight=[repmat({30}, 1, 7) {"fit", 28, 32, "fit", "1x"}], Padding=[8 6 8 6], RowSpacing=4);
kinds = ["sma_combined" "meteo" "inverter" "logger" "plant"];
labels = [ ...
    "⚡  SMA Birleşik Rapor CSV ekle (SmartGridLab)"
    "1️⃣  Meteoroloji dosyası ekle"
    "2️⃣  Kabin / invertör dosyaları ekle"
    "3️⃣  SmartLogger dosyası ekle"
    "4️⃣  Tesis sayacı dosyası ekle"];
for i = 1:numel(kinds)
    k = kinds(i);
    uibutton(lg, Text=labels(i), HorizontalAlignment="left", ButtonPushedFcn=@(~, ~) app.dataAdd(k));
end
uibutton(lg, Text="📁  Klasörden toplu yükle (alt klasörler dahil)", HorizontalAlignment="left", ...
    ButtonPushedFcn=@(~, ~) app.dataAddFolder());
uibutton(lg, Text="✖  Listeyi temizle", HorizontalAlignment="left", ButtonPushedFcn=@(~, ~) app.dataClear());
uilabel(lg, Text="Veri seti adı:", FontWeight="bold");
app.Dt.Name = uieditfield(lg, Value="yeni_veri", Tooltip="Çalışma alanı klasörü: workspace/<ad>");
app.Dt.Process = uibutton(lg, Text="⚙  İşle ve panele yükle", FontWeight="bold", BackgroundColor=[0.10 0.45 0.91], ...
    FontColor=[1 1 1], ButtonPushedFcn=@(~, ~) app.dataProcess());
app.Dt.Progress = uilabel(lg, Text="", WordWrap="on", FontColor=[0.3 0.35 0.4]);
app.Dt.Log = uitextarea(lg, Editable="off", FontSize=11, Value="");

rp = uipanel(g, Title="Seçilen dosyalar", FontWeight="bold");
rp.Layout.Row = 2;
rp.Layout.Column = 2;
rpg = uigridlayout(rp, [2 1], RowHeight={"fit", "1x"}, Padding=[4 4 4 4]);
app.Dt.Summary = uilabel(rpg, Text="Henüz dosya eklenmedi.", WordWrap="on", FontSize=12);
app.Dt.Table = uitable(rpg, ColumnName=["Dosya" "Tür" "Cihaz" "Kabin" "İlk zaman" "Son zaman" "Not"], RowName={}, ...
    FontSize=11, ColumnWidth={"auto", 90, 95, 50, 115, 115, "auto"});

sp = uipanel(g, Title="Gösterilen veri seti", FontWeight="bold");
sp.Layout.Row = 3;
sp.Layout.Column = [1 2];
sg = uigridlayout(sp, [1 4], ColumnWidth={"1x", 240, "fit", "fit"}, Padding=[8 4 8 4]);
app.Dt.Current = uilabel(sg, Text="", WordWrap="on");
app.Dt.Sets = uidropdown(sg, Items="Eğitim verisi (varsayılan)", ItemsData="", Tooltip="İşlenmiş veri setleri (workspace/)");
uibutton(sg, Text="Bu veri setine geç", ButtonPushedFcn=@(~, ~) app.loadDataset(string(app.Dt.Sets.Value)));
uibutton(sg, Text="↻", ButtonPushedFcn=@(~, ~) app.renderDataPage(true), Tooltip="Listeyi yenile");
app.Dt.Files = table();
end
