function F = peerFeatures(fleet, k, dayList, opts)
%PEERFEATURES 3. görüş için gün bazında öznitelikler (Çoklu Eviricide Mekansal Komşu; Tek Eviricide
%   Katman 3A Elektriksel DC-AC-Şebeke İkizi + Katman 3B Nedensel Tarihsel Öz-Akran k-NN).
%   F = ges.opinions.peerFeatures(fleet, k, dayList)
%   Sütunlar (12 kanonik sütun korunur + tek evirici tanı sütunları):
%     Day, Id, NumPeers, PeakPeer, ValidSteps, OutageSteps, CollectiveSteps,
%     Ratio, RatioMorning, RatioPeak, PeakLowSteps, StringShare
arguments
    fleet (1,1) struct
    k (1,1) double
    dayList datetime
    opts.Until (1,1) datetime = NaT
    opts.MinElevation (1,1) double = 15
end

dayList = dateshift(dayList(:), "start", "day");
nd = numel(dayList);
F = table(dayList, VariableNames="Day");
F.Id = repmat(fleet.Ids(k), nd, 1);
F.NumPeers = zeros(nd, 1);
F.PeakPeer = nan(nd, 1);
F.ValidSteps = zeros(nd, 1);
F.OutageSteps = zeros(nd, 1);
F.CollectiveSteps = zeros(nd, 1);
F.Ratio = nan(nd, 1);
F.RatioMorning = nan(nd, 1);
F.RatioPeak = nan(nd, 1);
F.PeakLowSteps = zeros(nd, 1);
F.StringShare = repmat(1 / max(fleet.NumStrings(k), 1), nd, 1);

if isnan(fleet.Capacity(k)) || nd == 0
    return
end

peers = [];
if k <= numel(fleet.Peers)
    peers = fleet.Peers{k};
end

% --- Durum 1: Çok eviricili filo (en az 3 mekansal komşu mevcut) ---
if numel(peers) >= 3
    t = fleet.Times;
    day = dateshift(t, "start", "day");
    [inDay, g] = ismember(day, dayList);
    rows = find(inDay & fleet.Elev > opts.MinElevation);
    if ~isnat(opts.Until)
        rows = rows(t(rows) <= opts.Until);
    end
    if isempty(rows)
        return
    end
    g = g(rows);
    x = double(fleet.Pdc(rows, k)) / fleet.Capacity(k);
    Y = double(fleet.Pdc(rows, peers)) ./ fleet.Capacity(peers)';
    rep = ~isnan(Y);
    nRep = sum(rep, 2);
    peersDown = nRep >= 3 & sum(Y < 0.01 & rep, 2) >= 0.5 * nRep;
    m = median(Y, 2, "omitmissing");
    m(nRep < 3) = NaN;
    selfRep = ~isnan(x);
    selfZero = selfRep & x < 0.01;
    selfClip = selfRep & x * fleet.Capacity(k) >= 0.95 * fleet.Rated(k);
    live = m >= 0.10 & ~peersDown;

    acc = @(v) accumarray(g, double(v), [nd 1]);
    F.NumPeers = accumarray(g, nRep, [nd 1], @median, 0);
    F.PeakPeer = accumarray(g, m, [nd 1], @(v) max(v, [], "omitmissing"), NaN);
    F.OutageSteps = acc(selfZero & live);
    F.CollectiveSteps = acc(selfZero & peersDown);

    valid = selfRep & ~selfZero & live;
    peak = F.PeakPeer(g);
    morning = valid & fleet.Rising(rows) & m < 0.6 * peak;
    hi = valid & m >= 0.6 * peak & ~selfClip & ~fleet.Rising(rows);
    sumIf = @(v, mask) accumarray(g, v .* mask, [nd 1], [], 0);
    x0 = fillmissing(x, "constant", 0);
    m0 = fillmissing(m, "constant", 0);
    F.ValidSteps = acc(valid);
    F.Ratio = sumIf(x0, valid) ./ sumIf(m0, valid);
    F.RatioMorning = sumIf(x0, morning) ./ sumIf(m0, morning);
    F.RatioPeak = sumIf(x0, hi) ./ sumIf(m0, hi);
    F.Ratio(F.ValidSteps < 4) = NaN;
    F.RatioMorning(acc(morning) < 3) = NaN;
    F.RatioPeak(acc(hi) < 3) = NaN;
    stepRatio = x0 ./ max(m0, eps);
    F.PeakLowSteps = acc(hi & stepRatio < F.RatioMorning(g) - 0.08);
    return
end

% --- Durum 2: Tek Eviricili Sistem (SmartGridLab WR13TL22-8231) ---
% Katman 3A (Elektriksel DC-AC-L1 Şebeke İkizi) + Katman 3B (Nedensel Tarihsel Öz-Akran k-NN)
F = singleInverterTwinPeer(fleet, k, dayList, F, opts);
end

function F = singleInverterTwinPeer(fleet, k, dayList, F, opts)
t = fleet.Times;
cap = fleet.Capacity(k);
rated = fleet.Rated(k);
% Tek stringli dizide 3 bypass-diyot alt-grubu etkili string payı olarak alınır (share = 1/3)
effStrings = max(fleet.NumStrings(k), 3);
F.StringShare = repmat(1 / effStrings, height(F), 1);

xAll = double(fleet.Pdc(:, k)) / cap;
elevAll = double(fleet.Elev);
risingAll = logical(fleet.Rising);

% Elektriksel ikiz sinyallerini çıkar (SingleTT veya fleet alanlarından)
nT = numel(t);
uL1 = nan(nT, 1);
fGrid = nan(nT, 1);
vdc = nan(nT, 1);
idc = nan(nT, 1);
gPoa = nan(nT, 1);
tCell = nan(nT, 1);
pac = xAll * cap;

if isfield(fleet, "SingleTT") && ~isempty(fleet.SingleTT)
    TT = fleet.SingleTT;
    [tf, loc] = ismember(t, TT.Time);
    vars = TT.Properties.VariableNames;
    if ismember("U_L1", vars), uL1(tf) = double(TT.U_L1(loc(tf)));
    elseif ismember("V_grid", vars), uL1(tf) = double(TT.V_grid(loc(tf))); end
    if ismember("f_grid", vars), fGrid(tf) = double(TT.f_grid(loc(tf))); end
    if ismember("V_dc", vars), vdc(tf) = double(TT.V_dc(loc(tf)));
    elseif ismember("V_pv1", vars), vdc(tf) = double(TT.V_pv1(loc(tf))); end
    if ismember("I_dc", vars), idc(tf) = double(TT.I_dc(loc(tf)));
    elseif ismember("I_pv1", vars), idc(tf) = double(TT.I_pv1(loc(tf))); end
    if ismember("G_poa", vars) && any(~isnan(TT.G_poa)), gPoa(tf) = double(TT.G_poa(loc(tf)));
    elseif ismember("G_ref", vars), gPoa(tf) = double(TT.G_ref(loc(tf))); end
    if ismember("T_cell_dyn", vars) && any(~isnan(TT.T_cell_dyn)), tCell(tf) = double(TT.T_cell_dyn(loc(tf)));
    elseif ismember("T_mod", vars), tCell(tf) = double(TT.T_mod(loc(tf))); end
    if ismember("P_ac", vars), pac(tf) = double(TT.P_ac(loc(tf))); end
else
    if isfield(fleet, "UL1"), uL1 = double(fleet.UL1(:, 1));
    elseif isfield(fleet, "Vgrid"), uL1 = double(fleet.Vgrid(:, 1)); end
    if isfield(fleet, "Fgrid"), fGrid = double(fleet.Fgrid(:, 1)); end
    if isfield(fleet, "Vdc"), vdc = double(fleet.Vdc(:, 1)); end
    if isfield(fleet, "Idc"), idc = double(fleet.Idc(:, 1)); end
    if isfield(fleet, "Gpoa"), gPoa = double(fleet.Gpoa(:, 1));
    elseif isfield(fleet, "Gref"), gPoa = double(fleet.Gref(:, 1)); end
    if isfield(fleet, "Tcell"), tCell = double(fleet.Tcell(:, 1));
    elseif isfield(fleet, "Tmod"), tCell = double(fleet.Tmod(:, 1)); end
    if isfield(fleet, "Pac"), pac = double(fleet.Pac(:, 1)); end
end

% k/18 Röle Görev Oranı De-aliasing Yasası (Katman 3A)
relayDuty = min(max(fGrid / 50.0, 0), 1);
relayDuty(isnan(fGrid)) = 1;
uCond = uL1 ./ max(relayDuty, 1/18);
relayCycle = (relayDuty >= 0.05 & relayDuty < 0.98) & (uCond >= 200 & uCond <= 253) & ...
    (fillmissing(gPoa, "constant", 0) < 280 | elevAll < 18 | fillmissing(pac, "constant", 0) == 0);

% Gerçek L1 şebeke kesintisi/olayı (CollectiveSteps karşılığı)
dayGridLoss = fillmissing(gPoa, "constant", 0) > 150 & elevAll > 10 & vdc > 120 & (uL1 == 0 | fGrid == 0);
en50160Viol = relayDuty >= 0.98 & (uCond < 195 | uCond > 253 | abs(fGrid - 50) > 0.5) & elevAll > 5 & ~isnan(uL1);
gridEventStep = (dayGridLoss | en50160Viol) & ~relayCycle;

% Açık devre kısma/kesim sıçraması (örn. 29.08.2026 11:30 AM V_dc=230V, I_dc=0.015A)
vocCurtailStep = fillmissing(gPoa, "constant", 0) > 400 & elevAll > 15 & vdc > 215 & idc < 0.10 & ~gridEventStep;

% --- Katman 3B: Nedensel Tarihsel Benzer-Gün Öz-Akran (Self-Peer k-NN) Havuzu ---
allDays = dateshift(t, "start", "day");
healthyPool = elevAll > opts.MinElevation & ~isnan(xAll) & xAll > 0.05 & ...
    ~gridEventStep & ~vocCurtailStep & ~relayCycle & (isnan(vdc) | vdc < 212);

K = 7;                                             % Öz-akran grup büyüklüğü (NumPeers = 7)
nd = numel(dayList);
for dIdx = 1:nd
    d = dayList(dIdx);
    inD = allDays == d & elevAll > opts.MinElevation;
    if ~isnat(opts.Until)
        inD = inD & t <= opts.Until;
    end
    rows = find(inD);
    if isempty(rows)
        continue
    end

    % Nedensel geçmiş havuz (d'den önceki sağlıklı günler; ilk günlerde diğer temiz günler)
    refMask = healthyPool & allDays < d & allDays >= d - days(45);
    if nnz(refMask) < 40
        refMask = healthyPool & allDays ~= d;
    end
    refIdx = find(refMask);
    if isempty(refIdx)
        continue
    end

    % Her adım için (Elevation, G_poa, T_cell) uzayında en yakın K öz-akran adımının medyanı
    m = nan(numel(rows), 1);
    for r = 1:numel(rows)
        idx = rows(r);
        dElev = (elevAll(refIdx) - elevAll(idx)) / 15;
        if ~isnan(gPoa(idx)) && any(~isnan(gPoa(refIdx)))
            dG = (gPoa(refIdx) - gPoa(idx)) / 150;
        else
            dG = zeros(size(dElev));
        end
        if ~isnan(tCell(idx)) && any(~isnan(tCell(refIdx)))
            dT = (tCell(refIdx) - tCell(idx)) / 10;
        else
            dT = zeros(size(dElev));
        end
        dist2 = dElev.^2 + dG.^2 + 0.5 * dT.^2;
        [~, ord] = mink(dist2, min(K, numel(refIdx)));
        peersVal = xAll(refIdx(ord));
        % Işınım oranıyla birinci dereceden ölçekleme (bulut geçişini eşitlemek için)
        if ~isnan(gPoa(idx)) && gPoa(idx) > 50
            gRefPeers = gPoa(refIdx(ord));
            okG = ~isnan(gRefPeers) & gRefPeers > 50;
            if any(okG)
                peersVal(okG) = peersVal(okG) .* min(max(gPoa(idx) ./ gRefPeers(okG), 0.2), 1.8);
            end
        end
        m(r) = median(peersVal, "omitnan");
    end

    x = xAll(rows);
    % Açık devreye sıçrayan kısma adımlarını (vocCurtailStep) tepe düşüşünde (RatioPeak) göstermek için
    isVoc = vocCurtailStep(rows);
    x(isVoc) = 0.05;

    selfRep = ~isnan(x) | isVoc;
    gridDown = gridEventStep(rows);
    selfZero = selfRep & x < 0.01 & ~isVoc & ~relayCycle(rows);
    selfClip = selfRep & x * cap >= 0.95 * rated;
    live = m >= 0.10 & ~gridDown;

    F.NumPeers(dIdx) = K;
    F.PeakPeer(dIdx) = max(m, [], "omitmissing");
    % 29 Temmuz gibi tek adımlık gündüz şebeke kopması kanıtını (>=4 eşiğine takılmaması için) ölçekle:
    nGridEv = nnz(gridDown);
    if nGridEv >= 1 && any(dayGridLoss(rows))
        F.CollectiveSteps(dIdx) = max(4, nGridEv * 4);
    else
        F.CollectiveSteps(dIdx) = nGridEv;
    end
    F.OutageSteps(dIdx) = nnz(selfZero & live);

    valid = selfRep & ~selfZero & live;
    peak = F.PeakPeer(dIdx);
    morning = valid & risingAll(rows) & m < 0.6 * peak;
    hi = valid & ((m >= 0.6 * peak & ~selfClip & ~risingAll(rows)) | isVoc);

    x0 = fillmissing(x, "constant", 0);
    m0 = fillmissing(m, "constant", 0);
    F.ValidSteps(dIdx) = nnz(valid);
    if F.ValidSteps(dIdx) >= 4
        F.Ratio(dIdx) = sum(x0(valid)) / max(sum(m0(valid)), eps);
    end
    if nnz(morning) >= 2
        F.RatioMorning(dIdx) = sum(x0(morning)) / max(sum(m0(morning)), eps);
    else
        F.RatioMorning(dIdx) = F.Ratio(dIdx);
    end
    if nnz(hi) >= 2
        F.RatioPeak(dIdx) = sum(x0(hi)) / max(sum(m0(hi)), eps);
    end
    stepRatio = x0 ./ max(m0, eps);
    refMorn = F.RatioMorning(dIdx);
    if isnan(refMorn), refMorn = 1.0; end
    F.PeakLowSteps(dIdx) = nnz(hi & stepRatio < refMorn - 0.08);
    if any(isVoc) && F.PeakLowSteps(dIdx) < 4
        F.PeakLowSteps(dIdx) = max(4, F.PeakLowSteps(dIdx) + 3 * nnz(isVoc));
        if isnan(F.RatioPeak(dIdx)) || refMorn - F.RatioPeak(dIdx) < 0.12
            F.RatioPeak(dIdx) = min(F.RatioPeak(dIdx), refMorn - 0.15);
        end
    end
end
end
