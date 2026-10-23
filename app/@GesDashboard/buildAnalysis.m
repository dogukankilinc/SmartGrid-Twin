function buildAnalysis(app, parent)
%BUILDANALYSIS Analiz: evirici + ufuk + 4 modlu mühendislik grafiği seçimi | grafik | skalogram şeridi | teşhis/olaylar/geri bildirim.
g = uigridlayout(parent, [4 1], RowHeight={"fit", "1x", 190, 200}, Padding=[2 2 2 2], RowSpacing=5);

tb = uigridlayout(g, [1 10], ColumnWidth={"fit", 95, 64, 64, 72, "fit", 270, "1x", "fit", "fit"}, Padding=[0 0 0 0], ColumnSpacing=4);
uilabel(tb, Text="Cihaz:", FontWeight="bold");
app.An.Inverter = uidropdown(tb, Items=app.Engine.Ids, Value=app.Selected, ...
    ValueChangedFcn=@(src, ~) app.select(string(src.Value)));
hs = ["instant" "day" "week"];
for h = hs
    app.An.HorizonButtons.(h) = uibutton(tb, Text=app.HorizonTr(h), ButtonPushedFcn=@(~, ~) app.applyHorizon(h), ...
        Tooltip="Grafik ve skalogram penceresi: Anlık = bugün, Günlük = değerlendirilen gün, Haftalık = son 7 gün.");
end
uilabel(tb, Text="Katman:", FontWeight="bold");
app.An.ChartMode = uidropdown(tb, Items=app.ChartModeTitles, ItemsData=app.ChartModes, Value=app.ChartMode, ...
    ValueChangedFcn=@(src, ~) app.setChartMode(string(src.Value)), ...
    Tooltip="4 Mühendislik Grafiği Modu: 1) Güç & POA Işınım, 2) DC Bara & 4-Kadranlı MPP Zarfı, 3) Verim & Faiman/Ross Termal İkiz, 4) L1 Şebeke (U_L1,cond, k/18) & R_iso.");
app.An.Status = uilabel(tb, Text="", Interpreter="html", FontSize=11.5);
uibutton(tb, Text="🗺 Haritada göster", ButtonPushedFcn=@(~, ~) app.showPage("map"));
uibutton(tb, Text="❓ Skalogram nedir?", ButtonPushedFcn=@(~, ~) app.showPage("help"));

app.An.Axes = uiaxes(g);
app.An.Chart = makePowerChart(app.An.Axes);

sp = uipanel(g, Title="Skalogram", FontWeight="bold");
app.An.ScaloPanel = sp;
sg = uigridlayout(sp, [2 8], RowHeight={"1x", 44}, ColumnWidth=[repmat({"1x"}, 1, 7) {250}], ...
    Padding=[4 2 4 2], RowSpacing=2, ColumnSpacing=4);
app.An.ScaloGrid = sg;
for k = 1:7
    app.An.ScaloImg(k) = uiimage(sg, ScaleMethod="fit");
    app.An.ScaloImg(k).Layout.Row = 1;
    app.An.ScaloImg(k).Layout.Column = k;
    app.An.ScaloLbl(k) = uilabel(sg, Text="", FontSize=10.5, WordWrap="on", HorizontalAlignment="center", ...
        VerticalAlignment="top");
    app.An.ScaloLbl(k).Layout.Row = 2;
    app.An.ScaloLbl(k).Layout.Column = k;
end
leg = uilabel(sg, WordWrap="on", FontSize=10.5, VerticalAlignment="top", Text= ...
    "Her resim bir günün güç sinyalinin dalgacık haritası (05:00–21:00 soldan sağa, yukarı = hızlı değişim). " + ...
    "Sarı: güç güneşi izliyor (normal). Camgöbeği: güneş var, güç yok (kesinti). Mavi/mor: eksik üretim. " + ...
    "Üstte kırmızı lekeler: öğlen zikzağı / MPP→Voc sıçraması (kısma). Altındaki etiket o günün SENSÖR kanıtına dayalı " + ...
    "teşhisi ve performansıdır (görsel CNN'in değil).");
leg.Layout.Row = [1 2];
leg.Layout.Column = 8;

tabs = uitabgroup(g);
tDiag = uitab(tabs, Title="Teşhis (ajanlar — 3 görüş)");
tg = uigridlayout(tDiag, [2 1], RowHeight={"1x", "fit"}, Padding=[4 4 4 4], RowSpacing=4);
app.An.Agent = uitextarea(tg, Editable="off", Value="");
ab = uigridlayout(tg, [1 3], ColumnWidth={"fit", "fit", "1x"}, Padding=[0 0 0 0]);
app.An.Explain = uibutton(ab, Text="💬 LLM ile açıkla", ButtonPushedFcn=@(~, ~) app.onExplain(), ...
    Tooltip="Teşhisi yerel LLM ile bakım ekibine yönelik açıklamaya çevirir (arka planda, sonuç Bildirimler'e düşer).");
app.An.Vlm = uibutton(ab, Text="🔍 VLM 2. görüş", ButtonPushedFcn=@(~, ~) app.onVlm(), ...
    Tooltip="Görsel-dil modeli skalogram ve 2-panelli güç/gerilim/şebeke grafiğine bakıp ikinci görüş verir (~20 sn).");
tEv = uitab(tabs, Title="Olaylar (son 30 gün)");
eg = uigridlayout(tEv, [1 1], Padding=[2 2 2 2]);
app.An.Events = uitable(eg, ColumnName=["Olay" "PV/Kanal" "Başlangıç" "Gün" "Kayıp (kWh)" "Kronik"], ...
    RowName={}, FontSize=11, ColumnWidth={"auto", 55, 85, 45, 78, 50});
tFb = uitab(tabs, Title="Saha geri bildirimi");
fbTip = "Bakım ekibi eviriciyi kontrol ettikten sonra gerçekte ne bulduğunu seçer ve kaydeder. " + ...
    "Bu kayıtlar gece yeniden eğitimde doğru etiket olarak kullanılır (active learning). Modelin kararı Teşhis sekmesindedir.";
fg = uigridlayout(tFb, [2 4], RowHeight={"fit", "1x"}, ColumnWidth={"fit", 170, "1x", "fit"}, Padding=[6 6 6 6]);
uilabel(fg, Text="Sahada ne buldunuz?", FontWeight="bold", Tooltip=fbTip);
app.An.Feedback = uidropdown(fg, Items=["— seçin —" app.ClassNamesTr], ItemsData=["" app.Classes], Value="", Tooltip=fbTip);
app.An.Note = uieditfield(fg, Placeholder="Not (isteğe bağlı), ör. MC4 konnektörü nemli veya L1 şebeke kesintisi", Tooltip=fbTip);
uibutton(fg, Text="Kaydet", ButtonPushedFcn=@(~, ~) app.onFeedback(), Tooltip=fbTip);
end
