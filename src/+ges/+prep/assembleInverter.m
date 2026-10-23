function P = assembleInverter(TT, f, pn, peerPn, row, meteoRef, cabinEvt, clipFraction, primarySource)
%ASSEMBLEINVERTER Ham veri + meteoroloji + bayraklar + öznitelikler -> işlenmiş invertör timetable.
%   P = ges.prep.assembleInverter(TT, f, pn, peerPn, row, meteoRef, cabinEvt, clipFraction, primarySource)
%   Eğitim zinciri (s03) ve veri yükleme hattı (ges.ingest.buildWorkspace) aynı fonksiyonu kullanır.
%   SmartGridLab (SMA WR13TL22-8231) için tüm 21 sütunu, türetilen elektriksel/termal/röle
%   büyüklüklerini ve tüm alt modüllerin beklediği geriye dönük takma adları (alias) üretir.

if nargin < 8 || isempty(clipFraction)
    clipFraction = 0.97;
end
if nargin < 9 || strlength(primarySource) == 0
    if isstruct(meteoRef.Properties.UserData) && isfield(meteoRef.Properties.UserData, "Primary")
        primarySource = string(meteoRef.Properties.UserData.Primary);
    else
        primarySource = "K01";
    end
end

P = TT;
n = height(P);
mVars = string(meteoRef.Properties.VariableNames);
wantMeteo = ["G_ref" "G_poa" "G_horiz" "MeteoSource" "T_mod" "T_mod_sat" "T_mod_sys" "T_amb" ...
    "WindSpeed" "T_cell_faiman" "Zenith" "Elevation" "SunAzimuth" "PoaCsRef" "GhiCs" "Kc" "KcVar" "SkyStep"];
for c = intersect(wantMeteo, mVars, "stable")
    P.(c) = meteoRef.(c);
end

pVars = string(P.Properties.VariableNames);
% Eksik temel veya takma ad sütunlarını tamamla (%100 geriye dönük ve ileriye dönük uyum)
if ~ismember("G_poa", pVars)
    P.G_poa = P.G_ref;
end
if ~ismember("G_horiz", pVars)
    if ismember("G", pVars), P.G_horiz = P.G; else, P.G_horiz = P.G_ref; end
end
P.G = P.G_horiz;
P.G_ref = P.G_poa;

if ~ismember("V_dc", pVars)
    if ismember("V_pv1", pVars), P.V_dc = P.V_pv1; else, P.V_dc = nan(n, 1); end
end
if ~ismember("I_dc", pVars)
    if ismember("I_pv1", pVars), P.I_dc = P.I_pv1; else, P.I_dc = nan(n, 1); end
end
P.V_pv1 = P.V_dc;
P.I_pv1 = P.I_dc;
for k = 2:8
    if ~ismember("V_pv" + k, pVars), P.("V_pv" + k) = nan(n, 1); end
    if ~ismember("I_pv" + k, pVars), P.("I_pv" + k) = nan(n, 1); end
end

if ~ismember("P_dc", pVars) || all(isnan(P.P_dc))
    P.P_dc = (P.V_dc .* P.I_dc) / 1000;
end
if ~ismember("P_ac_sys", pVars), P.P_ac_sys = P.P_ac; end
if ~ismember("P_ac_spec", pVars), P.P_ac_spec = P.P_ac / max(row.Rated(1), 1.20); end
if ~ismember("P_ac_spec_sys", pVars), P.P_ac_spec_sys = P.P_ac_spec; end

eta = P.P_ac ./ max(P.P_dc, 1e-4);
eta(P.P_dc < 0.015 | isnan(P.P_ac) | isnan(P.P_dc)) = NaN;
eta = min(max(eta, 0), 1.0);
P.Eta_inv = eta;
if ~ismember("Eff", pVars) || all(isnan(P.Eff))
    P.Eff = 100 * eta;
end

% Şebeke gerilim/akım/frekans ve röle görev oranı (alpha_relay = k/18)
if ~ismember("U_L1", pVars)
    if ismember("V_grid", pVars), P.U_L1 = P.V_grid;
    elseif ismember("U_ab", pVars), P.U_L1 = P.U_ab;
    else, P.U_L1 = nan(n, 1); end
end
if ~ismember("U_L2", pVars)
    if ismember("U_bc", pVars), P.U_L2 = P.U_bc; else, P.U_L2 = zeros(n, 1); end
end
if ~ismember("U_L3", pVars)
    if ismember("U_ca", pVars), P.U_L3 = P.U_ca; else, P.U_L3 = zeros(n, 1); end
end
P.V_grid = P.U_L1;
P.U_ab = P.U_L1;
P.U_bc = P.U_L2;
P.U_ca = P.U_L3;

if ~ismember("I_L1", pVars)
    if ismember("I_grid", pVars), P.I_L1 = P.I_grid;
    elseif ismember("I_a", pVars), P.I_L1 = P.I_a;
    else, P.I_L1 = nan(n, 1); end
end
if ~ismember("I_L2", pVars)
    if ismember("I_b", pVars), P.I_L2 = P.I_b; else, P.I_L2 = zeros(n, 1); end
end
if ~ismember("I_L3", pVars)
    if ismember("I_c", pVars), P.I_L3 = P.I_c; else, P.I_L3 = zeros(n, 1); end
end
P.I_grid = P.I_L1;
P.I_a = P.I_L1;
P.I_b = P.I_L2;
P.I_c = P.I_L3;

if ~ismember("f_grid", pVars)
    if ismember("Freq", pVars), P.f_grid = P.Freq; else, P.f_grid = nan(n, 1); end
end
P.Freq = P.f_grid;

relayDuty = min(max(P.f_grid / 50.0, 0), 1.0);
relayDuty(isnan(P.f_grid)) = NaN;
P.RelayDuty = relayDuty;
uCond = P.U_L1 ./ max(relayDuty, 1e-3);
uCond(isnan(relayDuty) | relayDuty < 0.05) = NaN;
P.U_L1_cond = uCond;

sAc = (P.U_L1 .* P.I_L1) / 1000;
qAc = sqrt(max(0, sAc.^2 - P.P_ac.^2));
pf = P.P_ac ./ max(sAc, 1e-4);
pf(sAc < 0.015 | isnan(sAc) | isnan(P.P_ac)) = NaN;
pf = min(max(pf, 0), 1.0);
P.S_ac = sAc;
P.P_grid_app = sAc;
P.Q_ac = qAc;
P.Q_grid = qAc;
if ~ismember("Q", pVars), P.Q = qAc; end
if ~ismember("PF", pVars) || all(isnan(P.PF)), P.PF = pf; end
if ~ismember("R_iso", pVars), P.R_iso = nan(n, 1); end
if ~ismember("SchedP_Pct", pVars), P.SchedP_Pct = nan(n, 1); end

% Sıcaklık ve Rüzgar Hızı
if ~ismember("T_mod_sat", pVars), P.T_mod_sat = P.T_mod; end
if ~ismember("T_mod_sys", pVars), P.T_mod_sys = P.T_mod_sat; end
if ~ismember("WindSpeed", pVars)
    if ismember("W_spd", pVars), P.WindSpeed = P.W_spd; else, P.WindSpeed = zeros(n, 1); end
end
P.W_spd = P.WindSpeed;

gPoaSafe = max(fillmissing(P.G_poa, "constant", 0), 0);
wSafe = fillmissing(max(P.WindSpeed, 0), "constant", 0.5);
tSs = P.T_amb + gPoaSafe ./ (25.0 + 6.84 * wSafe);
tFaiman = tSs;
alphaTh = exp(-15 / 12);
for i = 2:n
    if ~isnan(tFaiman(i-1)) && ~isnan(tSs(i))
        tFaiman(i) = alphaTh * tFaiman(i-1) + (1 - alphaTh) * tSs(i);
    end
end
P.T_cell_faiman = tFaiman;
P.T_cell_dyn = tFaiman;
P.DeltaT_wind = P.T_mod_sat - tFaiman;

vmpStc = 195.0;
betaV = -0.0031;
cV = 8.5;
tVdc = 25.0 + (P.V_dc - vmpStc - cV * log(max(gPoaSafe, 50) / 1000)) ./ (betaV * vmpStc);
tVdc(P.P_dc < 0.05 | isnan(P.V_dc) | gPoaSafe < 100) = NaN;
P.T_cell_vdc = min(max(tVdc, -10), 85);

if ~ismember("T_cab", pVars) || all(isnan(P.T_cab))
    pLoad = fillmissing(max(P.P_ac, 0), "constant", 0);
    P.T_cab = P.T_amb + 14.5 * (pLoad / max(row.Rated(1), 1.20)) + 0.012 * gPoaSafe ./ (1 + 0.25 * wSafe);
end

% Normalize güç ve Komşu / Fiziksel İkiz Oranı (PeerMedian & PeerRatio)
P.Pn = pn;
numValidPeers = sum(~isnan(peerPn), 2);
if size(peerPn, 2) >= 3 && any(numValidPeers >= 3)
    P.PeerMedian = median(peerPn, 2, "omitmissing");
    P.NumPeers = numValidPeers;
    P.PeerMedian(P.NumPeers < 3 | P.PeerMedian < 0.05) = NaN;
else
    % Tek evirici (SmartGridLab): Fiziksel POA + Sıcaklık düzeltmeli dijital ikiz referansı
    gammaP = -0.0037;
    pnTwin = (P.G_poa / 1000) .* (1 + gammaP * (P.T_cell_faiman - 25));
    pnTwin(P.G_poa < 50 | P.Elevation < 5 | isnan(P.G_poa)) = NaN;
    P.PeerMedian = pnTwin;
    P.NumPeers = double(~isnan(pnTwin));
end
P.PeerRatio = P.Pn ./ P.PeerMedian;

% Elektriksel + Metin Hibrit Durum Bayrakları
fFull = ges.prep.statusFlags(P);
if isstruct(f) && isfield(f, "OnGrid")
    % Çağıran tarafından verilen metinsel bayraklarla elektriksel bayrakları birleştir
    fFull.Fault = fFull.Fault | f.Fault;
    fFull.Derating = fFull.Derating | f.Derating;
    fFull.PowerLimit = fFull.PowerLimit | f.PowerLimit;
end

P.qMissing = isnan(P.P_ac);
P.qNight = meteoRef.Elevation < -2;
P.qOnGrid = fFull.OnGrid;
P.qFault = fFull.Fault;
P.qDerate = fFull.Derating;
P.qPowerLimit = fFull.PowerLimit;
P.qIdle = fFull.Idle;
P.qClip = P.P_ac >= clipFraction * row.Rated(1);
P.qCabinEvent = cabinEvt;
P.qMeteoFallback = string(meteoRef.MeteoSource) ~= primarySource & string(meteoRef.MeteoSource) ~= "K02";
P.qRebootEvent = fFull.RebootEvent;
P.qResetEvent = fFull.ResetEvent;
P.qRelayCycle = fFull.RelayCycle;
P.qWakeup = fFull.Wakeup;
P.qGridLoss = fFull.GridLoss;
P.qHighGridV = fFull.HighGridV;
P.qLowInsulation = fFull.LowInsulation;
P.qInverterEffDrop = fFull.InverterEffDrop;
P.qMeterMismatch = fFull.MeterMismatch;
P.qExportGap = fFull.ExportGap;

% String öznitelikleri (Tek stringde fiziksel referans akım ile)
currents = P{:, "I_pv" + (1:8)};
inst = logical(row.Installed(1, :));
if nnz(inst) == 1
    alphaI = 0.0005;
    iExpRef = 5.15 * (max(P.G_poa, 0) / 1000) .* (1 + alphaI * (P.T_cell_faiman - 25));
    s = ges.prep.stringFeatures(currents, inst, ExpectedCurrent=iExpRef, G=P.G_poa);
else
    s = ges.prep.stringFeatures(currents, inst);
end
P.I_median = s.Median;
P.I_norm = s.Norm;
P.NumDead = s.NumDead;
P.NumWeak = s.NumWeak;
P.DeadMask = s.DeadMask;
end
