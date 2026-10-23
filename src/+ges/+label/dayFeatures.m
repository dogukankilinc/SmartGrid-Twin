function F = dayFeatures(TT, Steps, D, info, events)
%DAYFEATURES Bir invertörün her günü için etiketleme fonksiyonlarının girdileri (%100 sütun kapsama).
%   F = ges.label.dayFeatures(TT, Steps, D, info, events)
%   TT     : işlenmiş 15 dk veri (s03)          Steps : M1 beklentisi (s05 / i01)
%   D      : günlük özet (s03)                  info  : cihaz künyesi
%   events : bu invertörün olay kataloğu satırları (s05 / i01)
%   Dedektörler Steps'teki beklentiyle yeniden çalıştırılır (model tahmini gerekmez).
%   Sayaçlar yalnızca gündüz (güneş > 5°) adımlarını sayar.

ex = struct("Pdc", Steps.Pdc_exp, "PdcWork", Steps.PdcWork_exp, "Pac", Steps.Pac_exp);
if ismember("EtaExp", Steps.Properties.VariableNames)
    ex.EtaExp = Steps.EtaExp;
end
s = ges.anomaly.detectSteps(TT, ex);
lit = TT.Elevation > 5;
day = dateshift(TT.Time, "start", "day");
[g, dayList] = findgroups(day);
nd = numel(dayList);
vars = TT.Properties.VariableNames;

    function c = cnt(m)
        c = accumarray(g, double(m & lit), [nd 1]);
    end
    function v = sumIf(x, m)
        x = double(x);
        x(~m | isnan(x)) = 0;
        v = accumarray(g, x, [nd 1]);
    end

F = table(dayList, VariableNames="Day");
F.Id = repmat(string(info.Id), nd, 1);
F.LitSteps = cnt(true(size(lit)));
F.Coverage = cnt(~TT.qMissing) ./ max(F.LitSteps, 1);
F.GridSteps = cnt(s.GridEvent);
F.TripSteps = cnt(s.Trip);
F.DeadSteps = cnt(any(s.StringDead, 2));
F.MaxDeadStrings = accumarray(g, sum(s.StringDead, 2), [nd 1], @max);
F.WeakSteps = cnt(s.StringWeak);
F.DerateSteps = cnt(s.Derate);
F.ThrottleSteps = cnt(s.Throttle);
F.StatusDerateSteps = cnt(TT.qDerate);
if ismember("qPowerLimit", vars)
    F.PowerLimitSteps = cnt(TT.qPowerLimit);
else
    F.PowerLimitSteps = zeros(nd, 1);
end
if ismember("ThrottleLossKw", vars)
    F.ThrottleLossKwh = sumIf(TT.ThrottleLossKw * 0.25, lit);
else
    F.ThrottleLossKwh = zeros(nd, 1);
end
F.HasThrottleSig = repmat( ...
    (ismember("Ppot", vars) && any(~isnan(TT.Ppot))) || ...
    ismember("V_dc", vars) || ismember("V_pv1", vars), nd, 1);
F.OfflineSteps = cnt(s.Offline);
F.Def2Steps = cnt(s.DeficitLevel >= 2);
F.Def3Steps = cnt(s.DeficitLevel >= 3);
F.ValidSteps = cnt(s.Valid);

% SmartGridLab %100 sütun günlük özet sayaçları
F.RelayCycleSteps = cnt(s.qRelayCycle);
F.HighGridVSteps = cnt(s.qHighGridV);
F.LowIsoSteps = cnt(s.qLowInsulation);
F.MiddayLowIsoSteps = cnt(s.qMiddayLowIso);
F.EffDropSteps = cnt(s.qInverterEffDrop);
F.RebootSteps = cnt(s.qRebootEvent);
if ismember("dV", vars)
    F.VoltageDropSteps = cnt(s.Valid & TT.dV < -0.05);
else
    F.VoltageDropSteps = zeros(nd, 1);
end
if ismember("R_iso", vars)
    F.RisoMin = accumarray(g, double(TT.R_iso), [nd 1], @(x) min(x, [], "omitmissing"), 3000);
else
    F.RisoMin = repmat(3000, nd, 1);
end

v = s.Valid;
thrLoss = zeros(height(TT), 1);
if ismember("ThrottleLossKw", vars)
    thrLoss = fillmissing(double(TT.ThrottleLossKw), "constant", 0);
end
F.ResDef = sumIf(ex.PdcWork - TT.P_dc - thrLoss, v) ./ max(sumIf(ex.Pdc, v), eps);
F.ResDef(F.ValidSteps == 0) = NaN;
F.TotDef = sumIf(ex.Pdc - TT.P_dc, v) ./ max(sumIf(ex.Pdc, v), eps);
F.TotDef(F.ValidSteps == 0) = NaN;
F.ExpectedKwh = sumIf(ex.Pdc * 0.25, lit);

tCabCol = double(TT.T_mod);
if ismember("T_cab", vars) && any(~isnan(TT.T_cab))
    tCabCol = double(TT.T_cab);
elseif ismember("T_cell_dyn", vars) && any(~isnan(TT.T_cell_dyn))
    tCabCol = double(TT.T_cell_dyn) + 8 * double(fillmissing(TT.P_ac, "constant", 0)) / max(info.Rated, 0.1);
end
F.TcabMax = accumarray(g, tCabCol, [nd 1], @(x) max(x, [], "omitmissing"), NaN);

tk = repmat("", nd, 1);
for i = find(F.TripSteps > 0)'
    tk(i) = string(mode(s.TripKind(g == i & s.Trip)));
end
F.TripKind = tk;

if ~isempty(D) && ismember("SkyClass", D.Properties.VariableNames)
    [tf, loc] = ismember(F.Day, dateshift(D.Time, "start", "day"));
    F.Sky = repmat(categorical("undefined", categories(D.SkyClass)), nd, 1);
    F.Sky(tf) = D.SkyClass(loc(tf));
    F.Kd = nan(nd, 1);
    if ismember("Kd", D.Properties.VariableNames)
        F.Kd(tf) = D.Kd(loc(tf));
    end
else
    F.Sky = categorical(repmat("clear", nd, 1), ["clear" "partly" "overcast" "undefined"]);
    F.Kd = nan(nd, 1);
end

F.EpisodeAgeDays = nan(nd, 1);
if ~isempty(events) && ismember("Type", events.Properties.VariableNames)
    sev = events(ismember(events.Type, ["trip" "string_dead"]) & events.Severity >= 2, :);
    for e = 1:height(sev)
        d0 = dateshift(sev.Start(e), "start", "day");
        inEp = F.Day >= d0 & F.Day <= sev.End(e);
        age = days(F.Day(inEp) - d0);
        F.EpisodeAgeDays(inEp) = min(F.EpisodeAgeDays(inEp), age, "omitmissing");
    end
end

F.M1Flag = F.Def2Steps > 0 | F.TripSteps > 0 | F.DeadSteps > 0 | F.GridSteps > 0;
end
