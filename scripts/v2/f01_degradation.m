%% F01_DEGRADATION  v2/v3-F: çoklu zaman ölçekli yaşlanma (YoY RdTools + Kısa Dönem STC Kararlılık Analizi).
% SmartGridLab v3 Geliştirmeleri:
%   1) Veri süresi >= 365 gün ise klasik RdTools YoY (PI(d)/PI(d-365) - 1) + Bootstrap GA çalışır.
%   2) Veri süresi < 365 gün ise (ör. 11 haftalık SmartGridLab), eğim (G_poa_eff), dinamik Faiman hücre
%      sıcaklığı (T_cell_dyn) ve tozlanma oranı (SR_d) ile tam düzeltilmiş Normalize STC Performans İndeksi
%      PI_STC_corr(d) üzerinde Blok-Bootstrap Theil-Sen (BlockSize=3) eğimi hesaplanarak
%      "Kısa Dönem Kararlılık / Erken Yaşlanma Üst Sınırı" raporlanır.
% Çıktı: artifacts/v2/f01_degradation.mat, artifacts/logs/v2_f01.log

clear;
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root);
setupGes();
cfg = gesConfig();
rng(7);
outDir = fullfile(root, "artifacts", "v2");
if ~isfolder(outDir), mkdir(outDir); end
logDir = fullfile(root, "artifacts", "logs");
if ~isfolder(logDir), mkdir(logDir); end
logFile = fullfile(logDir, "v2_f01.log");
writelines("=== v3-F01 çoklu ölçekli degradasyon ve STC kararlılık analizi " + string(datetime("now")), logFile);
logMsg = @(m) writelines(string(m), logFile, WriteMode="append");
tStart = tic;
gamma = -0.0037;
hotFallback = 56;

M = load(fullfile(cfg.paths.processed, "shared", "meteo_ref.mat")).meteoRef;
ud = M.Properties.UserData;
if isfield(ud, "SensorK02")
    sensor = ud.SensorK02;
elseif isfield(ud, "Sensor")
    sensor = ud.Sensor;
else
    sensor = struct("Tilt", 0, "Azimuth", 180);
end
geo = ges.solar.solarGeometry(M.Time, cfg.site);
ovFile = fullfile(outDir, "orientation_v2.mat");
if isfile(ovFile)
    O = load(ovFile).orientationV2;
else
    O = table();
end
d2File = fullfile(outDir, "d02_dryspells.mat");
if isfile(d2File)
    Sd = load(d2File, "days0", "SR", "ids", "coplanar");
    Sd.SR = Sd.SR ./ prctile(Sd.SR, 90, 1);
else
    Sd = struct("days0", NaT(0,1), "SR", [], "ids", strings(0,1), "coplanar", strings(0,1));
end

day = dateshift(M.Time, "start", "day");
[gd, days0] = findgroups(day);
nd = numel(days0);

clearNoon = M.Kc > 0.85 & M.Kc < 1.15 & M.KcVar < 0.04 & M.Elevation > 35;
kdc = accumarray(gd(clearNoon), M.G_ref(clearNoon) ./ M.PoaCsRef(clearNoon), [nd 1], @median, NaN);
sensorYoY = yoy(days0, kdc);

files = dir(fullfile(cfg.paths.processed, "train", "inverter", "*.mat"));
ids = erase(string({files.name})', ".mat");
n = numel(ids);
RdS = nan(n, 1); RdC = nan(n, 1); nPairs = zeros(n, 1);
ShortTermSlopeYr = nan(n, 1); ShortTermCiYr = nan(n, 2);
strRows = table();
for k = 1:n
    D = load(fullfile(files(k).folder, files(k).name), "TT", "info");
    TT = D.TT;
    info = D.info;
    if ~isempty(O) && any(O.Id == ids(k))
        o = O(O.Id == ids(k), :);
        arrTilt = o.Tilt(1); arrAz = o.Azimuth(1);
    else
        arrTilt = 32; arrAz = 178;
    end
    [~, loc] = ismember(TT.Time, M.Time);
    geoSub = struct("Zenith", geo.Zenith(loc), "Azimuth", geo.Azimuth(loc), ...
        "GhiCs", geo.GhiCs(loc), "DniCs", geo.DniCs(loc), "DhiCs", geo.DhiCs(loc), ...
        "Extraterrestrial", geo.Extraterrestrial(loc));
    [~, gArr, poaOut] = ges.solar.transposeGhiToPoa(TT.G_ref, geoSub, arrTilt, arrAz, ...
        SensorTilt=sensor.Tilt, SensorAzimuth=sensor.Azimuth);
    poaArr = poaOut.PoaCs;

    thrFile = fullfile(outDir, "throttle", ids(k) + ".mat");
    if isfile(thrFile)
        Th = load(thrFile, "Throttled", "Clipping");
        notThr = ~Th.Throttled & ~Th.Clipping;
    elseif ismember("T_cab", TT.Properties.VariableNames) && any(~isnan(TT.T_cab))
        notThr = TT.T_cab <= hotFallback & TT.P_ac < 0.97 * info.Rated;
    else
        notThr = TT.P_ac < 0.97 * info.Rated;
    end
    hr = hour(TT.Time) + minute(TT.Time) / 60;
    if ismember("qMeteoFallback", TT.Properties.VariableNames)
        primaryOk = ~TT.qMeteoFallback;
    else
        primaryOk = TT.MeteoSource ~= "PEER";
    end
    sel = TT.Kc >= 0.85 & TT.Kc <= 1.15 & TT.KcVar < 0.04 & TT.Elevation > 25 & hr >= 10 & hr <= 16 & TT.qOnGrid ...
        & ~TT.qFault & ~TT.qCabinEvent & primaryOk & notThr & TT.P_dc > 0.1 * info.Rated & gArr > 300;

    if numel(info.Vmppt) == 4 && numel(info.Installed) == 8
        mpptOf = [1 1 2 2 3 3 4 4];
        vS = info.Vmppt(mpptOf);
        dead = false(height(TT), 8);
        for b = 1:8
            dead(:, b) = bitget(uint8(TT.DeadMask), b) == 1;
        end
        fLive = ((info.Installed & ~dead) * vS') / max(sum(info.Installed .* vS), eps);
    else
        fLive = ones(height(TT), 1);
    end
    if ismember("T_cell_faiman", TT.Properties.VariableNames)
        tCell = TT.T_cell_faiman;
    else
        tCell = TT.T_mod;
    end
    tf = 1 + gamma * (tCell - 25);
    piS = TT.P_dc ./ (fLive .* (gArr / 1000) .* tf * info.Capacity);
    piC = TT.P_dc ./ (fLive .* (poaArr / 1000) .* tf * info.Capacity);
    piS(~sel | fLive < 0.5) = NaN;
    piC(~sel | fLive < 0.5) = NaN;
    g = gd(loc);
    PIs = accumarray(g, piS, [nd 1], @(x) medianOrNaN(x, 6), NaN);
    PIc = accumarray(g, piC, [nd 1], @(x) medianOrNaN(x, 6), NaN);

    % Tozlanma düzeltmesi
    j = find(Sd.ids == ids(k), 1);
    sr = nan(nd, 1);
    if ~isempty(j)
        [tfd, ld] = ismember(days0, Sd.days0);
        sr(tfd) = Sd.SR(ld(tfd), j);
    end
    sr = fillmissing(min(sr, 1), "linear", MaxGap=10);
    sr(isnan(sr)) = 1;
    PIs = PIs ./ sr;
    PIc = PIc ./ sr;
    PIs(sr < 0.92) = NaN;
    PIc(sr < 0.92) = NaN;

    rs = yoy(days0, PIs);
    rc = yoy(days0, PIc);
    nPairs(k) = nnz(~isnan(rs));
    if nPairs(k) >= 20
        RdS(k) = median(rs, "omitnan");
        RdC(k) = median(rc, "omitnan");
    end

    % Kısa dönem (<365 gün) STC kararlılık eğimi (Blok-Bootstrap Theil-Sen, yıllıklandırılmış)
    okStc = ~isnan(PIs);
    if nnz(okStc) >= 10
        xDays = days(days0(okStc) - days0(find(okStc, 1)));
        [aStc, bStc, ciStc] = ges.stats.theilSen(xDays, PIs(okStc), BlockSize=3, NumBootstrap=400);
        ShortTermSlopeYr(k) = (bStc * 365.25) / max(aStc, eps);
        ShortTermCiYr(k, :) = (ciStc * 365.25) / max(aStc, eps);
    end
end

ok = ~isnan(RdS);
if any(ok)
    logMsg(sprintf("YoY hesaplanabilen invertör: %d/%d (medyan %.0f çift)", nnz(ok), n, median(nPairs(ok))));
    bS = bootstrp(min(2000, max(100, nnz(ok)*20)), @median, RdS(ok));
    bC = bootstrp(min(2000, max(100, nnz(ok)*20)), @median, RdC(ok));
    logMsg(sprintf("FİLO YoY degradasyon hızı (sensör): medyan %+.2f %%/yıl [%%95 GA %+.2f, %+.2f]", ...
        100 * median(RdS(ok)), 100 * prctile(bS, 2.5), 100 * prctile(bS, 97.5)));
else
    bS = []; bC = [];
    logMsg("YoY çifti (<365 gün veri) bulunmadı → Kısa Dönem STC Kararlılık Modu aktif:");
    for k = 1:n
        if ~isnan(ShortTermSlopeYr(k))
            logMsg(sprintf("  %s: Eğim+IAM+Faiman+SR düzeltmeli STC kararlılık eğimi = %+.2f %%/yıl [%%95 Blok-GA %+.2f, %+.2f]", ...
                ids(k), 100 * ShortTermSlopeYr(k), 100 * ShortTermCiYr(k, 1), 100 * ShortTermCiYr(k, 2)));
        end
    end
end

save(fullfile(outDir, "f01_degradation.mat"), "ids", "RdS", "RdC", "nPairs", "bS", "bC", ...
    "ShortTermSlopeYr", "ShortTermCiYr", "strRows", "sensorYoY", "days0");
logMsg("=== v3-F01 bitti " + string(datetime("now")) + sprintf(" (%.1f s)", toc(tStart)));

function r = yoy(days, x)
r = nan(numel(days), 1);
[tf, loc] = ismember(days - caldays(365), days);
ok = tf & ~isnan(x);
ok(ok) = ~isnan(x(loc(ok)));
r(ok) = x(ok) ./ x(loc(ok)) - 1;
end

function m = medianOrNaN(x, nMin)
x = x(~isnan(x));
if numel(x) < nMin, m = NaN; else, m = median(x); end
end
