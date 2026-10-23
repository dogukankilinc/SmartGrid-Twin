%% D01_SOILING_V2  v2/v3-D: eğim ve Faiman sıcaklığı düzeltmeli akım tabanlı tozlanma oranı (SR) ve R_iso yağış doğrulaması.
% SmartGridLab v3 Geliştirmeleri:
%   1) Yatay sensör ışınımı (G_GHI, beta=0°), Erbs + HDKR + ASHRAE IAM ile dizi düzlemine (beta≈32°) taşınır.
%   2) Akım indeksi dinamik Faiman hücre sıcaklığı (T_cell_dyn) ile düzeltilir.
%   3) Temizlenme olayları kabin/evirici SR sıçraması + kapalı gök (Kd < 0.45) + düşük yalıtım direnci
%      (R_iso < 1500 kOhm, ıslak modül yüzeyi kanıtı!) ile "RainCleaning_RisoVerified" olarak doğrulanır.
% Çıktı: artifacts/v2/d01_soiling.mat, artifacts/logs/v2_d01.log

clear;
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root);
setupGes();
cfg = gesConfig();
outDir = fullfile(root, "artifacts", "v2");
if ~isfolder(outDir), mkdir(outDir); end
logDir = fullfile(root, "artifacts", "logs");
if ~isfolder(logDir), mkdir(logDir); end
logFile = fullfile(logDir, "v2_d01.log");
writelines("=== v3-D01 tozlanma ve R_iso yağış doğrulaması " + string(datetime("now")), logFile);
logMsg = @(m) writelines(string(m), logFile, WriteMode="append");
tStart = tic;
cabinJump = 0.015;
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

dayAll = dateshift(M.Time, "start", "day");
[gd, days0] = findgroups(dayAll);
lit = M.Elevation > 5 & ~isnan(M.G_ref);
Kd = accumarray(gd(lit), M.G_ref(lit), [numel(days0) 1]) ./ max(accumarray(gd(lit), M.PoaCsRef(lit), [numel(days0) 1]), 1);
noonZen = accumarray(gd, geo.Zenith, [numel(days0) 1], @min);

files = dir(fullfile(cfg.paths.processed, "train", "inverter", "*.mat"));
ids = erase(string({files.name})', ".mat");
n = numel(ids);
nd = numel(days0);
CI = nan(nd, n);
Eday = zeros(nd, n);
RisoDayMin = nan(nd, n);
cabin = ones(n, 1);
hasSig = false(n, 1);
for k = 1:n
    D = load(fullfile(files(k).folder, files(k).name), "TT", "info");
    TT = D.TT;
    info = D.info;
    if ~isempty(O) && any(O.Id == ids(k))
        o = O(O.Id == ids(k), :);
        arrTilt = o.Tilt(1); arrAz = o.Azimuth(1); cabin(k) = o.Cabin(1);
    else
        arrTilt = 32; arrAz = 178; cabin(k) = 1;
    end
    [tf, loc] = ismember(TT.Time, M.Time);
    if ~all(tf)
        error("Zaman ızgarası uyuşmuyor: %s", ids(k));
    end
    if ismember("G_poa_eff", TT.Properties.VariableNames)
        gArr = TT.G_poa_eff;
    elseif ismember("G_poa", TT.Properties.VariableNames)
        gArr = TT.G_poa;
    else
        geoSub = struct("Zenith", geo.Zenith(loc), "Azimuth", geo.Azimuth(loc), ...
            "GhiCs", geo.GhiCs(loc), "DniCs", geo.DniCs(loc), "DhiCs", geo.DhiCs(loc), ...
            "Extraterrestrial", geo.Extraterrestrial(loc));
        [~, gArr] = ges.solar.transposeGhiToPoa(TT.G_ref, geoSub, arrTilt, arrAz, ...
            SensorTilt=sensor.Tilt, SensorAzimuth=sensor.Azimuth);
    end
    thrFile = fullfile(outDir, "throttle", ids(k) + ".mat");
    if isfile(thrFile)
        Th = load(thrFile, "Throttled", "Clipping");
        notThr = ~Th.Throttled & ~Th.Clipping;
        hasSig(k) = true;
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
    sel = TT.Kc >= 0.80 & TT.Kc <= 1.15 & TT.KcVar < 0.05 & TT.Elevation > 25 & hr >= 10 & hr <= 16 ...
        & TT.qOnGrid & ~TT.qFault & ~TT.qCabinEvent & primaryOk & notThr ...
        & TT.P_dc > 0.1 * info.Rated & gArr > 300;

    if ismember("I_dc", TT.Properties.VariableNames) && ~all(isnan(TT.I_dc))
        iMed = TT.I_dc;
        iMed(iMed <= 0.05) = NaN;
        nLive = double(~isnan(iMed)) * 3;
    else
        dead = false(height(TT), 8);
        for b = 1:8
            dead(:, b) = bitget(uint8(TT.DeadMask), b) == 1;
        end
        I = nan(height(TT), 8);
        for s = 1:8
            if info.Installed(s) && ismember("I_pv" + s, TT.Properties.VariableNames)
                I(:, s) = TT.("I_pv" + s);
            end
        end
        I(dead | I <= 0.1) = NaN;
        nLive = sum(~isnan(I), 2);
        iMed = median(I, 2, "omitnan");
    end
    if ismember("T_cell_faiman", TT.Properties.VariableNames)
        tCell = TT.T_cell_faiman;
    else
        tCell = TT.T_mod;
    end
    iMedCorr = iMed ./ (1 + 0.0005 * (fillmissing(tCell, "constant", 25) - 25));
    idx = iMedCorr ./ (gArr / 1000);
    idx(~sel | nLive < min(3, sum(info.Installed))) = NaN;
    g = gd(loc);
    CI(:, k) = accumarray(g, idx, [nd 1], @(x) medianOrNaN(x, 6), NaN);
    Eday(:, k) = accumarray(g, max(fillmissing(TT.P_dc, "constant", 0), 0) * 0.25, [nd 1]);
    if ismember("R_iso", TT.Properties.VariableNames)
        RisoDayMin(:, k) = accumarray(g, TT.R_iso, [nd 1], @(x) minOrNaN(x), NaN);
    end
end
SR = CI ./ prctile(CI, 95, 1);
logMsg(sprintf("Günlük indeksi olan invertör-gün: %d (%.1f %% gün kapsamı)", nnz(~isnan(SR)), 100 * mean(~isnan(SR), "all")));

%% Temizlenme olayları (kabin / evirici + R_iso yüzey ıslaklığı doğrulaması)
cleanings = table();
cabins = unique(cabin)';
for c = cabins
    subSr = SR(:, cabin == c);
    cm = median(subSr, 2, "omitmissing");
    minReq = min(4, size(subSr, 2));
    cm(sum(~isnan(subSr), 2) < minReq) = NaN;
    risoCab = median(RisoDayMin(:, cabin == c), 2, "omitmissing");
    jump = stepJump(cm, 3);
    v = cm(~isnan(cm));
    if numel(v) >= 6
        noise = 1.4826 * median(abs(diff(v) - median(diff(v))));
        thr = max(cabinJump, 2.5 * noise);
    else
        noise = 0.005;
        thr = cabinJump;
    end
    logMsg(sprintf("  Kabin %d: günlük SR gürültüsü %.4f → temizlenme eşiği %.3f", c, noise, thr));
    isPeak = (jump >= thr & jump == movmax(jump, [3 3], "omitmissing")) | ...
             (jump >= 0.75 * thr & Kd < 0.45 & risoCab < 1500 & jump == movmax(jump, [2 2], "omitmissing"));
    for d = find(isPeak)'
        winIdx = max(1, d - 3):d;
        prevOvercast = any(Kd(winIdx) < 0.45);
        wetSurface = any(risoCab(winIdx) < 1500);
        after = cm(d:min(nd, d + 6));
        cleanings = [cleanings; table(c, days0(d), jump(d), prevOvercast, wetSurface, median(after, "omitmissing"), noonZen(d), ...
            VariableNames=["Cabin" "Day" "Jump" "AfterOvercast" "RisoWetVerified" "PostLevel" "NoonZenith"])]; %#ok<AGROW>
    end
end
logMsg(sprintf("Temizlenme olayı: %d (kapalı hava sonrası %d, R_iso ıslak yüzey doğrulamalı %d)", height(cleanings), ...
    nnz(cleanings.AfterOvercast), nnz(cleanings.RisoWetVerified)));

%% SRR: kirlenme hızı ve kayıp
loss = zeros(nd, n);
rate = zeros(nd, n);
intervals = table();
for k = 1:n
    cd = cleanings.Day(cleanings.Cabin == cabin(k));
    [loss(:, k), rate(:, k), iv] = ges.soiling.soilingIntervals(days0, SR(:, k), cd, ...
        Kd=Kd, RisoMin=RisoDayMin(:, k), DailyEnergyKwh=median(Eday(Eday(:,k)>0, k), "omitnan"));
    iv.Id = repmat(ids(k), height(iv), 1);
    iv.Cabin = repmat(cabin(k), height(iv), 1);
    intervals = [intervals; iv]; %#ok<AGROW>
end
lossKwh = Eday .* loss ./ max(1 - loss, 0.5);
act = intervals(intervals.RatePerDay > 0 & intervals.ValidDays >= 4, :);
if ~isempty(act)
    logMsg(sprintf("Kirlenme hızı (aktif aralıklar, n=%d): medyan %.3f %%/gün, IQR %.3f–%.3f", height(act), ...
        100 * median(act.RatePerDay), 100 * prctile(act.RatePerDay, 25), 100 * prctile(act.RatePerDay, 75)));
end
logMsg(sprintf("TOPLAM tozlanma enerji kaybı: %.2f kWh = DC üretimin %.2f %% (ortalama günlük kayıp %.2f %%)", ...
    sum(lossKwh, "all"), 100 * sum(lossKwh, "all") / max(sum(Eday, "all"), eps), 100 * mean(loss, "all")));

save(fullfile(outDir, "d01_soiling.mat"), "days0", "ids", "cabin", "CI", "SR", "loss", "rate", ...
    "lossKwh", "Eday", "RisoDayMin", "cleanings", "intervals", "Kd", "hasSig");
logMsg("=== v3-D01 bitti " + string(datetime("now")) + sprintf(" (%.1f s)", toc(tStart)));

function m = medianOrNaN(x, nMin)
x = x(~isnan(x));
if numel(x) < nMin, m = NaN; else, m = median(x); end
end

function m = minOrNaN(x)
x = x(~isnan(x) & x > 0);
if isempty(x), m = NaN; else, m = min(x); end
end

function jump = stepJump(x, w)
n = numel(x);
jump = nan(n, 1);
valid = find(~isnan(x));
for d = 1:n
    before = valid(valid < d);
    after = valid(valid >= d);
    if numel(before) >= w && numel(after) >= w
        jump(d) = median(x(after(1:w))) - median(x(before(end - w + 1:end)));
    end
end
end
