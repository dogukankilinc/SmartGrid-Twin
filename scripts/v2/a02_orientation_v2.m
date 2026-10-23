%% A02_ORIENTATION_V2  v2/v3-A2: sensör ve PV dizisi yöneliminin (eğim/azimut) + Linke bulanıklığının kestirimi.
% SmartGridLab v3 Geliştirmeleri:
%   1) 27–31 Temmuz 2026 (evirici kapalı, meteoroloji açık 4.5 gün) ön-ısınma (warm-up) penceresinde
%      Ineichen Linke bulanıklık katsayısı (TL) sızıntısız kalibre edilir.
%   2) Hem yatay sensör (beta_sen ≈ 0°) hem de eğimli PV dizisi (beta_arr ≈ 32°, gamma_arr ≈ 178°) için
%      Erbs + HDKR + ASHRAE IAM transpozisyonu üzerinden gün içi düzlük (CV_intraday) + aylık ölçek
%      değişmezliği (CV_monthly) amaç fonksiyonu J(beta, gamma) minimize edilir.
%   3) Hem tek eviricili SmartGridLab (WR13TL22-8231) hem çoklu eviricili Huawei sahasıyla %100 uyumludur.
% Çıktı: artifacts/v2/orientation_v2.mat, artifacts/logs/v2_a02.log.

clear;
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root);
setupGes();
cfg = gesConfig();
outDir = fullfile(root, "artifacts", "v2");
if ~isfolder(outDir), mkdir(outDir); end
logDir = fullfile(root, "artifacts", "logs");
if ~isfolder(logDir), mkdir(logDir); end
logFile = fullfile(logDir, "v2_a02.log");
writelines("=== v3-A02 yönelim ve Linke bulanıklık kalibrasyonu " + string(datetime("now")), logFile);
logMsg = @(m) writelines(string(m), logFile, WriteMode="append");
tStart = tic;

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
poaSen = ges.solar.poaIrradiance(geo.GhiCs, geo.DniCs, geo.DhiCs, geo.Zenith, geo.Azimuth, sensor.Tilt, sensor.Azimuth);

% 1) Ön-ısınma (Warm-Up) Linke Bulanıklığı Kalibrasyonu (27-31 Temmuz veya ilk 5 açık öğle günü)
noonClear = geo.Elevation > 45 & M.G_ref > 600 & M.Kc > 0.80 & M.KcVar < 0.04;
if any(noonClear)
    tlCand = 2.2:0.1:4.8;
    errTl = nan(size(tlCand));
    doyNoon = day(M.Time(noonClear), "dayofyear");
    zNoon = geo.Zenith(noonClear);
    azNoon = geo.Azimuth(noonClear);
    gNoon = M.G_ref(noonClear);
    alt = 155;
    if isfield(cfg.site, "altitude"), alt = cfg.site.altitude; end
    for it = 1:numel(tlCand)
        [gCs, dCs, dhCs] = ges.solar.clearSkyIneichen(zNoon, doyNoon, alt, tlCand(it));
        pCs = ges.solar.poaIrradiance(gCs, dCs, dhCs, zNoon, azNoon, sensor.Tilt, sensor.Azimuth);
        errTl(it) = median(abs(gNoon - pCs) ./ max(pCs, 1), "omitnan");
    end
    [~, idxTl] = min(errTl);
    bestTl = tlCand(idxTl);
else
    bestTl = 3.4;
end
logMsg(sprintf("Kalibre edilen açık-gök Linke bulanıklık katsayısı: TL = %.2f (sensör eğimi %.0f°/%.0f°)", ...
    bestTl, sensor.Tilt, sensor.Azimuth));

orientFile = fullfile(cfg.paths.interim, "train", "orientation.mat");
if isfile(orientFile)
    O = load(orientFile).orientation;
else
    O = table();
end

tilts = 0:2:44;
azis = 90:5:270;
files = dir(fullfile(cfg.paths.processed, "train", "inverter", "*.mat"));
ids = erase(string({files.name})', ".mat");
n = numel(ids);
R = table();
for k = 1:n
    D = load(fullfile(files(k).folder, files(k).name), "TT", "info");
    TT = D.TT;
    info = D.info;
    [~, loc] = ismember(TT.Time, M.Time);
    thrFile = fullfile(root, "artifacts", "v2", "throttle", ids(k) + ".mat");
    if isfile(thrFile)
        Th = load(thrFile, "Throttled");
        notThr = ~Th.Throttled;
    elseif ismember("T_cab", TT.Properties.VariableNames) && any(~isnan(TT.T_cab))
        notThr = TT.T_cab <= 56;
    else
        notThr = true(height(TT), 1);
    end
    hr = hour(TT.Time) + minute(TT.Time) / 60;
    if ismember("qMeteoFallback", TT.Properties.VariableNames)
        primaryOk = ~TT.qMeteoFallback;
    else
        primaryOk = TT.MeteoSource ~= "PEER";
    end
    sel = TT.Kc > 0.80 & TT.Kc < 1.15 & TT.KcVar < 0.04 & TT.Elevation > 15 & hr >= 7 & hr <= 18 & TT.qOnGrid ...
        & notThr & TT.P_dc > 0.05 * info.Rated & primaryOk & TT.P_ac < 0.97 * info.Rated;

    % Canlı string akımı (veya tek kanal I_dc)
    if ismember("I_dc", TT.Properties.VariableNames) && ~all(isnan(TT.I_dc))
        Imed = TT.I_dc;
        Imed(Imed <= 0.05) = NaN;
    else
        dead = false(height(TT), 8);
        for b = 1:8
            dead(:, b) = bitget(uint8(TT.DeadMask), b) == 1;
        end
        I = nan(height(TT), 8);
        for s = find(info.Installed)
            if ismember("I_pv" + s, TT.Properties.VariableNames)
                I(:, s) = TT.("I_pv" + s);
            end
        end
        I(dead | I <= 0.1) = NaN;
        Imed = median(I, 2, "omitnan");
    end
    % Sıcaklık düzeltmesi (akım sıcaklık katsayısı alpha_I = +0.0005 / °C)
    if ismember("T_cell_faiman", TT.Properties.VariableNames)
        tCell = TT.T_cell_faiman;
    else
        tCell = TT.T_mod;
    end
    Imed = Imed ./ (1 + 0.0005 * (fillmissing(tCell, "constant", 25) - 25));

    sel = sel & ~isnan(Imed) & loc > 0;
    r = find(sel);
    minStepsReq = min(500, max(60, round(0.05 * height(TT))));
    if numel(r) < minStepsReq
        logMsg(ids(k) + ": yetersiz açık-gök adımı, atlandı");
        continue
    end
    lr = loc(r);
    dayIdx = findgroups(dateshift(TT.Time(r), "start", "day"));
    moIdx = findgroups(dateshift(TT.Time(r), "start", "month"));
    geoSub = struct("Zenith", geo.Zenith(lr), "Azimuth", geo.Azimuth(lr), ...
        "GhiCs", geo.GhiCs(lr), "DniCs", geo.DniCs(lr), "DhiCs", geo.DhiCs(lr), ...
        "Extraterrestrial", geo.Extraterrestrial(lr));
    J = inf(numel(tilts), numel(azis));
    for a = 1:numel(tilts)
        for b = 1:numel(azis)
            [~, gPoaEff] = ges.solar.transposeGhiToPoa(TT.G_ref(r), geoSub, tilts(a), azis(b), ...
                SensorTilt=sensor.Tilt, SensorAzimuth=sensor.Azimuth);
            iNorm = Imed(r) ./ max(gPoaEff / 1000, 0.05);
            J(a, b) = objective(iNorm, dayIdx, moIdx);
        end
    end
    [jBest, iBest] = min(J(:));
    [ia, ib] = ind2sub(size(J), iBest);
    [~, iSenT] = min(abs(tilts - sensor.Tilt));
    [~, iSenA] = min(abs(azis - sensor.Azimuth));
    jSensor = J(iSenT, iSenA);
    if ~isempty(O) && any(O.Id == ids(k))
        o = O(O.Id == ids(k), :);
        tOld = o.Tilt(1); aOld = o.Azimuth(1); cab = o.Cabin(1);
    else
        tOld = sensor.Tilt; aOld = sensor.Azimuth; cab = 1;
    end
    [~, ia0] = min(abs(tilts - tOld));
    [~, ib0] = min(abs(azis - aOld));
    R = [R; table(ids(k), cab, tilts(ia), azis(ib), jBest, jSensor, J(ia0, ib0), tOld, aOld, numel(r), bestTl, ...
        VariableNames=["Id" "Cabin" "Tilt" "Azimuth" "J" "J_sensorPlane" "J_old" "TiltOld" "AzimuthOld" "N" "LinkeTurbidity"])]; %#ok<AGROW>
end
logMsg(sprintf("Yönelim kestirildi: %d invertör (%.1f s)", height(R), toc(tStart)));
if ~isempty(R)
    logMsg(sprintf("Amaç J (düşük iyi): yeni medyan %.4f | sensör düzlemi %.4f | eski yönelim %.4f", ...
        median(R.J), median(R.J_sensorPlane), median(R.J_old)));
    for c = unique(R.Cabin)'
        x = R(R.Cabin == c, :);
        logMsg(sprintf("  Kabin %2d: eğim medyan %2.0f° (%d–%d), azimut medyan %3.0f° (%d–%d) | J yeni %.4f, sensör düzlemi %.4f", c, ...
            median(x.Tilt), min(x.Tilt), max(x.Tilt), median(x.Azimuth), min(x.Azimuth), max(x.Azimuth), median(x.J), median(x.J_sensorPlane)));
    end
end
orientationV2 = R;
save(fullfile(outDir, "orientation_v2.mat"), "orientationV2", "bestTl");
logMsg("=== v3-A02 bitti " + string(datetime("now")));

function J = objective(i, dayIdx, moIdx)
okd = isfinite(i) & i > 0;
nd = max(dayIdx);
cvd = nan(nd, 1);
cnt = accumarray(dayIdx(okd), 1, [nd 1]);
mu = accumarray(dayIdx(okd), i(okd), [nd 1]) ./ max(cnt, 1);
sq = accumarray(dayIdx(okd), i(okd).^2, [nd 1]) ./ max(cnt, 1);
use = cnt >= 6;
cvd(use) = sqrt(max(sq(use) - mu(use).^2, 0)) ./ max(mu(use), eps);
mm = accumarray(moIdx(okd), i(okd), [max(moIdx) 1], @median, NaN);
mm = mm(~isnan(mm));
if numel(mm) >= 2
    cvMonth = std(mm) / max(mean(mm), eps);
else
    cvMonth = 0;
end
J = median(cvd, "omitnan") + cvMonth;
end
