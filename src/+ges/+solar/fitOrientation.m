function res = fitOrientation(t, y, site, opts)
%FITORIENTATION Bir ışınım sensörünün veya PV dizisinin efektif eğim/azimutunu veriden kestirir.
%   res = ges.solar.fitOrientation(t, y, site) açık (pürüzsüz) günlerde
%   ölçülen y eğrisinin şeklini, her aday (eğim, azimut) için açık gökyüzü
%   panel-düzlemi ışınımıyla karşılaştırır.
%
%   v3 Geliştirmesi (SmartGridLab & a02_orientation_v2 birleşimi):
%   - G_meas (yatay/referans sensör ışınımı) verilirse: aday (eğim, azimut) için
%     y / G_poa(eğim, azimut) oranının gün içi değişim katsayısı (CV_intraday) ve
%     aylık medyanlarının değişim katsayısı (CV_monthly) birlikte minimize edilir (J amacı).
%     Böylece Ağustos-Ekim arasındaki +%50.8 eğim farkı (beta=32° vs beta=0°) yakalanır!
%   - G_meas verilmezse: açık gökyüzü şekil nRMSE + mevsimsel ölçek tutarlılığı kullanılır.
%
%   res alanları: Tilt, Azimuth, Error, ErrorHorizontal, ScaleCv,
%   ScaleCvHorizontal, Scale, NumDays, ErrorSurface (eğim × azimut), Tilts, Azimuths, ObjectiveJ.
arguments
    t datetime
    y double
    site (1,1) struct
    opts.Tilts (1,:) double = 0:2:60
    opts.Azimuths (1,:) double = 90:5:270
    opts.MaxZenith (1,1) double = 80
    opts.ClearDayPercentile (1,1) double = 20
    opts.MinPeakFraction (1,1) double = 0.55
    opts.LinkeTurbidity double = 3.5
    opts.FitMask logical = true          % false olan noktalar (ör. clipping) fitte kullanılmaz
    opts.Gmeas (:,1) double = []         % verilirse y / G_poa düzlüğü + mevsimsel değişmezlik kullanılır
    opts.SensorTilt (1,1) double = 0
    opts.SensorAzimuth (1,1) double = 180
    opts.SeasonalWeight (1,1) double = 0.5
end

t = t(:);
y = y(:);
fitMask = opts.FitMask(:) & true(size(y));
geo = ges.solar.solarGeometry(t, site, LinkeTurbidity=opts.LinkeTurbidity);
day = dateshift(t, "start", "day");
use = geo.Zenith < opts.MaxZenith;

% --- Açık gün seçimi
[gDay, days] = findgroups(day(use));
yu = y(use);
nExpected = splitapply(@numel, yu, gDay);
nValid = splitapply(@(v) nnz(~isnan(v)), yu, gDay);
peak = splitapply(@(v) max(v, [], "omitmissing"), yu, gDay);
rough = splitapply(@(v) sum(abs(diff(fillmissing(v, "linear"), 2)), "omitmissing"), yu, gDay) ./ max(peak, eps);
uMonths = unique(month(days));
monthPeak = groupsummary(peak, month(days), @(v) prctile(v, 95));
[~, mIdx] = ismember(month(days), uMonths);
candidate = nValid >= 0.75 * max(nExpected) & peak >= opts.MinPeakFraction * monthPeak(mIdx);
if nnz(candidate) < 3
    candidate = nValid >= 12 & peak > 0;
end
pct = opts.ClearDayPercentile;
isClear = candidate & rough <= prctile(rough(candidate), max(pct, min(100, 500 / max(nnz(candidate), 1))));
if nnz(isClear) < 3
    isClear = candidate;
end
sel = use & ismember(day, days(isClear)) & ~isnan(y) & y > 0 & fitMask;

% --- Aday ızgarası (eğim 0'da azimut anlamsız, tek aday yeterli)
[tt, aa] = ndgrid(opts.Tilts, opts.Azimuths);
cand = unique([tt(:) aa(:) .* (tt(:) > 0) + 180 * (tt(:) == 0)], "rows");
poa = ges.solar.poaIrradiance(geo.GhiCs(sel), geo.DniCs(sel), geo.DhiCs(sel), ...
    geo.Zenith(sel), geo.Azimuth(sel), cand(:,1)', cand(:,2)');

% --- Gün bazında kapalı form en küçük kareler + mevsimsel ölçek tutarlılığı
[gSel, selDays] = findgroups(day(sel));
A = sparse(gSel, 1:numel(gSel), 1);
ys = y(sel);
n = full(sum(A, 2));
sy = A * ys;
syy = A * ys.^2;
sym = A * (ys .* poa);
smm = max(A * poa.^2, eps);
scale = sym ./ smm;
sse = max(syy - sym.^2 ./ smm, 0);
nrmse = sqrt(sse ./ max(n, 1)) ./ max(sy ./ max(n, 1), eps);
errShape = median(nrmse, 1, "omitmissing");

nCand = size(cand, 1);
scaleCvVec = zeros(1, nCand);
if numel(unique(month(selDays))) >= 2
    for c = 1:nCand
        scaleCvVec(c) = monthlyCv(scale(:, c), selDays);
    end
end

% Eğer Gmeas verilmişse (ör. SmartGridLab yatay G -> eğimli PV dizi akımı/gücü),
% a02_orientation_v2 amacı J = CV_intraday + CV_monthly doğrudan hesaplanır
if ~isempty(opts.Gmeas) && numel(opts.Gmeas) == numel(y)
    gm = opts.Gmeas(sel);
    poaSen = ges.solar.poaIrradiance(geo.GhiCs(sel), geo.DniCs(sel), geo.DhiCs(sel), ...
        geo.Zenith(sel), geo.Azimuth(sel), opts.SensorTilt, opts.SensorAzimuth);
    gArrMat = gm .* (poa ./ max(poaSen, 10));
    idxMat = ys ./ max(gArrMat / 1000, 0.02);
    moIdx = findgroups(dateshift(t(sel), "start", "month"));
    objJ = inf(1, nCand);
    for c = 1:nCand
        ic = idxMat(:, c);
        muD = (A * ic) ./ max(n, 1);
        sqD = (A * (ic.^2)) ./ max(n, 1);
        cvD = sqrt(max(sqD - muD.^2, 0)) ./ max(muD, eps);
        if max(moIdx) >= 2
            mm = accumarray(moIdx, ic, [max(moIdx) 1], @median, NaN);
            cvM = std(mm, "omitmissing") / max(mean(mm, "omitmissing"), eps);
        else
            cvM = 0;
        end
        objJ(c) = median(cvD(n >= 8), "omitmissing") + cvM;
    end
    score = 0.5 * errShape + 0.5 * objJ;
else
    objJ = errShape + opts.SeasonalWeight * scaleCvVec;
    score = objJ;
end

[~, k] = min(score);
h = find(cand(:,1) == 0, 1);
res.Tilt = cand(k,1);
res.Azimuth = cand(k,2);
res.Error = errShape(k);
res.ErrorHorizontal = errShape(h);
res.ScaleCv = scaleCvVec(k);
res.ScaleCvHorizontal = scaleCvVec(h);
res.Scale = median(scale(:,k), "omitmissing");
res.NumDays = numel(selDays);
res.ObjectiveJ = objJ(k);

surf = nan(numel(opts.Tilts), numel(opts.Azimuths));
for i = 1:nCand
    ti = opts.Tilts == cand(i,1);
    if cand(i,1) == 0
        surf(ti,:) = errShape(i);
    else
        surf(ti, opts.Azimuths == cand(i,2)) = errShape(i);
    end
end
res.ErrorSurface = surf;
res.Tilts = opts.Tilts;
res.Azimuths = opts.Azimuths;
end

function cv = monthlyCv(s, days)
% Aylık medyan ölçek katsayılarının değişim katsayısı (mevsimsel tutarlılık).
m = groupsummary(s, month(days), "median");
if numel(m) < 2
    cv = 0;
else
    cv = std(m, "omitmissing") / max(mean(m, "omitmissing"), eps);
end
end
