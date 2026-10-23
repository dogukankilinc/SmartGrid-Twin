function [gPoa, gPoaEff, out] = transposeGhiToPoa(gMeas, geo, tilt, surfaceAzimuth, opts)
%TRANSPOSEGHITOPOA Yatay (veya referans eğimli) ışınımı Erbs ayrıştırması + HDKR + ASHRAE IAM ile dizi düzlemine taşır.
%   [gPoa, gPoaEff, out] = ges.solar.transposeGhiToPoa(gMeas, geo, tilt, surfaceAzimuth)
%
%   SmartGridLab keşfi:
%     - Dış sensör ("System insolation on external sensor [W/m²]") yatay küresel ışınım (GHI, beta=0°) verir.
%     - Çatıdaki 1.20 kWp PV dizisi ise güneye ~32° eğimlidir (beta=32°, gamma=178°).
%     - Ham yatay G doğrudan kullanılırsa Ağustos-Ekim arasında I_dc/G oranı +%50.8 kayar ve bulutlu
%       günlerde basit açık-gök oranı %60 fazla tahmin üretir.
%
%   Yöntem (3 Adım):
%     1) Sensör eğimli ise (SensorTilt > 2°), ters izotropik/açık-gök oranı ile eşdeğer yatay GHI elde edilir.
%     2) Erbs vd. (1982) difüz kesir korelasyonu ile GHI -> (DNI_est, DHI_est) ayrıştırılır.
%     3) Hay-Davies-Klucher-Reindl (HDKR) anizotropik gökyüzü modeli + ASHRAE IAM (b0=0.05) ile
%        dizi düzlemi toplam ışınım (gPoa) ve yansıma düzeltmeli efektif ışınım (gPoaEff) hesaplanır.
arguments
    gMeas (:,1) double
    geo (1,1) struct
    tilt (1,:) double = 32
    surfaceAzimuth (1,:) double = 178
    opts.SensorTilt (1,1) double = 0
    opts.SensorAzimuth (1,1) double = 180
    opts.Albedo (1,1) double = 0.2
    opts.IamB0 (1,1) double = 0.05
end

zenith = geo.Zenith(:);
sunAz = geo.Azimuth(:);
cosZ = cosd(zenith);
lit = zenith < 87 & gMeas > 0 & ~isnan(gMeas);

if isfield(geo, "Extraterrestrial")
    i0 = geo.Extraterrestrial(:);
else
    i0 = repmat(1361, numel(zenith), 1);
end

% 1) Sensör yatay değilse önce eşdeğer GHI'ya indirge
if opts.SensorTilt > 2
    poaCsSen = ges.solar.poaIrradiance(geo.GhiCs(:), geo.DniCs(:), geo.DhiCs(:), ...
        zenith, sunAz, opts.SensorTilt, opts.SensorAzimuth, opts.Albedo);
    ratioSen = geo.GhiCs(:) ./ max(poaCsSen, 10);
    ratioSen = min(max(ratioSen, 0.5), 1.6);
    ghiEst = gMeas .* ratioSen;
else
    ghiEst = max(gMeas, 0);
end

% 2) Erbs vd. (1982) difüz ayrıştırması: Kt -> kd = DHI / GHI
kt = zeros(size(ghiEst));
kt(lit) = min(max(ghiEst(lit) ./ max(i0(lit) .* max(cosZ(lit), 0.05), 10), 0), 1.15);

kd = ones(size(kt));
m1 = lit & kt <= 0.22;
m2 = lit & kt > 0.22 & kt <= 0.80;
m3 = lit & kt > 0.80;

kd(m1) = 1.0 - 0.09 * kt(m1);
kt2 = kt(m2);
kd(m2) = 0.9511 - 0.1604 * kt2 + 4.388 * kt2.^2 - 16.638 * kt2.^3 + 12.336 * kt2.^4;
kd(m3) = 0.165;
kd = min(max(kd, 0.10), 1.0);

dhiEst = ghiEst .* kd;
dniEst = zeros(size(ghiEst));
dniEst(lit) = (ghiEst(lit) - dhiEst(lit)) ./ max(cosZ(lit), 0.06);
dniEst = min(max(dniEst, 0), 1150);

% 3) HDKR Anizotropik Transpozisyon + ASHRAE IAM
[~, details] = ges.solar.poaIrradiance(ghiEst, dniEst, dhiEst, zenith, sunAz, ...
    tilt, surfaceAzimuth, opts.Albedo, Model="hdkr", ApplyIam=false, ...
    IamB0=opts.IamB0, Extraterrestrial=i0);

gPoa = max(details.PoaTotal, 0);
gPoaEff = max(details.PoaEffective, 0);
gPoa(~lit, :) = 0;
gPoaEff(~lit, :) = 0;
gPoa(isnan(gMeas), :) = NaN;
gPoaEff(isnan(gMeas), :) = NaN;

if nargout > 2
    poaCsArr = ges.solar.poaIrradiance(geo.GhiCs(:), geo.DniCs(:), geo.DhiCs(:), ...
        zenith, sunAz, tilt, surfaceAzimuth, opts.Albedo, Model="hdkr", Extraterrestrial=i0);
    out = struct("GhiEst", ghiEst, "DniEst", dniEst, "DhiEst", dhiEst, ...
        "Kt", kt, "DiffuseFraction", kd, "PoaCs", poaCsArr, ...
        "CosAoi", details.CosAoi, "AoiDeg", details.AoiDeg, "Iam", details.Iam, ...
        "Beam", details.Beam, "SkyDiffuse", details.SkyDiffuse, "GroundReflected", details.GroundReflected);
end
end
