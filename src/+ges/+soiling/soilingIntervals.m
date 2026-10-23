function [loss, rate, intervals] = soilingIntervals(day, pi, cleanDays, opts)
%SOILINGINTERVALS Temizlenmeler arası tozlanma hızı, birikmiş kayıp ve R_iso doğrulamalı temizlenme.
%   [loss, rate, intervals] = ges.soiling.soilingIntervals(day, pi, cleanDays)
%   day, pi   : günlük performans / tozlanma oranı indeksi (NaN = ölçüm yok)
%   cleanDays : temizlenme (yağmur / yıkama) günleri — boş verilirse SR sıçraması + R_iso/Kd ile otomatik bulunur.
%   Her aralıkta PI ~ a + b·(gün) Theil-Sen ile uydurulur (aykırı günlere dayanıklı).
%   b < 0 ise aralık tozlanma aralığıdır: hız = -b/a (birim/gün), birikmiş kayıp
%   loss(d) = 1 - PI_fit(d)/PI_fit(aralık başı). b >= 0 ise kayıp 0 kabul edilir.
%   v3 Geliştirmesi: R_iso < 1500 kOhm (ıslak yüzey kanıtı) ve Kd < 0.45 (kapalı gök)
%   verildiğinde temizlenme olayları "RainCleaning" veya "DryWashOrWind" olarak sınıflandırılır.
arguments
    day (:,1) datetime
    pi (:,1) double
    cleanDays datetime = NaT(0, 1)
    opts.MinDays (1,1) double = 10
    opts.MinValid (1,1) double = 6
    opts.Kd (:,1) double = []
    opts.RisoMin (:,1) double = []
    opts.JumpThreshold (1,1) double = 0.015
    opts.WashCostTl (1,1) double = 1500
    opts.ElecPriceTl (1,1) double = 3.0
    opts.DailyEnergyKwh (1,1) double = 6.5
end

n = numel(day);
loss = zeros(n, 1);
rate = zeros(n, 1);

% Eğer cleanDays boşsa, pi/SR serisindeki pozitif basamak sıçramalarından otomatik tespit et
cleanDays = cleanDays(:);
if isempty(cleanDays) || all(isnat(cleanDays))
    cleanDays = detectCleanDays(day, pi, opts.JumpThreshold, opts.Kd, opts.RisoMin);
end

edges = unique([day(1); sort(cleanDays(cleanDays > day(1) & cleanDays <= day(end))); day(end) + caldays(1)]);
nInt = numel(edges) - 1;
rows = cell(nInt, 1);
for k = 1:nInt
    in = day >= edges(k) & day < edges(k + 1);
    ok = in & ~isnan(pi);
    x = days(day(ok) - edges(k));
    y = pi(ok);
    b = 0;
    a = median(y, "omitmissing");
    minDaysEff = min(opts.MinDays, max(4, floor(n / 3)));
    minValidEff = min(opts.MinValid, max(3, floor(nnz(~isnan(pi)) / 4)));
    if nnz(ok) >= minValidEff && days(edges(k + 1) - edges(k)) >= minDaysEff
        [a, b] = ges.stats.theilSen(x, y);
        if isnan(b)
            b = 0;
            a = median(y, "omitmissing");
        end
    end
    if b < 0 && a > 0
        xi = days(day(in) - edges(k));
        loss(in) = min(max(0, -b * xi / a), 0.5);
        rate(in) = -b / a;
    end
    cType = classifyCleaning(edges(k), day, opts.Kd, opts.RisoMin, k == 1);
    rows{k} = table(edges(k), edges(k + 1) - caldays(1), nnz(ok), a, -b / max(a, eps), cType, ...
        VariableNames=["Start" "End" "ValidDays" "CleanLevel" "RatePerDay" "CleaningType"]);
end
intervals = vertcat(rows{:});

% Ekonomik optimum temizlik periyodu: T* = sqrt(2*C / (r * E * p))
activeRates = intervals.RatePerDay(intervals.RatePerDay > 0);
if isempty(activeRates)
    rMed = 0.0015;
else
    rMed = median(activeRates, "omitnan");
end
tOpt = sqrt(2 * opts.WashCostTl / max(rMed * opts.DailyEnergyKwh * opts.ElecPriceTl, 1e-6));
intervals.Properties.UserData = struct("MedianRatePerDay", rMed, "OptWashDays", tOpt, ...
    "WashCostTl", opts.WashCostTl, "ElecPriceTl", opts.ElecPriceTl, "DailyEnergyKwh", opts.DailyEnergyKwh);
end

function cDays = detectCleanDays(day, sr, minJump, kd, riso)
n = numel(sr);
jump = nan(n, 1);
valid = find(~isnan(sr));
w = 3;
for d = 1:n
    before = valid(valid < d);
    after = valid(valid >= d);
    if numel(before) >= w && numel(after) >= w
        jump(d) = median(sr(after(1:w))) - median(sr(before(end - w + 1:end)));
    end
end
v = sr(~isnan(sr));
if numel(v) >= 6
    noise = 1.4826 * median(abs(diff(v) - median(diff(v))));
    thr = max(minJump, 2.5 * noise);
else
    thr = minJump;
end
isPeak = jump >= thr & jump == movmax(jump, [3 3], "omitmissing");
% R_iso < 1500 kOhm ve Kd < 0.45 olan şiddetli yağış günlerinde eşiği %25 esnet
if numel(kd) == n && numel(riso) == n
    wetRain = kd < 0.45 & riso < 1500;
    wetPeak = jump >= 0.75 * thr & wetRain & jump == movmax(jump, [2 2], "omitmissing");
    isPeak = isPeak | wetPeak;
end
cDays = day(isPeak);
end

function cType = classifyCleaning(startDay, day, kd, riso, isFirst)
if isFirst
    cType = "PeriodStart";
    return
end
idx = find(day >= startDay - caldays(2) & day <= startDay);
hasKd = numel(kd) == numel(day) && ~isempty(idx);
hasRiso = numel(riso) == numel(day) && ~isempty(idx);
if hasKd && hasRiso
    isCloudy = any(kd(idx) < 0.45);
    isWet = any(riso(idx) < 1500);
    if isCloudy && isWet
        cType = "RainCleaning_RisoVerified";
    elseif isCloudy
        cType = "RainCleaning_CloudInferred";
    else
        cType = "DryWashOrWind";
    end
elseif hasKd
    if any(kd(idx) < 0.45)
        cType = "RainCleaning_CloudInferred";
    else
        cType = "DryWashOrWind";
    end
else
    cType = "CleaningEvent";
end
end
