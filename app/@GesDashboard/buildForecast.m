function buildForecast(app, parent)
%BUILDFORECAST Tahmin & Erken Uyarı: 48 saat üretim | yarın ısıl kısma | arıza riski | geriye dönük doğrulama.
g = uigridlayout(parent, [1 1], Padding=[2 2 2 2]);
tabs = uitabgroup(g);
app.Fc.Tabs = tabs;

% 1) 48 saatlik üretim tahmini (internet hava tahmini + M1)
t1 = uitab(tabs, Title="48 saatlik üretim tahmini");
g1 = uigridlayout(t1, [3 1], RowHeight={"fit", "2x", "1x"}, Padding=[6 6 6 6], RowSpacing=4);
tb = uigridlayout(g1, [1 2], ColumnWidth={"fit", "1x"}, Padding=[0 0 0 0]);
app.Fc.Weather = uibutton(tb, Text="🌦 Hava tahmini al (internet)", ButtonPushedFcn=@(~, ~) app.onWeather(), ...
    Tooltip="Open-Meteo'dan 48 saatlik hava tahmini alır, M1 modeliyle tesis ve evirici (WR13TL22-8231) gücünü tahmin eder (arka planda).");
app.Fc.Status = uilabel(tb, Text="Henüz tahmin alınmadı. Tahmin GERÇEK bugünün tarihleri içindir; arıza durumu oynatma anından alınır.", ...
    WordWrap="on", FontColor=[0.3 0.35 0.4]);
app.Fc.Ax1 = uiaxes(g1);
app.Fc.Ax2 = uiaxes(g1);
title(app.Fc.Ax1, "SmartGridLab üretim tahmini (1.20 kWp)");
title(app.Fc.Ax2, "Tahminin dayandığı hava verisi");

% 2-4) Isıl kısma tahmini, risk, geriye dönük doğrulama (ges.forecast / scripts/v2/k01 çıktıları)
t2 = uitab(tabs, Title="Isıl kısma tahmini");
app.Fc.ThermalGrid = uigridlayout(t2, [2 2], RowHeight={"fit", "1x"}, ColumnWidth={"3x", "2x"}, Padding=[6 6 6 6]);
t3 = uitab(tabs, Title="Arıza riski & erken uyarı");
app.Fc.RiskGrid = uigridlayout(t3, [2 2], RowHeight={"fit", "1x"}, ColumnWidth={"3x", "2x"}, Padding=[6 6 6 6]);
t4 = uitab(tabs, Title="Geriye dönük doğrulama");
app.Fc.BacktestGrid = uigridlayout(t4, [2 2], RowHeight={"fit", "1x"}, ColumnWidth={"2x", "3x"}, Padding=[6 6 6 6]);
app.buildForecastTabs();
tabs.SelectedTab = t2;                                  % internetsiz çalışan sekme önde
end
