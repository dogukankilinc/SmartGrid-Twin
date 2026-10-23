function [sig, meta] = injectFault(sig, expectedN, type, nStrings, rngState)
%INJECTFAULT Gerçek sağlıklı bir günün sinyaline fiziksel olarak tutarlı sentetik arıza ekler.
%   [sig, meta] = ges.scalogram.injectFault(sig, expectedN, type, nStrings)
%   sig       : 64×3 [güç, ışınım, eksik] (ges.scalogram.dailySignals, sağlıklı gün)
%   expectedN : 64×1 M1 beklentisi / kapasite
%   type      : "string_dead" | "string_weak" | "inverter_trip" | "thermal_derating" | "soiling"
%   nStrings  : invertörün kurulu string sayısı (tek stringli SmartGridLab'da alt-modül/bypass
%               diyot gruplarını temsil etmek üzere en az 3 alt-grup olarak modellenir)
arguments
    sig (:,3) double
    expectedN (:,1) double
    type (1,1) string
    nStrings (1,1) double
    rngState = []
end

if ~isempty(rngState)
    rng(rngState);
end
effStrings = max(nStrings, 3);                   % tek stringli eviricide 3 bypass diyot alt-grubu
p = sig(:, 1);
n = numel(p);
day = find(sig(:, 2) > 0.05);                   % ışınım olan adımlar
if isempty(day)
    day = (1:n)';
end
t0 = day(1);
t1 = day(end);
meta = struct("Type", type);

switch type
    case "string_dead"
        k = 1 / effStrings;
        if rand < 0.6                            % çoğunlukla günün tamamı (kronik)
            from = 1;
        else                                      % gün içinde kopma / bypass diyot çökmesi
            from = randi([t0, max(t0, round((t0 + t1) / 2))]);
        end
        p(from:end) = p(from:end) * (1 - k);
        meta.Fraction = k;
        meta.From = from;
    case "string_weak"
        rho = 0.3 + 0.4 * rand;                   % zayıf stringin normale oranı
        k = (1 - rho) / effStrings;
        p = p * (1 - k);
        meta.Fraction = k;
        meta.Rho = rho;
    case "inverter_trip"
        from = randi([t0, max(t0, t1 - 4)]);
        if rand < 0.4
            to = n;                               % gün sonuna kadar
        else
            to = min(n, from + randi([4, 24]));   % 1-6 saat
        end
        p(from:to) = 0;
        meta.From = from;
        meta.To = to;
    case "thermal_derating"
        c = 0.72 + 0.16 * rand;
        period = randi([3 5]);
        phase = randi(period);
        spike = 1.0 + 0.3 * rand;
        mid = find((1:n)' >= t0 + round(0.25 * (t1 - t0)) & (1:n)' <= t0 + round(0.85 * (t1 - t0)));
        base = p(mid) * c .* (1 + 0.03 * randn(numel(mid), 1));
        isSpike = mod(mid + phase, period) == 0;
        base(isSpike) = min(p(mid(isSpike)) * spike, 1.2 * max(p));
        p(mid) = base;
        meta.BaseFraction = c;
        meta.Period = period;
        meta.Spike = spike;
    case "soiling"
        s = 0.04 + 0.11 * rand;
        p = p * (1 - s);
        meta.Loss = s;
    otherwise
        error("ges:scalogram:unknownFault", "Bilinmeyen sentetik arıza tipi: %s", type);
end
p = max(p, 0);
sig(:, 1) = p;
sig(:, 3) = max(max(expectedN, 0) - p, 0);
end
