function h = makePowerChart(ax)
%MAKEPOWERCHART 4 modlu mühendislik grafiği nesnelerini BİR KEZ kurar (sonra yalnız veri değişir).
%   Modlar: "power" (Güç & POA Işınım), "dc_mpp" (DC Gerilim/Akım & MPP Zarfı),
%           "eff_thermal" (Evirici Verimi & Ross/Faiman Sıcaklık + Rüzgar),
%           "grid_riso" (L1 Şebeke U_L1/U_L1_cond & Frekans/R_iso).
t0 = datetime(2026, 8, 1, TimeZone="Europe/Istanbul") + minutes([0; 15]);
yyaxis(ax, "left");
h.Pact = plot(ax, t0, [NaN; NaN], "-", LineWidth=1.7, Color=[0.10 0.35 0.75]);
hold(ax, "on");
h.Pac  = plot(ax, t0, [NaN; NaN], "-", LineWidth=1.4, Color=[0.16 0.62 0.32]);
h.Pexp = plot(ax, t0, [NaN; NaN], "--", LineWidth=1.6, Color=[0.90 0.45 0.10]);
hold(ax, "off");
ylabel(ax, "Güç (kW)");

yyaxis(ax, "right");
h.G = area(ax, t0, [NaN; NaN], FaceAlpha=0.14, EdgeColor="none", FaceColor=[0.95 0.75 0.2]);
hold(ax, "on");
h.R1 = plot(ax, t0, [NaN; NaN], "-.", LineWidth=1.3, Color=[0.55 0.25 0.72]);
hold(ax, "off");
ylabel(ax, "Işınım (W/m^2)");

legend(ax, [h.Pact h.Pac h.Pexp h.G], ["DC Güç" "AC Güç" "Beklenen (M1)" "POA Işınım"], ...
    Location="northwest", Orientation="horizontal", FontSize=8, Box="off");
grid(ax, "on");
disableDefaultInteractivity(ax);
h.Mode = "power";
h.Key = "";
end
