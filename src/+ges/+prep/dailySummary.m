function D = dailySummary(P, opts)
%DAILYSUMMARY İşlenmiş invertör timetable'ından günlük özet (enerji, gökyüzü, olay sayaçları, termal & şebeke).
%   D = ges.prep.dailySummary(P) — Hem standart GES metriklerini hem de SmartGridLab
%   genişletilmiş metriklerini (H_horiz, H_poa, Wind_mean/max, T_cell_faiman_max,
%   DeltaT_cooling, Eta_med, R_iso_min/morning, V_grid_min/max, ResetEvents, PR_poa, PR_temp_corr) üretir.

arguments
    P timetable
    opts.Step (1,1) duration = minutes(15)
    opts.MinElevation (1,1) double = 5
    opts.PeerElevation (1,1) double = 15
    opts.OvercastKd (1,1) double = 0.4
    opts.ClearKd (1,1) double = 0.75
    opts.ClearVi (1,1) double = 2.5
end

h = hours(opts.Step);
day = dateshift(P.Time, "start", "day");
[g, days] = findgroups(day);
nd = numel(days);
lit = P.Elevation > opts.MinElevation;
pVars = string(P.Properties.VariableNames);
has = @(c) ismember(c, pVars);

    function s = sumIf(x, m)
        v = x;
        v(~m | isnan(v)) = 0;
        s = accumarray(g, v, [nd 1]);
    end
    function c = countIf(m)
        c = accumarray(g, double(m), [nd 1]);
    end
    function mVal = maxIf(x, m)
        v = x;
        v(~m) = NaN;
        mVal = splitapply(@(z) maxWithNaN(z), v, g);
    end
    function mVal = minIf(x, m)
        v = x;
        v(~m) = NaN;
        mVal = splitapply(@(z) minWithNaN(z), v, g);
    end
    function mVal = medIf(x, m)
        v = x;
        v(~m) = NaN;
        mVal = splitapply(@(z) median(z, "omitmissing"), v, g);
    end
    function mVal = meanIf(x, m)
        v = x;
        v(~m) = NaN;
        mVal = splitapply(@(z) mean(z, "omitmissing"), v, g);
    end

nLit = countIf(lit);
D = timetable(RowTimes=days);
D.Coverage = countIf(lit & ~isnan(P.P_dc)) ./ max(nLit, 1);
D.MeteoCoverage = countIf(lit & ~isnan(P.G_ref)) ./ max(nLit, 1);
D.E_dc = sumIf(P.P_dc * h, true(height(P), 1));
D.E_ac = sumIf(P.P_ac * h, true(height(P), 1));
D.H_ref = sumIf(P.G_ref * h / 1000, lit);
if has("G_horiz")
    D.H_horiz = sumIf(P.G_horiz * h / 1000, lit);
else
    D.H_horiz = D.H_ref;
end
if has("G_poa")
    D.H_poa = sumIf(P.G_poa * h / 1000, lit);
else
    D.H_poa = D.H_ref;
end

both = lit & ~isnan(P.G_ref) & ~isnan(P.PoaCsRef);
D.Kd = sumIf(P.G_ref, both) ./ sumIf(P.PoaCsRef, both);
sameDay = [false; g(2:end) == g(1:end-1)];
pair = both & [false; both(1:end-1)] & sameDay;
dG = abs([NaN; diff(P.G_ref)]);
dCs = abs([NaN; diff(P.PoaCsRef)]);
D.VI = sumIf(dG, pair) ./ sumIf(dCs, pair);

D.Ynorm = sumIf(P.Pn * h, lit);
D.YieldRatio = D.Ynorm ./ D.H_ref;
D.PR_poa = (D.E_ac / 1.20) ./ max(D.H_poa, 0.05);
D.PR_poa(D.H_poa < 0.2) = NaN;

if has("T_cell_faiman")
    tCell = P.T_cell_faiman;
else
    tCell = P.T_mod;
end
pDcTempCorr = P.P_dc ./ (1 - 0.0037 * (tCell - 25));
eDcCorr = sumIf(pDcTempCorr * h, lit);
D.PR_temp_corr = (eDcCorr / 1.20) ./ max(D.H_poa, 0.05);
D.PR_temp_corr(D.H_poa < 0.2) = NaN;

peerOk = lit & P.Elevation > opts.PeerElevation & ~isnan(P.Pn) & ~isnan(P.PeerMedian) & ~P.qClip;
D.PeerRatio = sumIf(P.Pn, peerOk) ./ sumIf(P.PeerMedian, peerOk);
D.PeerSteps = countIf(peerOk);

D.FaultSteps = countIf(P.qFault);
D.DerateSteps = countIf(P.qDerate);
D.IdleDaySteps = countIf(P.qIdle & lit);
D.ClipSteps = countIf(P.qClip);
D.CabinEventSteps = countIf(P.qCabinEvent);
if has("qMeteoFallback")
    D.MeteoFallbackSteps = countIf(lit & P.qMeteoFallback);
else
    D.MeteoFallbackSteps = countIf(lit & string(P.MeteoSource) ~= "K02" & string(P.MeteoSource) ~= "K01");
end
D.WeakSteps = countIf(P.NumWeak > 0);
for k = 1:8
    D.("DeadSteps_pv" + k) = countIf(bitget(P.DeadMask, k) == 1);
end

D.T_cab_max = maxIf(P.T_cab, true(height(P), 1));
D.T_mod_max = maxIf(P.T_mod, true(height(P), 1));
D.T_amb_max = maxIf(P.T_amb, true(height(P), 1));
D.T_cell_faiman_max = maxIf(tCell, true(height(P), 1));

if has("WindSpeed")
    D.Wind_mean = meanIf(P.WindSpeed, lit);
    D.Wind_max = maxIf(P.WindSpeed, lit);
else
    D.Wind_mean = nan(nd, 1);
    D.Wind_max = nan(nd, 1);
end
if has("DeltaT_wind")
    D.DeltaT_cooling = meanIf(P.DeltaT_wind, lit);
else
    D.DeltaT_cooling = meanIf(P.T_mod - tCell, lit);
end

if has("Eff")
    D.Eta_med = medIf(P.Eff, lit & P.P_dc > 0.15);
else
    D.Eta_med = nan(nd, 1);
end

if has("R_iso")
    hr = hour(P.Time) + minute(P.Time) / 60;
    D.R_iso_min = minIf(P.R_iso, ~isnan(P.R_iso));
    D.R_iso_morning = medIf(P.R_iso, hr >= 6 & hr <= 9.5 & ~isnan(P.R_iso));
else
    D.R_iso_min = nan(nd, 1);
    D.R_iso_morning = nan(nd, 1);
end

if has("U_L1")
    D.V_grid_min = minIf(P.U_L1, P.qOnGrid);
    D.V_grid_max = maxIf(P.U_L1, P.qOnGrid);
else
    D.V_grid_min = nan(nd, 1);
    D.V_grid_max = nan(nd, 1);
end
if has("f_grid")
    D.f_grid_min = minIf(P.f_grid, P.qOnGrid);
    D.f_grid_max = maxIf(P.f_grid, P.qOnGrid);
else
    D.f_grid_min = nan(nd, 1);
    D.f_grid_max = nan(nd, 1);
end

if has("qRebootEvent"), D.ResetEvents = countIf(P.qRebootEvent); else, D.ResetEvents = zeros(nd, 1); end
if has("qRelayCycle"), D.RelayCycleSteps = countIf(P.qRelayCycle); else, D.RelayCycleSteps = zeros(nd, 1); end
if has("qGridLoss"), D.GridLossSteps = countIf(P.qGridLoss); else, D.GridLossSteps = zeros(nd, 1); end
if has("qHighGridV"), D.HighGridVSteps = countIf(P.qHighGridV); else, D.HighGridVSteps = zeros(nd, 1); end
if has("qLowInsulation"), D.LowIsoSteps = countIf(P.qLowInsulation); else, D.LowIsoSteps = zeros(nd, 1); end

sky = repmat("partly", nd, 1);
sky(D.Kd < opts.OvercastKd) = "overcast";
sky(D.Kd >= opts.ClearKd & D.VI < opts.ClearVi) = "clear";
sky(D.MeteoCoverage < 0.8 | isnan(D.Kd)) = "undefined";
D.SkyClass = categorical(sky, ["clear" "partly" "overcast" "undefined"]);
end

function m = maxWithNaN(z)
v = z(~isnan(z));
if isempty(v), m = NaN; else, m = max(v); end
end

function m = minWithNaN(z)
v = z(~isnan(z));
if isempty(v), m = NaN; else, m = min(v); end
end
