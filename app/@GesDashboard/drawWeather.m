function drawWeather(app)
%DRAWWEATHER 48 saatlik üretim tahmini ve dayandığı hava/rüzgar verisinin grafikleri.
wx = app.Forecast.wx;
fc = app.Forecast.fc;
dt = app.dtHours();
eNow = sum(fc.PlantKw) * dt;
eFix = sum(fc.PlantKwAllStrings) * dt;
app.Fc.Status.Text = sprintf("Open-Meteo'dan %s'de alınan hava tahmini (GERÇEK bugünün tarihleri) M1 beklenen güç modeline verildi. " + ...
    "Toplam beklenen üretim: %s. Arıza durumu oynatma anından (%s): %d birimde dizi kaybı var; " + ...
    "onarılırsa +%s (%%%.1f).", string(wx.Properties.UserData.Retrieved, "dd.MM.yyyy HH:mm"), energyText(eNow), ...
    string(app.Forecast.stateTime, "dd.MM.yyyy HH:mm"), app.Forecast.nFaulty, energyText(eFix - eNow), ...
    100 * (eFix - eNow) / max(eNow, 0.01));
ax1 = app.Fc.Ax1;
cla(ax1);
plot(ax1, fc.Time, fc.PlantKw, "-", LineWidth=2, Color=[0.10 0.35 0.75]);
hold(ax1, "on");
plot(ax1, fc.Time, fc.PlantKwAllStrings, "--", LineWidth=1.4, Color=[0.20 0.65 0.30]);
hold(ax1, "off");
ylabel(ax1, "Tesis gücü (kW)");
legend(ax1, ["Beklenen üretim (mevcut durum)" "Tam kapasite (onarılırsa)"], Location="northwest");
title(ax1, "48 Saatlik Üretim Tahmini (" + app.Cfg.site.name + ")");
grid(ax1, "on");
ax2 = app.Fc.Ax2;
cla(ax2);
yyaxis(ax2, "left");
gPoa = fc.G_poa;
gPoa(isnan(gPoa)) = 0;
hG = area(ax2, fc.Time, max(gPoa, 0), FaceColor=[0.95 0.75 0.2], FaceAlpha=0.45, EdgeColor=[0.85 0.6 0.1]);
ylabel(ax2, "POA Işınım (W/m^2)");
yyaxis(ax2, "right");
hC = plot(ax2, fc.Time, fc.Cloud, "-", Color=[0.45 0.45 0.45], LineWidth=1.2);
ylabel(ax2, "Bulutluluk (%)");
ylim(ax2, [0 100]);
legend(ax2, [hG hC], ["Panel düzlemi ışınımı (G_poa)" "Bulutluluk (%)"], Location="northwest");
title(ax2, "Tahminin dayandığı hava verisi");
grid(ax2, "on");
xlim(ax1, [fc.Time(1) fc.Time(end)]);
xlim(ax2, [fc.Time(1) fc.Time(end)]);
end
