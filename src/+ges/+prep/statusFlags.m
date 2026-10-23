function f = statusFlags(statusOrTT, TTopt)
%STATUSFLAGS Huawei "Status" metninden ve/veya SMA elektriksel sinyallerinden durum bayrakları üretir.
%   f = ges.prep.statusFlags(status)       — categorical/string Status vektörü
%   f = ges.prep.statusFlags(TT)           — doğrudan cihaz timetable'ı (SMA veya Huawei)
%   f = ges.prep.statusFlags(status, TT)   — hem Status hem TT
%
%   Temel alanlar (N×1 logical):
%     OnGrid, Fault, Derating, PowerLimit, Idle, Missing
%   SmartGridLab genişletilmiş alanlar (N×1 logical):
%     Wakeup, RelayCycle, GridLoss, RebootEvent, ResetEvent,
%     HighGridV, LowInsulation, InverterEffDrop, MeterMismatch, ExportGap

if istimetable(statusOrTT) || istable(statusOrTT)
    TT = statusOrTT;
    if ismember("Status", TT.Properties.VariableNames)
        s = string(TT.Status(:));
    else
        s = repmat("", height(TT), 1);
    end
else
    s = string(statusOrTT(:));
    if nargin >= 2 && (istimetable(TTopt) || istable(TTopt))
        TT = TTopt;
    else
        TT = table();
    end
end

n = numel(s);
f.OnGrid = startsWith(s, "On-grid");
f.Fault = s == "Shutdown: Fault";
f.Derating = s == "On-grid:self derating";
f.PowerLimit = s == "On-grid: Power limit";
f.Idle = startsWith(s, "Idle");
f.Missing = ismissing(s) | strlength(s) == 0;

% Varsayılan genişletilmiş bayraklar
f.Wakeup = false(n, 1);
f.RelayCycle = false(n, 1);
f.GridLoss = false(n, 1);
f.RebootEvent = false(n, 1);
f.ResetEvent = false(n, 1);
f.HighGridV = false(n, 1);
f.LowInsulation = false(n, 1);
f.InverterEffDrop = false(n, 1);
f.MeterMismatch = false(n, 1);
f.ExportGap = false(n, 1);

if isempty(TT) || height(TT) ~= n
    return
end

v = string(TT.Properties.VariableNames);
has = @(c) ismember(c, v);

if has("P_ac") && has("V_dc")
    pAc = TT.P_ac;
    vDc = TT.V_dc;
    iDc = zeros(n, 1);
    if has("I_dc"), iDc = TT.I_dc; elseif has("I_pv1"), iDc = TT.I_pv1; end
    uL1 = repmat(230, n, 1);
    if has("U_L1"), uL1 = TT.U_L1; elseif has("V_grid"), uL1 = TT.V_grid; end
    fGrid = repmat(50, n, 1);
    if has("f_grid"), fGrid = TT.f_grid; elseif has("Freq"), fGrid = TT.Freq; end
    gHoriz = zeros(n, 1);
    if has("G_horiz"), gHoriz = TT.G_horiz; elseif has("G"), gHoriz = TT.G; end
    rIso = repmat(3000, n, 1);
    if has("R_iso"), rIso = TT.R_iso; end
    schedP = nan(n, 1);
    if has("SchedP_Pct"), schedP = TT.SchedP_Pct; end

    % 1) Röle görev oranı (alpha_relay = k/18) ve koşullu şebeke gerilimi
    relayDuty = min(max(fGrid / 50.0, 0), 1.0);
    uCond = uL1 ./ max(relayDuty, 1e-3);
    uCond(relayDuty < 0.05 | isnan(relayDuty)) = NaN;

    f.RelayCycle = (relayDuty > 0.05 & relayDuty < 0.98) & (uCond >= 195 & uCond <= 253);
    f.Wakeup = (pAc == 0 & iDc < 0.05 & ~isnan(vDc) & uL1 > 0) | f.RelayCycle;

    % 2) Gündüz gerçek şebeke kesintisi (ör. 07/29/2026 11:45 AM: G=873, V_dc=238V, U_L1=0, f_grid=0)
    f.GridLoss = gHoriz > 80 & ~isnan(vDc) & vDc > 140 & (uL1 == 0 | fGrid == 0);

    % 3) Reboot / Reconnect el sıkışması vs. gerçek güç sınırlaması
    if has("qRebootEvent")
        f.RebootEvent = logical(TT.qRebootEvent);
    else
        prevOff = [false; isnan(pAc(1:end-1)) & gHoriz(1:end-1) > 80];
        f.RebootEvent = ~isnan(schedP) & schedP == 0 & (isnan(pAc) | prevOff);
    end
    f.ResetEvent = f.RebootEvent;
    f.PowerLimit = f.PowerLimit | (~isnan(schedP) & schedP > 0 & schedP < 100) | ...
        (~isnan(schedP) & schedP == 0 & pAc <= 0.02 & gHoriz > 200 & ~f.RebootEvent);

    % 4) Ek kalite ve sağlık bayrakları
    f.HighGridV = ~isnan(uL1) & uL1 > 242;
    f.LowInsulation = ~isnan(rIso) & rIso < 1500;
    if has("Eta_inv")
        f.InverterEffDrop = ~isnan(TT.Eta_inv) & pAc > 0.15 & TT.Eta_inv < 0.88;
    end
    if has("P_ac_sys")
        f.MeterMismatch = ~isnan(pAc) & ~isnan(TT.P_ac_sys) & abs(pAc - TT.P_ac_sys) > 0.05;
    end
    f.ExportGap = isnan(gHoriz) & isnan(pAc);

    % 5) Ana bayrakların elektriksel doğrulaması
    f.OnGrid = (pAc > 0 & uCond >= 195 & uCond <= 253 & fGrid >= 47.0 & fGrid <= 51.0);
    f.Idle = f.Wakeup | (isnan(pAc) & gHoriz <= 25);
    f.Fault = f.GridLoss | (~isnan(rIso) & rIso < 500) | ...
        (gHoriz > 100 & (isnan(pAc) | (pAc == 0 & ~f.Wakeup)) & ~f.PowerLimit);
    f.Missing = isnan(pAc);
end
end
