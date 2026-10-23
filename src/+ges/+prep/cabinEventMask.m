function mask = cabinEventMask(data, flags, elevation, gRef)
%CABINEVENTMASK Kabin / şebeke olayı maskesi.
%   Çoklu eviricide (m >= 3): raporlayan eviricilerin >= %50'si aynı anda arızada/üretimsizse.
%   Tek eviricide (m < 3, SmartGridLab): L1 şebeke gerilimi/frekansı sınır dışıysa veya
%   gündüz DC gerilim varken şebeke gerilimi/frekansı sıfıra düşmüşse (qGridLoss).

m = numel(data);
n = numel(elevation);
if m >= 3
    down = false(n, m);
    reporting = false(n, m);
    for k = 1:m
        reporting(:,k) = ~isnan(data{k}.P_ac) | ~flags{k}.Missing;
        noPower = data{k}.P_ac <= 0.1 & elevation > 10 & gRef > 100;
        down(:,k) = flags{k}.Fault | (noPower & reporting(:,k));
    end
    nRep = sum(reporting, 2);
    mask = nRep >= 3 & sum(down, 2) >= 0.5 * nRep;
    return
end

mask = false(n, 1);
if m == 0
    return
end
TT = data{1};
v = string(TT.Properties.VariableNames);
if isfield(flags{1}, "GridLoss")
    mask = mask | flags{1}.GridLoss;
end
if ismember("U_L1", v) && ismember("f_grid", v)
    u = TT.U_L1;
    f = TT.f_grid;
    relayDuty = min(max(f / 50.0, 0), 1.0);
    uCond = u ./ max(relayDuty, 1e-3);
    gridOut = ~isnan(TT.P_ac) & TT.P_ac > 0.02 & ...
        (uCond < 195 | uCond > 253 | (relayDuty >= 0.98 & abs(f - 50) > 0.5));
    gridZero = elevation > 5 & gRef > 100 & ~isnan(TT.V_pv1) & TT.V_pv1 > 140 & (u == 0 | f == 0);
    mask = mask | gridOut | gridZero;
end
end
