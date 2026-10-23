function events = inverterEvents(TT, ex, s, id, cabin, sigName)
%INVERTEREVENTS Bir invertörün adım bayraklarından olay kataloğu satırları (v2-I01 ve veri yükleme hattı).
%   events = ges.anomaly.inverterEvents(TT, ex, s, id, cabin, sigName)
%   TT: işlenmiş veri (ThrottleLossKw dahil), ex: ges.anomaly.expectedPower, s: ges.anomaly.detectSteps,
%   sigName: kısma kanıtının adı ("V/I imzası" | "güç+sıcaklık imzası").
if nargin < 6 || strlength(sigName) == 0
    sigName = "V/I imzası";
end
thrLoss = zeros(height(TT), 1);
if ismember("ThrottleLossKw", TT.Properties.VariableNames)
    thrLoss = fillmissing(double(TT.ThrottleLossKw), "constant", 0);
end
lossDeficit = max(ex.PdcWork - TT.P_dc - thrLoss, 0);
lossDeficit(~s.Valid) = 0;
nDead = max(sum(s.StringDead, 2), 1);
lossString = max(ex.Pdc - ex.PdcWork, 0) ./ nDead;
specs = {
    "trip",          s.Trip,               max(ex.Pdc - fillmissing(TT.P_dc, "constant", 0), 0), 3, 0, s.Obs.Trip
    "grid_event",    s.GridEvent,          max(ex.Pdc - fillmissing(TT.P_dc, "constant", 0), 0), 3, 0, s.Obs.GridEvent
    "string_weak",   s.StringWeak,         zeros(height(TT), 1),                                 1, 0, s.Obs.StringWeak
    "power_deficit", s.DeficitLevel >= 2,  lossDeficit,                                          2, 0, s.Obs.Deficit
    "derating",      s.Derate,             thrLoss,                                              1, 0, s.Obs.Derate
    "offline",       s.Offline,            ex.Pdc,                                               1, 0, s.Obs.Offline};
for pv = 1:8
    specs(end+1, :) = {"string_dead", s.StringDead(:, pv), lossString .* s.StringDead(:, pv), 2, pv, s.Obs.StringDead}; %#ok<AGROW>
end
parts = cell(size(specs, 1), 1);
vars = TT.Properties.VariableNames;
for i = 1:size(specs, 1)
    minSt = 1;
    ep = ges.anomaly.buildEpisodes(TT.Time, specs{i, 2}, specs{i, 3}, Observed=specs{i, 6}, MaxObservedGap=4, MaxGap=days(60), MinSteps=minSt);
    if height(ep) == 0, continue, end
    detail = repmat("", height(ep), 1);
    for e = 1:height(ep)
        inEp = TT.Time >= ep.Start(e) & TT.Time <= ep.End(e);
        switch specs{i, 1}
            case "trip"
                kinds = s.TripKind(inEp & s.Trip);
                if ~isempty(kinds), detail(e) = string(mode(kinds)); end
                if isfield(s, "qRebootEvent") && any(inEp & s.qRebootEvent)
                    detail(e) = detail(e) + " (SchedP=0 reset)";
                end
            case "grid_event"
                if ismember("U_L1", vars) && any(inEp & s.GridEvent & TT.U_L1 == 0)
                    detail(e) = "gündüz L1 şebeke kesintisi (U_L1=0 V)";
                elseif isfield(s, "U_L1_cond") && any(inEp & s.GridEvent & (s.U_L1_cond < 195 | s.U_L1_cond > 253))
                    detail(e) = "EN 50160 L1 gerilim sınır ihlali";
                else
                    detail(e) = "şebeke/kabin olayı";
                end
            case "derating"
                if ismember("qPowerLimit", vars) && nnz(inEp & TT.qPowerLimit) > nnz(inEp & s.Throttle)
                    detail(e) = "planlı güç sınırı (SchedP_Pct)";
                elseif nnz(inEp & TT.qDerate) >= nnz(inEp & s.Throttle) && any(inEp & TT.qDerate)
                    detail(e) = "durum kodu";
                else
                    detail(e) = sigName;
                end
            case "string_dead"
                if ismember("dV", vars) && any(inEp & TT.dV < -0.05)
                    detail(e) = "gerilim çökmesi (bypass diyot)";
                else
                    detail(e) = "akım kaybı";
                end
            case "offline"
                if isfield(s, "qRebootEvent") && any(TT.Time >= ep.Start(e) & TT.Time <= ep.End(e) + minutes(30) & s.qRebootEvent)
                    detail(e) = "iletişim/evirici kesintisi (SchedP=0 reset ile dönüş)";
                end
        end
    end
    parts{i} = table(repmat(string(id), height(ep), 1), repmat(cabin, height(ep), 1), repmat(specs{i, 1}, height(ep), 1), ...
        repmat(specs{i, 5}, height(ep), 1), repmat(specs{i, 4}, height(ep), 1), detail, ep.Start, ep.End, ep.Steps, ...
        ep.DurationDays, ep.LossKwh, ep.Chronic, ...
        VariableNames=["Id" "Cabin" "Type" "PV" "Severity" "Detail" "Start" "End" "Steps" "DurationDays" "LossKwh" "Chronic"]);
end
events = vertcat(parts{:});
if isempty(events)
    z = NaT(0, 1, TimeZone=TT.Time.TimeZone);
    events = table(strings(0, 1), zeros(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), z, z, zeros(0, 1), ...
        zeros(0, 1), zeros(0, 1), false(0, 1), ...
        VariableNames=["Id" "Cabin" "Type" "PV" "Severity" "Detail" "Start" "End" "Steps" "DurationDays" "LossKwh" "Chronic"]);
end
end
