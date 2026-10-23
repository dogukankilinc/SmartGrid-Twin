function buildForecastTabs(app)
%BUILDFORECASTTABS Isıl kısma / termal kayıp tahmini, arıza riski & erken uyarı (R_iso + kısa kopma), geriye dönük doğrulama.
root = app.Cfg.paths.root;
try
    app.Fc.K1 = load(fullfile(root, "artifacts", "v2", "k01_thermal.mat"));
catch
    app.Fc.K1 = [];
end
try
    app.Fc.K2 = load(fullfile(root, "artifacts", "v2", "k02_early_warning.mat"));
catch
    app.Fc.K2 = [];
end

% --- Isıl kısma & Termal Kayıp Tahmini
g = app.Fc.ThermalGrid;
top = uigridlayout(g, [1 3], ColumnWidth={"1x", "fit", 230}, Padding=[0 0 0 0]);
top.Layout.Row = 1;
top.Layout.Column = [1 2];
app.Fc.ThermalInfo = uilabel(top, Text="", WordWrap="on", FontWeight="bold");
uilabel(top, Text="Yarının havası:");
app.Fc.WxMode = uidropdown(top, Items=["Ölçülen hava (tahmin yerine, geriye dönük)" "Son günün havası (internetsiz)"], ...
    ItemsData=["measured" "persist"], ValueChangedFcn=@(~, ~) app.renderForecast(true), ...
    Tooltip="Geçmiş oynatmada hava tahmini arşivi olmadığından ertesi günün ölçülen havası 'mükemmel tahmin' olarak kullanılabilir; gerçek kullanımda internet hava tahmini girer.");
app.Fc.ThermalTable = uitable(g, ColumnName=["Birim" "Son gün gerçek (sa)" "Yarın tahmin (sa)" "Beklenen kayıp" "Tahmini tepe sıcaklık (°C)"], ...
    RowName={}, FontSize=11, SelectionType="row", SelectionChangedFcn=@(src, ~) app.onTablePick(src));
app.Fc.ThermalTable.Layout.Row = 2;
app.Fc.ThermalTable.Layout.Column = 1;
rg = uigridlayout(g, [2 1], RowHeight={"1x", "1x"}, Padding=[0 0 0 0]);
rg.Layout.Row = 2;
rg.Layout.Column = 2;
app.Fc.ThermalAxes = uiaxes(rg);
disableDefaultInteractivity(app.Fc.ThermalAxes);
app.Fc.ThermalText = uitextarea(rg, Editable="off", FontSize=11.5);
lines = [
    "SmartGrid-Twin Termal İkiz & Kısma Tahmini (Faiman Rüzgar Soğutmalı Model):"
    "• T_cell,dyn = T_amb + G_poa / (U_0 + U_1 · v_wind) ile rüzgar hızının soğutma etkisi hesaba katılır."
    "• MPP zarfında dV > +6% ve dI < -8% (çalışma noktasının Voc'ye kayması) ile kısma ve verim kaybı öngörülür."];
if ~isempty(app.Fc.K1) && isfield(app.Fc.K1, "res") && isfield(app.Fc.K1, "periods")
    try
        K = app.Fc.K1.res;
        mt = dictionary(["Oracle" "Adaptive" "Hybrid" "PersWx" "Yesterday" "Clim"], ["sabit ikiz" "uyarlanır ikiz" "MELEZ (kullanılan)" ...
            "ikiz, son günün havası" "taban: dünkü kısma" "taban: geçen yıl aynı ay"]);
        lines(end+1) = "Doğrulama (F1 / MAE / r):";
        for p = 1:min(2, height(app.Fc.K1.periods))
            lines(end+1) = app.Fc.K1.periods.Name(p) + ":"; %#ok<AGROW>
            R = K(K.Period == p, :);
            for i = 1:height(R)
                mName = R.Method(i);
                if isKey(mt, mName), mName = mt(mName); end
                lines(end+1) = sprintf("  %s: F1 %.2f · MAE %.2f sa · r %.2f", mName, R.F1(i), R.MAE(i), R.R(i)); %#ok<AGROW>
            end
        end
    catch
    end
end
app.Fc.ThermalText.Value = lines(:);

% --- Arıza riski & erken uyarı (R_iso + DC Kısa Kopma + Reset)
g = app.Fc.RiskGrid;
app.Fc.RiskInfo = uilabel(g, Text="", WordWrap="on", FontWeight="bold");
app.Fc.RiskInfo.Layout.Row = 1;
app.Fc.RiskInfo.Layout.Column = [1 2];
lg = uigridlayout(g, [4 1], RowHeight={"fit", "1x", "fit", "1x"}, Padding=[0 0 0 0], RowSpacing=4);
lg.Layout.Row = 2;
lg.Layout.Column = 1;
uilabel(lg, Text="DC Dizi Kısa Kopma & Yalıtım Direnci (R_iso) Erken Uyarıları (tıklayın → Analiz)", FontWeight="bold");
app.Fc.StringTable = uitable(lg, ColumnName=["Birim" "Kanal" "Kısa kopma / R_iso" "Son olay" "Öneri"], RowName={}, FontSize=11, ...
    ColumnWidth={80, 50, 115, 110, "1x"}, SelectionType="row", SelectionChangedFcn=@(src, ~) app.onTablePick(src));
uilabel(lg, Text="Termal & Yalıtım Bakım Önceliği (R_iso min & Faiman ΔT)", FontWeight="bold");
app.Fc.CoolTable = uitable(lg, ColumnName=["Sıra" "Birim" "Kısma / Verim Kaybı (%)" "Min R_iso (kΩ) / 60–68°C Oranı (%)"], ...
    RowName={}, FontSize=11, SelectionType="row", SelectionChangedFcn=@(src, ~) app.onTablePick(src));
app.Fc.RiskText = uitextarea(g, Editable="off", FontSize=11.5);
app.Fc.RiskText.Layout.Row = 2;
app.Fc.RiskText.Layout.Column = 2;
app.Fc.RiskText.Value = [
    "SmartGrid-Twin Erken Uyarı ve Öncü Göstergeler (Precursors):"
    ""
    "1) DC Yalıtım Direnci (R_iso [kOhm]) Zayıflaması:"
    "   • Tavan değer 3000 kOhm'dur. Sabah çiyi/nemde 1153–1350 kOhm bandına inip öğlen 3000 kOhm'a dönmesi normaldir."
    "   • Sıcak ve kuru öğle saatlerinde R_iso < 1500 kOhm kalması veya < 1000 kOhm altına inmesi kablo/konnektör izolasyon erken uyarısıdır."
    ""
    "2) 4-Kadranlı MPP Zarfı Kısa Kopmalar ve Reset (SchedP_Pct = 0.00%) İmzası:"
    "   • Son 7 günde dI < -60% kısa kopmaları veya ızgara dışı (:10, :25, :50) 0.00% reset el-sıkışmaları (qRebootEvent) kalıcı kesinti öncüsüdür."
    "   • Kanonik saha doğrulaması: 29 Temmuz 11:45 (R_iso=1153 kOhm, U_L1=0V), 29 Ağustos 11:30 (V_dc=230V MPP->Voc sıçraması), 03 Eylül 18:50 reset."];

% --- Geriye dönük doğrulama
g = app.Fc.BacktestGrid;
app.Fc.BtInfo = uilabel(g, WordWrap="on", FontWeight="bold", Text= ...
    "Geçmiş saha olayları ve arızalar: bir satır seçin → olaydan önceki DC akım/gerilim zarfı ve kısa kopmalar grafikte. " + ...
    "Altta: termal/kısma tahmininin gerçekleşen ile karşılaştırması.");
app.Fc.BtInfo.Layout.Row = 1;
app.Fc.BtInfo.Layout.Column = [1 2];
app.Fc.EvTable = uitable(g, ColumnName=["Birim" "PV" "Olay başlangıcı" "Süre (gün)" "Önceden uyarı" "Öncü süre (gün)" "Kısa kopma / Kanıt"], ...
    RowName={}, FontSize=11, SelectionType="row", SelectionChangedFcn=@(src, ~) app.onEventPick(src));
app.Fc.EvTable.Layout.Row = 2;
app.Fc.EvTable.Layout.Column = 1;
bg = uigridlayout(g, [2 1], RowHeight={"1x", "1x"}, Padding=[0 0 0 0]);
bg.Layout.Row = 2;
bg.Layout.Column = 2;
app.Fc.EvAxes = uiaxes(bg);
disableDefaultInteractivity(app.Fc.EvAxes);
title(app.Fc.EvAxes, "Bir olay seçin");
app.Fc.BtAxes = uiaxes(bg);
disableDefaultInteractivity(app.Fc.BtAxes);
if ~isempty(app.Fc.K1) && isfield(app.Fc.K1, "bt") && ~isempty(app.Fc.K1.bt)
    B = app.Fc.K1.bt;
    [gg, dl] = findgroups(B.Day);
    fa = splitapply(@sum, B.Actual, gg);
    fh = splitapply(@(x) sum(x, "omitnan"), B.Hybrid, gg);
    plot(app.Fc.BtAxes, dl, fa, "-", Color=[0.76 0.09 0.36], LineWidth=1.6);
    hold(app.Fc.BtAxes, "on");
    plot(app.Fc.BtAxes, dl, fh, "--", Color=[0.10 0.35 0.75], LineWidth=1.4);
    hold(app.Fc.BtAxes, "off");
    ylabel(app.Fc.BtAxes, "Günlük kısma / kayıp (saat)");
    legend(app.Fc.BtAxes, ["Gerçekleşen" "Tahmin (melez, bir gün önce)"], Location="northwest");
    title(app.Fc.BtAxes, "Termal kısma: bir gün önceden tahmin vs gerçekleşen");
    grid(app.Fc.BtAxes, "on");
end
end
