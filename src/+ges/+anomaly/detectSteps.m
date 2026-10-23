function s = detectSteps(TT, ex, opts)
%DETECTSTEPS Sayısal ajan dedektörleri — adım düzeyinde bayraklar, seviyeler ve 3-katmanlı fiziksel tanılar.
%   s = ges.anomaly.detectSteps(TT, ex) — TT işlenmiş invertör verisi, ex
%   ges.anomaly.expectedPower çıktısı.
%   Temel alanlar (N×1 aksi belirtilmedikçe):
%     Valid            — M1 karşılaştırması anlamlı (ışınım, yükseklik, şebekede, clipping/kabin olayı yok)
%     Deficit          — (Pdc - P_dc)/Pdc, tüm kurulu stringlere göre toplam eksik üretim
%     ResidualDeficit  — (PdcWork - P_dc - throttleLoss)/Pdc, bilinen kayıplar DIŞINDA açıklanamayan eksik
%     DeficitLevel     — ResidualDeficit için kademeli seviye 0..3 (ges.anomaly.deviationLevel)
%     Trip, GridEvent, Derate, Offline, StringWeak — mantıksal
%     TripKind         — categorical: none | fault_status | idle_no_dc | zero_output
%     StringDead       — N×8 mantıksal (kalıcılığı sağlayan serilerin tamamı)
%     StringDeadCausal — N×8 mantıksal (nedensel gerçek zamanlı alarm)
%   SmartGridLab (%100 Sütun) zenginleştirilmiş alanlar:
%     RelayDuty        — k/18 şebeke röle görev oranı (f_grid / 50)
%     U_L1_cond        — de-aliased koşullu L1 şebeke gerilimi (U_L1 / max(RelayDuty, 1/18))
%     qRelayCycle      — düşük ışınım/uyanış röle anahtarlaması (0.05 <= RelayDuty < 0.98; arıza DEĞİLDİR)
%     qHighGridV       — aktif üretimde şebeke gerilim yükselmesi (U_L1_cond > 241.5 V)
%     qLowInsulation   — DC yalıtım direnci zayıflaması (R_iso < 1500 kOhm)
%     qMiddayLowIso    — güneşli öğle saatinde düşük yalıtım (R_iso < 2000 kOhm @ G>500, T>40)
%     qInverterEffDrop — DC->AC dönüşüm verimi çökmesi (Eta_inv < Eta_exp - 0.03)
%     qRebootEvent     — ızgara dışı (:10,:25,:50) veya gündüz SchedP_Pct=0 reset olayı
arguments
    TT timetable
    ex (1,1) struct
    opts.MinIrradiance (1,1) double = 150
    opts.MinElevation (1,1) double = 10
    opts.DeadSteps (1,1) double = 4
    opts.WeakSteps (1,1) double = 8
    opts.WeakRatio (1,1) double = 0.7
    opts.WeakIrradiance (1,1) double = 400
    opts.TripExpectedKw (1,1) double = 3
end

n = height(TT);
vars = TT.Properties.VariableNames;
lit = TT.Elevation > 5;
hasData = ~TT.qMissing;
seen = find(hasData);
inSpan = false(n, 1);
if ~isempty(seen)
    inSpan(seen(1):seen(end)) = true;
end

gEff = double(TT.G_ref);
if ismember("G_poa", vars) && any(~isnan(TT.G_poa))
    gEff = double(TT.G_poa);
end

% Nominal kapasiteye göre ölçekli TripExpectedKw (1.20 kWp SmartGridLab'da 3 kW yerine ~0.12 kW)
capEst = max(max(ex.Pdc, [], "omitnan"), max(TT.P_dc, [], "omitnan"));
if isnan(capEst) || capEst <= 0
    capEst = 1.20;
end
tripKw = opts.TripExpectedKw;
if capEst < 5 && opts.TripExpectedKw >= 1
    tripKw = max(0.08 * capEst, 0.08);
end

% --- k/18 Şebeke Röle Görev Oranı (De-aliasing) ve L1 Şebeke Doğrulaması ---
s.RelayDuty = ones(n, 1);
s.U_L1_cond = repmat(230, n, 1);
s.qRelayCycle = false(n, 1);
s.qHighGridV = false(n, 1);

hasGrid = (ismember("U_L1", vars) || ismember("V_grid", vars)) && ismember("f_grid", vars);
vdc = getSignal(TT, ["V_dc" "V_pv1"], NaN);
idc = getSignal(TT, ["I_dc" "I_pv1"], NaN);

if hasGrid
    uL1 = getSignal(TT, ["U_L1" "V_grid"], NaN);
    fGrid = double(TT.f_grid);
    if ismember("RelayDuty", vars)
        s.RelayDuty = double(TT.RelayDuty);
    else
        s.RelayDuty = min(max(fGrid / 50.0, 0), 1);
    end
    if ismember("U_L1_cond", vars)
        s.U_L1_cond = double(TT.U_L1_cond);
    else
        s.U_L1_cond = uL1 ./ max(s.RelayDuty, 1/18);
    end
    if ismember("qRelayCycle", vars)
        s.qRelayCycle = logical(TT.qRelayCycle);
    else
        s.qRelayCycle = (s.RelayDuty >= 0.05 & s.RelayDuty < 0.98) & ...
            (s.U_L1_cond >= 200 & s.U_L1_cond <= 253) & ...
            (gEff < 280 | TT.Elevation < 18 | fillmissing(TT.P_ac, "constant", 0) == 0);
    end
    s.qHighGridV = s.RelayDuty >= 0.98 & s.U_L1_cond > 241.5 & fillmissing(TT.P_ac, "constant", 0) > 0.05 * capEst;

    % Gerçek şebeke olayı: (A) gündüz DC gerilim varken U_L1=0 / f_grid=0 (örn. 29 Temmuz 11:45 AM),
    % veya (B) röle tam bağlıyken EN 50160 gerilim/frekans sınır ihlali
    dayGridLoss = gEff > 150 & TT.Elevation > 10 & vdc > 120 & (uL1 == 0 | fGrid == 0) & hasData;
    en50160Viol = s.RelayDuty >= 0.98 & (s.U_L1_cond < 195 | s.U_L1_cond > 253 | abs(fGrid - 50) > 0.5) & lit & hasData;
    cabinEv = (TT.qCabinEvent & ~s.qRelayCycle) | dayGridLoss | en50160Viol;
else
    cabinEv = TT.qCabinEvent;
end

s.Valid = gEff > opts.MinIrradiance & TT.Elevation > opts.MinElevation & TT.qOnGrid ...
    & ~TT.qClip & ~cabinEv & ~s.qRelayCycle & ~isnan(TT.P_dc);

% --- Gizli Isıl Kısma (V/I İmzası) ve Planlı Güç Sınırı ---
throttleLoss = zeros(n, 1);
s.Throttle = false(n, 1);
if ismember("qThrottle", vars)
    s.Throttle = logical(TT.qThrottle);
    if ismember("ThrottleLossKw", vars)
        throttleLoss = fillmissing(double(TT.ThrottleLossKw), "constant", 0);
    end
end
% 29.08.2026 11:30 AM gibi açık devreye sıçrayan kısma adımı (G>400, V_dc>215V, I_dc<0.1A)
vocCurtail = gEff > 400 & TT.Elevation > 15 & vdc > 215 & idc < 0.10 & hasData & ~cabinEv;
if any(vocCurtail)
    % Komşu adımlarda aktif üretim veya kısma varsa bunu kısma/sınırlama dizisine dahil et
    nearActive = movmax(double(fillmissing(TT.P_ac, "constant", 0) > 0.05 * capEst | s.Throttle), [2 2]) == 1;
    vocCurtail = vocCurtail & nearActive;
    s.Throttle = s.Throttle | vocCurtail;
    throttleLoss(vocCurtail) = max(ex.PdcWork(vocCurtail) - fillmissing(TT.P_dc(vocCurtail), "constant", 0), 0);
end

s.ThrottleDuty = movmean(double(s.Throttle), [7 0], Endpoints="shrink");
s.Deficit = (ex.Pdc - TT.P_dc) ./ max(ex.Pdc, eps);
s.ResidualDeficit = (ex.PdcWork - TT.P_dc - throttleLoss) ./ max(ex.Pdc, eps);
s.DeficitLevel = ges.anomaly.deviationLevel(TT.P_dc + (ex.Pdc - ex.PdcWork) + throttleLoss, ex.Pdc, s.Valid);

% --- Trip ve TripKind ---
noOutput = fillmissing(TT.P_ac, "constant", 0) <= 0.02 * capEst & ex.Pdc > tripKw & hasData & ~s.qRelayCycle & ~vocCurtail;
s.Trip = (TT.qFault | noOutput) & ~cabinEv & lit;
kind = repmat("zero_output", n, 1);
iMed = getSignal(TT, ["I_median" "I_dc" "I_pv1"], 0);
qIdle = false(n, 1);
if ismember("qIdle", vars), qIdle = logical(TT.qIdle); end
kind((qIdle | vdc > 120) & ~(iMed > 0.05)) = "idle_no_dc";
kind(TT.qFault) = "fault_status";
kind(~s.Trip) = "none";
s.TripKind = categorical(kind, ["none" "fault_status" "idle_no_dc" "zero_output"]);

s.GridEvent = cabinEv & lit;
qPowLim = false(n, 1);
if ismember("qPowerLimit", vars), qPowLim = logical(TT.qPowerLimit); end
s.Derate = TT.qDerate | s.Throttle | (qPowLim & lit & gEff > 200);
s.Offline = TT.qMissing & lit & inSpan;

% --- Yalıtım Direnci (R_iso), Dönüşüm Verimi (Eta_inv) ve Reset/Reboot Bayrakları ---
riso = getSignal(TT, "R_iso", 3000);
s.qLowInsulation = riso < 1500 & lit & hasData;
tMod = getSignal(TT, ["T_cell_dyn" "T_mod"], 25);
s.qMiddayLowIso = riso < 2000 & gEff > 500 & tMod > 40 & hasData;

etaMeas = getSignal(TT, "Eta_inv", NaN);
if all(isnan(etaMeas)) && ismember("Eff", vars)
    etaMeas = double(TT.Eff) / 100;
elseif all(isnan(etaMeas))
    etaMeas = double(TT.P_ac) ./ max(double(TT.P_dc), eps);
end
etaExp = repmat(0.9356, n, 1);
if isfield(ex, "EtaExp") && numel(ex.EtaExp) == n
    etaExp = fillmissing(ex.EtaExp, "constant", 0.9356);
end
s.EtaResidual = etaMeas - etaExp;
s.qInverterEffDrop = TT.P_dc > 0.15 * capEst & TT.P_ac > 0.05 * capEst & s.EtaResidual < -0.03 & s.Valid;

s.qRebootEvent = false(n, 1);
for rn = ["qRebootEvent" "qResetEvent"]
    if ismember(rn, vars)
        s.qRebootEvent = s.qRebootEvent | logical(TT.(rn));
    end
end
if ismember("SchedP_Pct", vars)
    s.qRebootEvent = s.qRebootEvent | (TT.SchedP_Pct == 0 & lit);
end

% --- StringDead ve StringWeak (8-String ve Tek-String 4-Kadranlı Uyum) ---
deadMask = uint8(zeros(n, 1));
if ismember("DeadMask", vars)
    deadMask = uint8(fillmissing(TT.DeadMask, "constant", 0));
end
% Tek-string / tek-MPPT sistemde (SmartGridLab) gerilim çökmesi (dV < -0.05) veya
% sabit gerilimde büyük akım çökmesi (dI <= -0.35) DeadMask bit-1'e işlenir
if ismember("dV", vars) && ismember("dI", vars)
    vDrop = s.Valid & ~s.Throttle & ((TT.dV < -0.05 & TT.dI > -0.20) | (abs(TT.dV) <= 0.05 & TT.dI <= -0.35));
    deadMask(vDrop) = bitor(deadMask(vDrop), uint8(1));
end

s.StringDead = sustainBackward(deadMask, opts.DeadSteps);
s.StringDeadCausal = false(n, 8);
for k = 1:8
    raw = double(bitget(deadMask, k) == 1);
    s.StringDeadCausal(:, k) = movmin(raw, [opts.DeadSteps - 1, 0], Endpoints="fill") == 1;
end
deadNow = false(n, 8);
for k = 1:8
    deadNow(:, k) = bitget(deadMask, k) == 1;
end

iMinMed = min(2.0, 0.4 * capEst);
weakRaw = false(n, 1);
if ismember("I_norm", vars)
    weakRaw = any(TT.I_norm < opts.WeakRatio & ~deadNow, 2) & gEff > opts.WeakIrradiance & iMed > iMinMed;
end
if ismember("dI", vars)
    weakSingle = s.Valid & ~s.Throttle & ~any(deadNow, 2) & TT.dI < -(1 - opts.WeakRatio) & gEff > opts.WeakIrradiance;
    weakRaw = weakRaw | weakSingle;
end
s.StringWeak = movmin(double(weakRaw), [opts.WeakSteps - 1, 0], Endpoints="fill") == 1;

stringsVisible = lit & hasData & iMed > iMinMed;
s.Obs = struct( ...
    "Trip", lit & hasData & ex.Pdc > tripKw, ...
    "GridEvent", lit & hasData, ...
    "StringDead", stringsVisible, ...
    "StringWeak", stringsVisible & gEff > opts.WeakIrradiance, ...
    "Deficit", s.Valid, ...
    "Derate", lit & hasData & gEff > 250, ...
    "Offline", lit & inSpan);
end

function v = getSignal(TT, names, defaultVal)
v = repmat(defaultVal, height(TT), 1);
for nm = string(names(:))'
    if ismember(nm, TT.Properties.VariableNames)
        v = double(TT.(nm));
        return
    end
end
end

function dead = sustainBackward(mask, minSteps)
dead = false(numel(mask), 8);
for k = 1:8
    m = bitget(mask, k) == 1;
    d = diff([false; m; false]);
    starts = find(d == 1);
    ends = find(d == -1) - 1;
    long = (ends - starts + 1) >= minSteps;
    for r = find(long)'
        dead(starts(r):ends(r), k) = true;
    end
end
end
