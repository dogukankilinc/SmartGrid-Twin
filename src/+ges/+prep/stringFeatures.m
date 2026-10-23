function s = stringFeatures(current, installed, opts)
%STRINGFEATURES String akımlarından normalize akım ve ölü/zayıf string göstergeleri.
%   s = ges.prep.stringFeatures(current, installed, opts)
%   Hem çok-stringli (Huawei PV1..PV8) hem de tek-stringli (SMA WR13TL22-8231 I_dc)
%   eviricileri destekler. Tek stringli eviricide opts.ExpectedCurrent veya opts.G
%   verilmişse fiziksel referans akıma göre, verilmemişse kendi aktif akım zarfına
%   göre normalize eder.

arguments
    current (:,8) double
    installed (1,8) logical
    opts.DeadCurrent (1,1) double = 0.08
    opts.ActiveMedian (1,1) double = 0.5
    opts.MinMedian (1,1) double = 0.25
    opts.WeakRatio (1,1) double = 0.78
    opts.ExpectedCurrent (:,1) double = double.empty(0,1)
    opts.G (:,1) double = double.empty(0,1)
    opts.ImpNominal (1,1) double = 5.15
end

n = size(current, 1);
cur = current;
cur(:, ~installed) = NaN;

if nnz(installed) == 1
    kIdx = find(installed, 1);
    c1 = cur(:, kIdx);
    if numel(opts.ExpectedCurrent) == n
        refCur = opts.ExpectedCurrent;
    elseif numel(opts.G) == n
        refCur = opts.ImpNominal * (max(opts.G, 0) / 1000);
    else
        refCur = c1;
    end
    s.Median = c1;
    s.Norm = nan(n, 8);
    s.Norm(:, kIdx) = c1 ./ max(refCur, opts.MinMedian);
    s.Norm(refCur < opts.MinMedian, kIdx) = NaN;

    active = refCur > opts.ActiveMedian;
    s.Dead = false(n, 8);
    s.Weak = false(n, 8);
    s.Dead(:, kIdx) = active & (isnan(c1) | c1 < opts.DeadCurrent);
    s.Weak(:, kIdx) = active & ~s.Dead(:, kIdx) & (s.Norm(:, kIdx) < opts.WeakRatio);
else
    s.Median = median(cur, 2, "omitmissing");
    s.Norm = cur ./ s.Median;
    s.Norm(s.Median < opts.MinMedian, :) = NaN;

    active = s.Median > opts.ActiveMedian;
    s.Dead = installed & cur < opts.DeadCurrent & active;
    s.Weak = installed & s.Norm < opts.WeakRatio & ~s.Dead & active;
end

s.NumDead = sum(s.Dead, 2);
s.NumWeak = sum(s.Weak, 2);
s.DeadMask = uint8(s.Dead * (2 .^ (0:7))');
end
