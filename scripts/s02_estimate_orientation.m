%% S02_ESTIMATE_ORIENTATION  Faz 1b-i: Uydu sensörü ve PV dizi geometrisini veriden kestirme.
% SmartGridLab (SmartGrid-Twin) için uyarlanmış: tek uydu sensörü (K01-METEO, beta=0° / GHI),
% tek evirici dizisi (K01-INV01, beta≈32° Güneye bakan).
%
% Adımlar:
%  1) Uydu sensörünün montaj açısını (beta_sen=0°) doğrula ve Ineichen bulanıklık kalibrasyonu yap.
%  2) Evirici dizisinin efektif eğim/azimutunu DC akım mevsimsel kaymadan kestir (fitOrientation).
%  3) Yatay GHI -> G_poa (HDKR) transpozisyon ölçek katsayısını kalibre et.
%  Çıktı: artifacts/interim/train/orientation.mat

clear;
addpath(fileparts(fileparts(mfilename("fullpath"))));
setupGes();
cfg = gesConfig();
inDir = fullfile(cfg.paths.interim, "train");

%% 1) Uydu sensörü (K01-METEO, yatay GHI)
M = load(fullfile(inDir, "meteo", "K01-METEO.mat")).TT;
M = M(M.Time < cfg.split.validationStart, :);
geo = ges.solar.solarGeometry(M.Time, cfg.site);
night = geo.Elevation < -2;

% fitOrientation: yatay sensör - beklenen beta=0 doğrulanır
rSen = ges.solar.fitOrientation(M.Time, M.G, cfg.site, ...
    TiltInit=0, AzimuthInit=180, FitMode="shape_only");
fprintf("Sensör oryantasyon kestirimi: beta=%.1f°, gamma=%.1f°, nRMSE=%.3f\n", ...
    rSen.Tilt, rSen.Azimuth, rSen.Error);

% Mevsimsel Linke bulanıklık kalibrasyonu (27-31 Temmuz warm-up penceresi)
warmStart = datetime(2026,7,27, TimeZone=cfg.data.timeZone);
warmEnd   = datetime(2026,7,31, TimeZone=cfg.data.timeZone);
warmMask  = M.Time >= warmStart & M.Time < warmEnd & ~night;
if nnz(warmMask) > 10
    tlEst = ges.solar.clearSkyIneichen(M.Time(warmMask), cfg.site, "FitTurbidity", M.G(warmMask));
    fprintf("27-31 Temmuz warm-up Linke bulanıklık kestirimi: TL=%.2f\n", tlEst);
end

sensorRows = table("K01-METEO", rSen.Tilt, rSen.Azimuth, rSen.Error, 0.0, rSen.ScaleCv, rSen.NumDays, ...
    VariableNames=["Id" "Tilt" "Azimuth" "FitError" "FitErrorHorizontal" "ScaleCv" "ClearDays"]);

%% 2) Evirici dizisi geometrisi (K01-INV01)
invFile = fullfile(inDir, "inverter", "K01-INV01.mat");
if isfile(invFile)
    TT = load(invFile).TT;
    TT = TT(TT.Time < cfg.split.validationStart, :);
    % G_poa hesapla (mevcut yatay G ile, HDKR)
    geoInv = ges.solar.solarGeometry(TT.Time, cfg.site);
    gPoa = ges.solar.transposeGhiToPoa(TT.G, geoInv.Zenith, geoInv.Azimuth, ...
        cfg.site.panelTiltDeg, cfg.site.panelAzimuthDeg, geoInv.GhiCs, geoInv.DhiCs);
    rArr = ges.solar.fitOrientation(TT.Time, TT.G, cfg.site, ...
        G_poa_meas=gPoa, I_dc_meas=TT.I_dc, C_kWp=cfg.dcCapacityKwp, ...
        TiltInit=32, AzimuthInit=180);
    fprintf("Dizi oryantasyon kestirimi: beta=%.1f°, gamma=%.1f°\n", rArr.Tilt, rArr.Azimuth);

    % AmPm oranı (sabah/öğleden sonra enerji oranı; >1 doğuya, <1 batıya)
    geoT = ges.solar.solarGeometry(TT.Time, cfg.site);
    isMorning = geoT.Azimuth < 180;
    up = geoT.Elevation > 5 & ~isnan(TT.P_ac);
    days = dateshift(TT.Time, "start", "day");
    [g, dd] = findgroups(days(up));
    amE  = splitapply(@(p,m) sum(p(m)*0.25,"omitmissing"), TT.P_ac(up), isMorning(up), g);
    pmE  = splitapply(@(p,m) sum(p(~m)*0.25,"omitmissing"), TT.P_ac(up), isMorning(up), g);
    amPm = median(amE ./ max(pmE, 0.01), "omitmissing");
    fprintf("AM/PM enerji oranı: %.3f (>1=Doğu eğimi, <1=Batı eğimi)\n", amPm);

    orientation = table("K01-INV01", rArr.Tilt, rArr.Azimuth, amPm, ...
        VariableNames=["Id" "Tilt" "Azimuth" "AmPm"]);
else
    warning("s02:noInvFile", "Evirici dosyası bulunamadı: %s — varsayılan (32°/180°) kullanılıyor", invFile);
    orientation = table("K01-INV01", cfg.site.panelTiltDeg, cfg.site.panelAzimuthDeg, 0.9, ...
        VariableNames=["Id" "Tilt" "Azimuth" "AmPm"]);
end

%% 3) GHI->G_poa ölçek kalibrasyonu (eğitim dilimi, net saatler)
if isfile(invFile)
    Mtrain = M(M.Time < cfg.split.validationStart, :);
    geoM   = ges.solar.solarGeometry(Mtrain.Time, cfg.site);
    gPoaM  = ges.solar.transposeGhiToPoa(Mtrain.G, geoM.Zenith, geoM.Azimuth, ...
        orientation.Tilt, orientation.Azimuth, geoM.GhiCs, geoM.DhiCs);
    TTt = load(invFile).TT;
    TTt = TTt(TTt.Time < cfg.split.validationStart, :);
    TTt_sync = synchronize(TTt(:,"I_dc"), Mtrain(:,"G"), geoM.Elevation, "first");
    TTt_sync.Properties.VariableNames(end) = "Elevation";
    cal = TTt_sync.Elevation > 15 & TTt_sync.G > 100 & ~isnan(TTt_sync.I_dc) & ...
          TTt_sync.G > 50;
    if nnz(cal) > 20
        ratio  = TTt_sync.I_dc(cal) ./ max(gPoaM(cal(1:height(TTt_sync))), 0.01);
        scaleGhi2Poa = median(ratio) / cfg.impNominal;
        fprintf("GHI->G_poa ölçek katsayısı: %.3f\n", scaleGhi2Poa);
    end
end

save(fullfile(inDir, "orientation.mat"), "orientation", "sensorRows");
fprintf("Oryantasyon dosyası kaydedildi: %s\n", fullfile(inDir, "orientation.mat"));
