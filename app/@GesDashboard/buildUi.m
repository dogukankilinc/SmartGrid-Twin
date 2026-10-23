function buildUi(app, visible)
%BUILDUI BTÜ SmartGridLab kabuğu: başlık (oynatma + zamana atla) | üst menü (sayfalar) | sayfa alanı + sağda asistan.
%   Tüm yerleşim uigridlayout ile; sayfalar aynı hücrede üst üste durur, yalnızca açık olan görünür.
%   Ekran 1536×864 (125 % ölçek) için tasarlandı; pencere tam ekran açılır.
scr = get(groot, "ScreenSize");
app.Fig = uifigure(Name=app.Cfg.site.name + " — Dijital İkiz", ...
    Position=[scr(1) + 10, scr(2) + 40, min(1536, scr(3) - 20), min(820, scr(4) - 90)], ...
    Visible=visible, CloseRequestFcn=@(~, ~) app.delete());
if visible
    app.Fig.WindowState = "maximized";
end
app.Outer = uigridlayout(app.Fig, [3 2], RowHeight={44, 38, "1x"}, ColumnWidth={"1x", 380}, ...
    Padding=[6 4 6 6], RowSpacing=4, ColumnSpacing=6);

%% Başlık: ad | oynat | hız | saat | zamana atla | durum
h = uigridlayout(app.Outer, [1 6], ColumnWidth={"1x", 90, 140, 165, 300, 230}, Padding=[4 2 4 2]);
h.Layout.Row = 1;
h.Layout.Column = [1 2];
app.Header.Title = uilabel(h, Text=app.Cfg.site.name + " Dijital İkiz", FontSize=18, FontWeight="bold");
app.Header.Play = uibutton(h, Text="▶ Oynat", ButtonPushedFcn=@(~, ~) app.togglePlay(), ...
    Tooltip="Kayıtlı veriyi 15 dakikalık adımlarla canlı akış gibi oynatır (otonom izleme simülasyonu).");
app.Header.Speed = uidropdown(h, Items=["1× (15 dk/sn)" "4× (1 saat/sn)" "16× (4 saat/sn)"], ...
    ItemsData=[1 4 16], ValueChangedFcn=@(src, ~) app.setSpeed(src.Value));
app.Header.Time = uilabel(h, Text="", FontSize=14, FontWeight="bold", HorizontalAlignment="center");
nav = uigridlayout(h, [1 4], ColumnWidth={"1x", 52, 52, 44}, Padding=[0 0 0 0], ColumnSpacing=4);
[t0, t1] = app.Engine.range();
tNow = app.Engine.Times(app.Engine.Index);
app.Header.Date = uidatepicker(nav, DisplayFormat="dd.MM.yyyy", ...
    Limits=[datetime(year(t0), month(t0), day(t0)), datetime(year(t1), month(t1), day(t1))], ...
    Value=datetime(year(tNow), month(tNow), day(tNow)), ...
    Tooltip=sprintf("Atlanacak tarih (%s – %s).", string(t0, "dd.MM.yyyy"), string(t1, "dd.MM.yyyy")));
app.Header.Hour = uidropdown(nav, Items=compose("%02d", 0:23), ItemsData=0:23, Value=hour(tNow), Tooltip="Saat");
app.Header.Minute = uidropdown(nav, Items=["00" "15" "30" "45"], ItemsData=[0 15 30 45], ...
    Value=15 * floor(minute(tNow) / 15), Tooltip="Dakika");
uibutton(nav, Text="Git", ButtonPushedFcn=@(~, ~) app.onSeek(), Tooltip="Seçilen tarih ve saate atla");
app.Header.Busy = uilabel(h, Text="✓ hazır", FontColor=[0.2 0.55 0.3], HorizontalAlignment="right");

%% Üst menü (sayfalar) + asistanı gizle/göster
nb = uigridlayout(app.Outer, [1 numel(app.Pages) + 1], ColumnWidth=[repmat({"fit"}, 1, numel(app.Pages)) {"1x"}], ...
    Padding=[0 0 0 0], ColumnSpacing=4);
nb.Layout.Row = 2;
nb.Layout.Column = 1;
for i = 1:numel(app.Pages)
    p = app.Pages(i);
    app.NavButtons.(p) = uibutton(nb, Text=app.PageIcons(i) + " " + app.PageTitles(i), FontSize=13, ...
        FontWeight="bold", BackgroundColor=[1 1 1], ButtonPushedFcn=@(~, ~) app.showPage(p));
end
toggle = uibutton(nb, Text="💬 Asistanı gizle", HorizontalAlignment="right", ...
    ButtonPushedFcn=@(src, ~) app.toggleChat(src));
toggle.Layout.Column = numel(app.Pages) + 1;

%% Sayfalar: aynı hücrede üst üste; yalnızca açık olan görünür
content = uigridlayout(app.Outer, [1 1], Padding=[0 0 0 0]);
content.Layout.Row = 3;
content.Layout.Column = 1;
for p = app.Pages
    app.PagePanels.(p) = uipanel(content, BorderType="none", Visible="off");
    app.PagePanels.(p).Layout.Row = 1;
    app.PagePanels.(p).Layout.Column = 1;
end
app.buildOverview(app.PagePanels.overview);
app.buildMapPage(app.PagePanels.map);
app.buildAnalysis(app.PagePanels.analysis);
app.buildForecast(app.PagePanels.forecast);
app.buildReports(app.PagePanels.reports);
app.buildNotifyPage(app.PagePanels.notify);
app.buildDataPage(app.PagePanels.data);
app.buildHelpPage(app.PagePanels.help);

%% Asistan (her sayfada; yalnızca açık sayfanın içeriğiyle yanıt verir)
title = uilabel(app.Outer, Text="💬 Asistan", FontSize=13, FontWeight="bold", VerticalAlignment="bottom");
title.Layout.Row = 2;
title.Layout.Column = 2;
app.Ch.Title = title;
cp = uipanel(app.Outer);
cp.Layout.Row = 3;
cp.Layout.Column = 2;
cg = uigridlayout(cp, [4 3], RowHeight={"1x", "fit", "fit", "fit"}, ColumnWidth={"1x", "fit", "fit"}, ...
    Padding=[4 4 4 4], RowSpacing=4, ColumnSpacing=4);
webDir = fullfile(fileparts(fileparts(mfilename("fullpath"))), "web");
app.Ch.Html = uihtml(cg, HTMLSource=fullfile(webDir, "chat.html"), ...
    HTMLEventReceivedFcn=@(~, ev) app.onPanelReady(ev, "chat"));
app.Ch.Html.Layout.Column = [1 3];
app.ChatLog = struct("role", "assistant", "text", ...
    "Merhaba! BTÜ SmartGridLab (WR13TL22-8231) için açık olan sayfadaki bilgilerle yanıt veririm. Başka sayfadaki bir bilgi sorarsanız sizi o sayfaya " + ...
    "yönlendiririm. Bir sayfadaki bilgiyi 📌 Hafızaya al ile saklayıp başka sayfada karşılaştırmamı isteyebilirsiniz.", ...
    "tools", "", "page", "", "go", "");
app.Ch.Input = uieditfield(cg, Placeholder="Bu sayfa hakkında sorun… (ör. k/18 röle nedir? R_iso sabah neden düşük?)", ...
    ValueChangedFcn=@(~, ~) app.onChat());
app.Ch.Input.Layout.Row = 2;
app.Ch.Input.Layout.Column = [1 2];
app.Ch.Send = uibutton(cg, Text="Gönder", ButtonPushedFcn=@(~, ~) app.onChat());
app.Ch.Send.Layout.Row = 2;
app.Ch.Send.Layout.Column = 3;
pinBtn = uibutton(cg, Text="📌 Hafızaya al", ButtonPushedFcn=@(~, ~) app.onPin(), ...
    Tooltip="Bu sayfanın özetini ve buradaki son yanıtı saklar; başka sayfada karşılaştırma için kullanılır.");
pinBtn.Layout.Row = 3;
pinBtn.Layout.Column = 2;
clr = uibutton(cg, Text="Temizle", ButtonPushedFcn=@(~, ~) app.clearMemory(), Tooltip="Hafızayı temizle");
clr.Layout.Row = 3;
clr.Layout.Column = 3;
app.Ch.Memory = uilabel(cg, Text="", WordWrap="on", FontSize=11, FontColor=[0.35 0.4 0.45]);
app.Ch.Memory.Layout.Row = 4;
app.Ch.Memory.Layout.Column = [1 3];
hint = uilabel(cg, Text="Asistan yalnızca açık sayfayı okur.", FontSize=11, FontColor=[0.35 0.4 0.45]);
hint.Layout.Row = 3;
hint.Layout.Column = 1;
app.refreshMemory();
end

