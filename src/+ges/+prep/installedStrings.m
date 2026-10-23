function installed = installedStrings(TT, minDays)
%INSTALLEDSTRINGS En az MinDays farklı günde aktif akım taşımış PV girişleri kurulu sayılır.
%   Tek stringli küçük eviricilerde (ör. WR13TL22-8231, 1.20 kWp, I_max ~ 5.9 A)
%   eşik otomatik ölçeklenir; en az 1 string kurulu garantisi verilir.

if nargin < 2
    minDays = 20;
end
day = dateshift(TT.Time, "start", "day");
nTotalDays = numel(unique(day(~isnan(TT.P_ac))));
minDaysEff = min(minDays, max(1, round(0.2 * nTotalDays)));

installed = false(1, 8);
v = string(TT.Properties.VariableNames);
for k = 1:8
    col = "I_pv" + k;
    if ismember(col, v)
        cur = TT.(col);
        p99 = prctile(cur, 99);
        thr = min(1.0, max(0.2, 0.15 * p99));
        on = cur > thr;
        installed(k) = numel(unique(day(on))) >= minDaysEff;
    end
end
if ~any(installed) && ismember("I_pv1", v) && any(TT.I_pv1 > 0.05)
    installed(1) = true;
end
end
