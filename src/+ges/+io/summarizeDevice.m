function s = summarizeDevice(TT, meta, report)
%SUMMARIZEDEVICE Birleştirilmiş cihaz timetable'ı için tek satırlık kalite/künye özeti.
%   s = ges.io.summarizeDevice(TT, meta, report) cihaz kaydı (registry)
%   için bir struct döndürür. Hem SMA (WR13TL22-8231) hem Huawei cihazlarını destekler.

arguments
    TT timetable
    meta (1,:) table
    report (1,1) struct
end

s = table2struct(meta(1, :));
s.Groups = strjoin(sort(report.Groups), ",");
s.NumGroups = numel(report.Groups);
s.NumSteps = height(TT);
s.Start = NaT(TimeZone="Europe/Istanbul");
s.End = NaT(TimeZone="Europe/Istanbul");
s.ValidPct = NaN;
s.DuplicateTimes = sum(report.DuplicateTimes);
s.OffGridTimes = sum(report.OffGridTimes);
s.P_ac_max = NaN;
s.P_ac_p999 = NaN;
s.ActiveStrings = NaN;
s.HasPvVoltage = any(report.Groups == "pvVoltage");
s.FaultSteps = NaN;
s.DeratingSteps = NaN;
s.R_iso_min = NaN;
s.Eta_median = NaN;
s.ResetEventSteps = 0;

if height(TT) == 0
    return
end
s.Start = TT.Time(1);
s.End = TT.Time(end);
numeric = TT(:, vartype("numeric"));
s.ValidPct = 100 * mean(any(~ismissing(numeric), 2));

v = string(TT.Properties.VariableNames);
if any(v == "P_ac")
    s.P_ac_max = max(TT.P_ac, [], "omitmissing");
    s.P_ac_p999 = prctile(TT.P_ac, 99.9);
end
if any(v == "V_dc") || any(v == "V_pv1")
    s.HasPvVoltage = any(~isnan(TT.V_pv1));
end
currents = v(startsWith(v, "I_pv"));
if ~isempty(currents)
    s.ActiveStrings = nnz(max(TT{:, currents}, [], 1, "omitmissing") > 0.3);
end
if any(v == "Status") && meta.Kind(1) == "inverter"
    s.FaultSteps = nnz(TT.Status == "Shutdown: Fault");
    s.DeratingSteps = nnz(TT.Status == "On-grid:self derating");
end
if any(v == "R_iso")
    s.R_iso_min = min(TT.R_iso, [], "omitmissing");
end
if any(v == "Eff")
    ok = TT.P_ac > 0.2 * max(s.P_ac_max, 0.5) & TT.Eff > 50 & TT.Eff <= 100;
    if any(ok)
        s.Eta_median = median(TT.Eff(ok), "omitmissing");
    end
end
if any(v == "qRebootEvent")
    s.ResetEventSteps = nnz(TT.qRebootEvent);
end
end
