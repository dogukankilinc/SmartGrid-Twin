function onEventPick(app, src)
%ONEVENTPICK Geriye dönük doğrulama: seçilen olaydan önceki 14-21 gün (normalize DC akım / gerilim + kısa kopmalar).
if isempty(src.Selection) || isempty(src.UserData)
    return
end
ev = src.UserData(src.Selection(1), :);
d = ges.agents.deviceData(app.Ctx, ev.Id);
TT = d.TT(d.TT.Time >= ev.Start - days(14) & d.TT.Time <= ev.Start + days(2), :);
ax = app.Fc.EvAxes;
cla(ax, "reset");
disableDefaultInteractivity(ax);
if isempty(TT)
    title(ax, "Bu aralıkta veri yok");
    return
end
vars = string(TT.Properties.VariableNames);
pvIdx = max(1, min(8, double(ev.PV)));
if all(ismember("I_pv" + (1:8), vars)) && numel(d.info.Installed) >= 8 && nnz(d.info.Installed) > 1
    sf = ges.prep.stringFeatures(TT{:, "I_pv" + (1:8)}, d.info.Installed);
    vis = TT.Elevation > 10 & TT.G_ref > 300 & sf.Median > 1;
    nrm = sf.Norm(:, pvIdx);
    nrm(~vis) = NaN;
    dead = sf.Dead(:, pvIdx);
    yLbl = "PV" + pvIdx + " akımı / diğer dizilerin medyanı";
else
    % Tek MPPT / tek DC kanal (SmartGrid-Twin WR13TL22-8231)
    if ismember("I_dc", vars)
        idc = double(TT.I_dc);
    elseif ismember("I_pv1", vars)
        idc = double(TT.I_pv1);
    else
        idc = double(TT.P_dc) * 5;
    end
    g = max(double(TT.G_ref), 1);
    iExp = 5.2 * (g / 1000);
    vis = TT.Elevation > 10 & TT.G_ref > 250;
    nrm = idc ./ max(iExp, 0.2);
    nrm(~vis) = NaN;
    dead = vis & (isnan(idc) | idc < 0.15 * iExp);
    yLbl = "Normalize DC akım I_{dc} / I_{mp,beklenen}";
end
plot(ax, TT.Time, nrm, ".", Color=[0.10 0.35 0.75], MarkerSize=6);
hold(ax, "on");
dd = diff([false; dead; false]);
s0 = find(dd == 1);
e0 = find(dd == -1) - 1;
short = (e0 - s0 + 1) <= 4;
if any(short)
    plot(ax, TT.Time(s0(short)), zeros(nnz(short), 1), "v", Color=[0.85 0.2 0.15], MarkerFaceColor=[0.85 0.2 0.15], MarkerSize=7);
end
xline(ax, ev.Start, "-", "olay başlangıcı", Color=[0.85 0.2 0.15], LineWidth=1.4);
xregion(ax, ev.Start - days(7), ev.Start - hours(1), FaceColor=[1 0.85 0.4], FaceAlpha=0.25);
hold(ax, "off");
ylim(ax, [-0.1 1.35]);
ylabel(ax, yLbl);
ndrop = 2;
if ~isempty(app.Fc.K2) && isfield(app.Fc.K2, "NDROP")
    ndrop = app.Fc.K2.NDROP;
end
warned = ev.ShortDrops >= ndrop;
title(ax, sprintf("%s PV%d — %s: %s", ev.Id, ev.PV, string(ev.Start, "dd.MM.yyyy HH:mm"), ...
    ifelse(warned, sprintf("önceden uyarıldı (%d öncü işaret ▼)", ev.ShortDrops), "önceden uyarı YOK")));
legend(ax, ["Normalize DC akım" "Kısa kopma / kesinti (▼)"], Location="southwest");
grid(ax, "on");
end
