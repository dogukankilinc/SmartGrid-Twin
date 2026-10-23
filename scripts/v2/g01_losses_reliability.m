%% G01_LOSSES_RELIABILITY  v2/v3-G: 8/10 kademeli fiziksel enerji kayıp şelalesi, L1 Thevenin empedansı ve bakım aralıkları.
% SmartGridLab v3 Geliştirmeleri:
%   1) Klasik 9 kategorili kayıp tablosu (L) korunurken, STC'den AC şebekeye 10 kademeli tam fiziksel
%      enerji şelalesi (Waterfall) hesaplanır:
%      E_horiz_stc -> +E_poa_gain -> -E_iam_loss -> -E_temp_ross -> +E_wind_gain -> -E_soiling
%      -> -E_dc_derate -> -E_outage -> -E_inv_loss -> E_ac_net.
%   2) Tek fazlı L1 şebeke bağlantısında aktif adımlarda (f_grid >= 49.0 Hz, P_ac > 0.05 kW)
%      efektif Thevenin şebeke direnci R_grid_est = Cov(ΔU_L1, ΔI_L1) / Var(ΔI_L1) [Ohm] hesaplanır.
%   3) Testere dişi kirlenme modelinden ekonomik optimum temizlik periyodu T* = sqrt(2*C/(r*E*p)) üretilir.
% Çıktılar: artifacts/v2/g01_losses.mat, artifacts/v2/events_catalog_v2.mat, artifacts/logs/v2_g01.log

clear;
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root);
setupGes();
cfg = gesConfig();
v2Dir = fullfile(root, "artifacts", "v2");
if ~isfolder(v2Dir), mkdir(v2Dir); end
outDir = fullfile(v2Dir, "anomaly");
if ~isfolder(outDir), mkdir(outDir); end
logDir = fullfile(root, "artifacts", "logs");
if ~isfolder(logDir), mkdir(logDir); end
logFile = fullfile(logDir, "v2_g01.log");
writelines("=== v3-G01 fiziksel enerji şelalesi ve güvenilirlik " + string(datetime("now")), logFile);
logMsg = @(m) writelines(string(m), logFile, WriteMode="append");
tStart = tic;
gamma = -0.0037;

m1File = fullfile(cfg.paths.models, cfg.files.m1);
if ~isfile(m1File)
    m1File = fullfile(cfg.paths.models, "m1_expected_power.mat");
end
bundle = load(m1File).bundle;
fps = bundle.Fingerprints;

d2File = fullfile(v2Dir, "d02_dryspells.mat");
if isfile(d2File)
    D2 = load(d2File, "days0", "SR", "ids", "R", "coplanar");
    Sd.days0 = D2.days0;
    Sd.ids = D2.ids;
    srRel = D2.SR ./ prctile(D2.SR, 90, 1);
    srRel = fillmissing(srRel, "linear", 1, MaxGap=10);
    Sd.loss = max(0, 1 - min(srRel, 1));
    Sd.loss(isnan(Sd.loss)) = 0;
else
    D2 = struct("coplanar", strings(0,1), "R", table());
    Sd = struct("days0", NaT(0,1), "ids", strings(0,1), "loss", []);
end

M = load(fullfile(cfg.paths.processed, "shared", "meteo_ref.mat")).meteoRef;
geo = ges.solar.solarGeometry(M.Time, cfg.site);

files = dir(fullfile(cfg.paths.processed, "train", "inverter", "*.mat"));
ids = erase(string({files.name})', ".mat");
n = numel(ids);
cats = ["veri boşluğu (üretim sürdü)" "gerçek kesinti (veri yok)" "şebeke/kabin olayı" "invertör durması (trip)" ...
    "ölü string" "ısıl kısma" "kırpma (DC/AC oranı)" "tozlanma" "açıklanamayan"];
L = zeros(n, numel(cats));                         % kWh
wfStages = ["E_horiz_stc" "E_poa_gain" "E_iam_loss" "E_temp_ross_loss" "E_wind_cooling_gain" ...
    "E_soiling_loss" "E_dc_derate_loss" "E_outage_loss" "E_inv_conv_loss" "E_ac_net"];
W = zeros(n, numel(wfStages));                     % 10 kademeli fiziksel şelale (kWh)
RgridEst = nan(n, 1);                              % L1 Thevenin hat direnci [Ohm]
EtaMed = nan(n, 1);                                % Medyan DC->AC dönüşüm verimi
Eact = zeros(n, 1);
Eexp = zeros(n, 1);
yearsObs = zeros(n, 1);
nStr = zeros(n, 1);
thrDays = zeros(n, 1);
evAll = cell(n, 1);

for k = 1:n
    D = load(fullfile(files(k).folder, files(k).name), "TT", "info");
    TT = D.TT;
    info = D.info;
    f = fps(fps.Id == ids(k), :);
    if isempty(f)
        fp = struct("AmPm", 1.0, "Vmean", mean(info.Vmppt), "Cabin", 1);
    else
        fp = struct("AmPm", f.AmPm(1), "Vmean", f.Vmean(1), "Cabin", f.Cabin(1));
    end
    thrFile = fullfile(v2Dir, "throttle", ids(k) + ".mat");
    if isfile(thrFile)
        Th = load(thrFile, "Throttled", "LossKw", "Ppot", "Clipping");
        TT.qThrottle = Th.Throttled;
        TT.ThrottleLossKw = double(Th.LossKw);
        ppot = double(Th.Ppot);
    else
        TT.qThrottle = false(height(TT), 1);
        TT.ThrottleLossKw = zeros(height(TT), 1);
        ppot = nan(height(TT), 1);
    end
    ex = ges.anomaly.expectedPower(bundle, TT, info, fp);
    s = ges.anomaly.detectSteps(TT, ex);

    seen = find(~isnan(TT.P_dc));
    inSpan = false(height(TT), 1);
    if ~isempty(seen)
        % SmartGridLab'da ilk 4.5 gün (27-31 Temmuz) meteo açık, evirici kapalı kesintisini de yakalamak için tüm ışınımlı dönem dahil
        inSpan(1:seen(end)) = true;
    else
        inSpan(:) = true;
    end
    lit = TT.Elevation > 5 & ex.Pdc > 0 & inSpan;
    p = max(fillmissing(TT.P_dc, "constant", 0), 0);
    pac = max(fillmissing(TT.P_ac, "constant", 0), 0);
    used = false(height(TT), 1);

    % a) veri boşlukları / kesinti
    gapL = zeros(height(TT), 2);
    miss = isnan(TT.P_dc) & lit;
    if ismember("E_life", TT.Properties.VariableNames)
        e = TT.E_life;
        if ~isnumeric(e), e = str2double(e); end
    else
        e = nan(height(TT), 1);
    end
    runs = findRuns(miss);
    for r = 1:size(runs, 1)
        a = runs(r, 1); b = runs(r, 2);
        i0 = find(~isnan(e(1:a-1)) & e(1:a-1) > 0, 1, "last");
        i1 = b + find(~isnan(e(b+1:end)) & e(b+1:end) > 0, 1, "first");
        expGap = sum(ex.PdcWork(a:b), "omitnan") * 0.25;
        produced = 0;
        if ~isempty(i0) && ~isempty(i1)
            produced = max(e(i1) - e(i0) - p(i1) * 0.25, 0);
            produced = min(produced, expGap * 1.05);
        end
        gapL(a:b, 1) = ex.PdcWork(a:b) * (produced / max(expGap, eps));
        gapL(a:b, 2) = ex.PdcWork(a:b) * (1 - produced / max(expGap, eps));
    end
    L(k, 1) = sum(gapL(:, 1), "omitnan") * 0.25;
    L(k, 2) = sum(gapL(:, 2), "omitnan") * 0.25;
    used = used | miss;
    % b) şebeke/kabin, c) trip
    m = lit & ~used & s.GridEvent;
    L(k, 3) = sum(max(ex.Pdc(m) - p(m), 0)) * 0.25;
    used = used | m;
    m = lit & ~used & s.Trip;
    L(k, 4) = sum(max(ex.Pdc(m) - p(m), 0)) * 0.25;
    used = used | m;
    % d) ölü string
    m = lit & ~used;
    L(k, 5) = sum(max(ex.Pdc(m) - ex.PdcWork(m), 0), "omitnan") * 0.25;
    % e) ısıl kısma
    L(k, 6) = sum(TT.ThrottleLossKw(m & TT.qThrottle)) * 0.25;
    % f) kırpma
    clip = m & TT.P_ac >= 0.97 * info.Rated & ~isnan(ppot);
    L(k, 7) = sum(max(ppot(clip) - p(clip), 0)) * 0.25;
    % g) tozlanma
    j = find(Sd.ids == ids(k), 1);
    dayK = dateshift(TT.Time, "start", "day");
    sl = zeros(height(TT), 1);
    if ~isempty(j) && (isempty(D2.coplanar) || ismember(ids(k), D2.coplanar))
        [tfd, ld] = ismember(dayK, Sd.days0);
        sl(tfd) = Sd.loss(ld(tfd), j);
    end
    rest = m & ~TT.qThrottle & ~clip;
    L(k, 8) = sum(p(rest) .* sl(rest) ./ max(1 - sl(rest), 0.5)) * 0.25;
    % h) açıklanamayan kalan
    resid = ex.PdcWork - p - TT.ThrottleLossKw - (p .* sl ./ max(1 - sl, 0.5)) .* rest;
    resid(clip) = 0;
    L(k, 9) = sum(max(resid(m), 0), "omitnan") * 0.25 - sum(max(-resid(m), 0), "omitnan") * 0.25;
    Eact(k) = sum(p(inSpan)) * 0.25;
    Eexp(k) = sum(ex.Pdc(lit), "omitnan") * 0.25;

    % --- 10 Kademeli Fiziksel Enerji Şelalesi (STC -> POA -> IAM -> Ross/Faiman -> DC -> AC) ---
    [~, locM] = ismember(TT.Time, M.Time);
    if ismember("G_horiz", TT.Properties.VariableNames)
        gHoriz = max(fillmissing(TT.G_horiz, "constant", 0), 0);
    else
        gHoriz = max(fillmissing(M.G_ref(max(locM, 1)), "constant", 0), 0);
    end
    geoSub = struct("Zenith", geo.Zenith(max(locM, 1)), "Azimuth", geo.Azimuth(max(locM, 1)), ...
        "GhiCs", geo.GhiCs(max(locM, 1)), "DniCs", geo.DniCs(max(locM, 1)), ...
        "DhiCs", geo.DhiCs(max(locM, 1)), "Extraterrestrial", geo.Extraterrestrial(max(locM, 1)));
    [gPoaTot, gPoaEff] = ges.solar.transposeGhiToPoa(gHoriz, geoSub, 32, 178);
    if ismember("WindSpeed", TT.Properties.VariableNames)
        wSpd = fillmissing(TT.WindSpeed, "constant", 0.7);
    else
        wSpd = repmat(0.7, height(TT), 1);
    end
    tModSat = TT.T_amb + 0.028 * gPoaTot;
    [tCellDyn, ~, fOut] = ges.solar.cellTemperatureFaiman(TT.T_amb, gPoaTot, wSpd, TmodSat=tModSat);

    capKw = info.Capacity;
    eHorizStc = sum(capKw * (gHoriz(lit) / 1000)) * 0.25;
    ePoaStc = sum(capKw * (gPoaTot(lit) / 1000)) * 0.25;
    ePoaEffStc = sum(capKw * (gPoaEff(lit) / 1000)) * 0.25;
    pStcStep = capKw * (gPoaEff(lit) / 1000);
    eTempRoss = sum(pStcStep .* abs(gamma) .* max(tModSat(lit) - 25, 0)) * 0.25;
    eWindGain = sum(pStcStep .* abs(gamma) .* max(fOut.DeltaTWind(lit), 0)) * 0.25;
    eSoiling = L(k, 8);
    eOutage = L(k, 2) + L(k, 3) + L(k, 4);
    eDcDerate = L(k, 5) + L(k, 6) + L(k, 7) + max(L(k, 9), 0);
    eInvLoss = sum(max(p(inSpan) - pac(inSpan), 0)) * 0.25;
    eAcNet = sum(pac(inSpan)) * 0.25;
    W(k, :) = [eHorizStc, ePoaStc - eHorizStc, ePoaStc - ePoaEffStc, eTempRoss, eWindGain, ...
        eSoiling, eDcDerate, eOutage, eInvLoss, eAcNet];

    % --- L1 Şebeke Thevenin Direnci (R_grid_est = Cov(dU_L1, dI_L1)/Var(dI_L1)) ve Verim ---
    okEta = p > 0.15 * capKw & pac > 0 & pac <= p * 1.02;
    if any(okEta)
        EtaMed(k) = median(pac(okEta) ./ p(okEta), "omitnan");
    end
    uCol = ""; iCol = "";
    if ismember("U_L1", TT.Properties.VariableNames), uCol = "U_L1";
    elseif ismember("U_ab", TT.Properties.VariableNames), uCol = "U_ab"; end
    if ismember("I_L1", TT.Properties.VariableNames), iCol = "I_L1";
    elseif ismember("I_a", TT.Properties.VariableNames), iCol = "I_a"; end
    if uCol ~= "" && iCol ~= "" && ismember("f_grid", TT.Properties.VariableNames)
        uL1 = double(TT.(uCol)); iL1 = double(TT.(iCol)); fg = double(TT.f_grid);
        actGrid = fg >= 49.0 & pac > 0.05 * capKw & uL1 > 190 & iL1 > 0.2;
        du = [NaN; diff(uL1)]; di = [NaN; diff(iL1)];
        pairOk = actGrid & [false; actGrid(1:end-1)] & abs(di) > 0.15 & abs(du) < 15;
        if nnz(pairOk) >= 20
            covMat = cov(di(pairOk), du(pairOk));
            RgridEst(k) = max(covMat(1, 2) / max(covMat(1, 1), eps), 0);
        end
    end

    obs = TT.Time(~isnan(TT.P_dc));
    if numel(obs) >= 2
        yearsObs(k) = max(years(obs(end) - obs(1)), 1/52);
    else
        yearsObs(k) = 1/52;
    end
    thrDays(k) = numel(unique(dateshift(TT.Time(TT.qThrottle), "start", "day")));
    nStr(k) = max(nnz(info.Installed), 1);
    ev = eventsOf(TT, ex, s, ids(k), fp.Cabin);
    evAll{k} = ev;
    Steps = timetable(TT.Time, ex.Pdc, ex.PdcWork, s.ResidualDeficit, s.DeficitLevel, TT.qThrottle, s.ThrottleDuty, ...
        VariableNames=["Pdc_exp" "PdcWork_exp" "ResidualDeficit" "DeficitLevel" "Throttle" "ThrottleDuty"]);
    save(fullfile(outDir, ids(k) + ".mat"), "Steps", "ev");
end
catalog = sortrows(vertcat(evAll{:}), "Start");
save(fullfile(v2Dir, "events_catalog_v2.mat"), "catalog");

waterfall = array2table(W, VariableNames=wfStages);
waterfall = [table(ids, RgridEst, EtaMed, VariableNames=["Id" "R_grid_Ohm" "Eta_inv_med"]), waterfall];

logMsg("");
logMsg(sprintf("FİZİKSEL ENERJİ VE KAYIP ŞELALESİ — %d invertör", n));
for sIdx = 1:numel(wfStages)
    logMsg(sprintf("  %-22s : %8.2f kWh", wfStages(sIdx), sum(W(:, sIdx))));
end
logMsg(sprintf("  Medyan Evirici Verimi  : %.2f %% | Medyan L1 Şebeke Thevenin Direnci: %.3f Ohm", ...
    100 * median(EtaMed, "omitnan"), median(RgridEst, "omitnan")));

save(fullfile(v2Dir, "g01_losses.mat"), "ids", "cats", "L", "Eact", "Eexp", "yearsObs", "nStr", ...
    "waterfall", "wfStages", "W", "RgridEst", "EtaMed");
logMsg("=== v3-G01 bitti " + string(datetime("now")) + sprintf(" (%.1f s)", toc(tStart)));

function runs = findRuns(m)
d = diff([false; m(:); false]);
runs = [find(d == 1), find(d == -1) - 1];
end

function events = eventsOf(TT, ex, s, id, cabin)
lossDeficit = max(ex.PdcWork - TT.P_dc, 0);
lossDeficit(~s.Valid) = 0;
nDead = max(sum(s.StringDead, 2), 1);
lossString = (ex.Pdc - ex.PdcWork) ./ nDead;
specs = {
    "trip",          s.Trip,               max(ex.Pdc - TT.P_dc, 0), 3, 0, s.Obs.Trip
    "grid_event",    s.GridEvent,          max(ex.Pdc - TT.P_dc, 0), 3, 0, s.Obs.GridEvent
    "string_weak",   s.StringWeak,         zeros(height(TT), 1),     1, 0, s.Obs.StringWeak
    "power_deficit", s.DeficitLevel >= 2,  lossDeficit,              2, 0, s.Obs.Deficit
    "derating",      s.Derate,             fillmissing(double(TT.ThrottleLossKw), "constant", 0), 1, 0, s.Obs.Derate
    "offline",       s.Offline,            ex.Pdc,                   1, 0, s.Obs.Offline};
for pv = 1:size(s.StringDead, 2)
    specs(end+1, :) = {"string_dead", s.StringDead(:, pv), lossString .* s.StringDead(:, pv), 2, pv, s.Obs.StringDead}; %#ok<AGROW>
end
parts = cell(size(specs, 1), 1);
for i = 1:size(specs, 1)
    ep = ges.anomaly.buildEpisodes(TT.Time, specs{i, 2}, specs{i, 3}, Observed=specs{i, 6}, MaxObservedGap=4, MaxGap=days(60));
    if height(ep) == 0, continue, end
    parts{i} = table(repmat(string(id), height(ep), 1), repmat(cabin, height(ep), 1), repmat(specs{i, 1}, height(ep), 1), ...
        repmat(specs{i, 5}, height(ep), 1), repmat(specs{i, 4}, height(ep), 1), ep.Start, ep.End, ...
        days(ep.End - ep.Start), ep.LossKwh, days(ep.End - ep.Start) >= 7, ...
        VariableNames=["Id" "Cabin" "Type" "PV" "Severity" "Start" "End" "DurationDays" "LossKwh" "Chronic"]);
end
events = vertcat(parts{:});
if isempty(events)
    events = table(strings(0, 1), zeros(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), NaT(0, 1, TimeZone=TT.Time.TimeZone), ...
        NaT(0, 1, TimeZone=TT.Time.TimeZone), zeros(0, 1), zeros(0, 1), false(0, 1), ...
        VariableNames=["Id" "Cabin" "Type" "PV" "Severity" "Start" "End" "DurationDays" "LossKwh" "Chronic"]);
end
end
