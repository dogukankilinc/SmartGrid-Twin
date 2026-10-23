function buildMapPage(app, parent)
%BUILDMAPPAGE Saha Haritası: SmartGrid-Twin 5-düğümlü interaktif topoloji (HTML) | seçili düğüm/evirici özeti ve grafiği.
g = uigridlayout(parent, [1 2], ColumnWidth={"2x", "1x"}, Padding=[2 2 2 2], ColumnSpacing=6);
webDir = fullfile(fileparts(fileparts(mfilename("fullpath"))), "web");
app.Mp.Html = uihtml(g, HTMLSource=fullfile(webDir, "plantmap.html"), ...
    HTMLEventReceivedFcn=@(src, event) app.onHtmlEvent(src, event));
dp = uipanel(g, Title="Seçili Düğüm & Evirici Özeti", FontWeight="bold");
dg = uigridlayout(dp, [4 1], RowHeight={"fit", "fit", "1x", "fit"}, Padding=[6 4 6 6], RowSpacing=4);
app.Mp.Title = uilabel(dg, Text="Haritadan bir düğüm veya evirici seçin", FontSize=13, WordWrap="on", Interpreter="html");
app.Mp.Summary = uilabel(dg, Text="", FontSize=11.5, WordWrap="on", FontColor=[0.25 0.29 0.34]);
app.Mp.Axes = uiaxes(dg);
app.Mp.Chart = makePowerChart(app.Mp.Axes);
bg = uigridlayout(dg, [1 2], ColumnWidth={"fit", "1x"}, Padding=[0 0 0 0]);
uibutton(bg, Text="📈 Analiz sayfasında aç", ButtonPushedFcn=@(~, ~) app.showPage("analysis"), ...
    Tooltip="4 modlu mühendislik grafikleri, skalogramlar, 3 görüşlü teşhis ajanları, olay geçmişi ve saha geri bildirimi.");
uilabel(bg, Text="Topoloji düğümlerine tıklayarak grafik katmanını değiştirebilirsiniz.", FontColor=[0.42 0.47 0.52], FontSize=11);
end
