function [sig, info2] = throttleSignatureRolling(TT, info, opts)
%THROTTLESIGNATUREROLLING Nedensel (gerçek zamanlı uygun) kısma ve 4-kadranlı MPP imzası.
%   sig = ges.anomaly.throttleSignatureRolling(TT, info)
%   Uzun çok-yıllı veri setlerinde (>150 gün) her takvim ayı için önceki 120 günlük pencerede,
%   kısa veri setlerinde (örn. 11 haftalık SmartGridLab, ~77 gün) ise haftalık adımlarla önceki
%   14 günlük nedensel pencerede (ilk günlerde genişleyen önek / geri dönüş zarfıyla) öğrenilir.
%   Böylece hiçbir dönem NaN kalmaz ve gelecek bilgisi sızmaz.
arguments
    TT timetable
    info (1,1) struct
    opts.Window (1,1) double = 120          % gün (kısa veride otomatik 14 güne ölçeklenir)
    opts.MinSteps (1,1) double = 1500
    opts.TauV (1,1) double = 0.06
end

n = height(TT);
rated = 1.20;
if isfield(info, "Rated") && ~isempty(info.Rated) && ~isnan(info.Rated)
    rated = info.Rated;
end
sig = struct("dV", nan(n, 1), "dI", nan(n, 1), "Throttled", false(n, 1), ...
    "Clipping", TT.P_ac >= 0.97 * rated, "Valid", false(n, 1), "Ppot", nan(n, 1), ...
    "LossKw", zeros(n, 1), "CurrentDrop", false(n, 1), "VoltageDrop", false(n, 1), ...
    "SoilingHint", false(n, 1), "Quadrant", zeros(n, 1, "uint8"));

if n == 0
    info2.MonthsWithEnvelope = 0;
    return
end

spanDays = days(TT.Time(end) - TT.Time(1));
gCol = TT.G_ref;
if ismember("G_poa", TT.Properties.VariableNames) && any(~isnan(TT.G_poa))
    gCol = TT.G_poa;
end

if spanDays <= 150
    % Kısa veri modu (SmartGridLab 11 hafta): haftalık nedensel kayan pencere (14 gün)
    winDays = min(opts.Window, 14);
    minSt = min(opts.MinSteps, 80);
    t0 = dateshift(TT.Time(1), "start", "day");
    tEnd = dateshift(TT.Time(end), "start", "day") + days(1);
    edges = t0:days(7):tEnd;
    if edges(end) < tEnd
        edges(end+1) = tEnd;
    end
    thrPrev = false(n, 1);
    used = 0;
    % İlk 14 gün için başlangıç kalibrasyon zarfı (ilk 14 günün sağlıklı açık-gök adımları)
    warmMask = TT.Time < t0 + days(min(14, max(7, floor(spanDays / 3))));
    envFallback = ges.anomaly.mppEnvelope(TT(warmMask, :), info, MinSteps=25, IncludeDead=true);
    if isempty(envFallback)
        envFallback = ges.anomaly.mppEnvelope(TT, info, MinSteps=25, IncludeDead=true);
    end
    for w = 1:(numel(edges) - 1)
        inW = TT.Time >= edges(w) & TT.Time < edges(w+1);
        trainW = TT.Time >= edges(w) - days(winDays) & TT.Time < edges(w) & ~thrPrev;
        env = [];
        if nnz(trainW & TT.qOnGrid & gCol > 250) >= minSt
            env = ges.anomaly.mppEnvelope(TT(trainW, :), info, MinSteps=40, IncludeDead=true);
        elseif nnz(TT.Time < edges(w) & ~thrPrev & TT.qOnGrid & gCol > 250) >= 35
            env = ges.anomaly.mppEnvelope(TT(TT.Time < edges(w) & ~thrPrev, :), info, MinSteps=30, IncludeDead=true);
        end
        if isempty(env)
            env = envFallback;
        end
        if isempty(env)
            continue
        end
        s = ges.anomaly.throttleSignature(TT(inW, :), info, env, TauV=opts.TauV);
        sig = copySlice(sig, s, inW);
        thrPrev(inW) = s.Throttled;
        used = used + 1;
    end
    info2.MonthsWithEnvelope = max(1, numel(unique(dateshift(TT.Time(sig.Valid), "start", "month"))));
    info2.WindowsWithEnvelope = used;
    return
end

months = unique(dateshift(TT.Time, "start", "month"));
thrPrev = false(n, 1);
used = 0;
for m = months'
    inM = TT.Time >= m & TT.Time < m + calmonths(1);
    trainW = TT.Time >= m - days(opts.Window) & TT.Time < m & ~thrPrev;
    if nnz(trainW & TT.qOnGrid & gCol > 250) < opts.MinSteps
        continue
    end
    env = ges.anomaly.mppEnvelope(TT(trainW, :), info, MinSteps=300, IncludeDead=true);
    if isempty(env)
        continue
    end
    s = ges.anomaly.throttleSignature(TT(inM, :), info, env, TauV=opts.TauV);
    sig = copySlice(sig, s, inM);
    thrPrev(inM) = s.Throttled;
    used = used + 1;
end
info2.MonthsWithEnvelope = used;
end

function sig = copySlice(sig, s, mask)
sig.dV(mask) = s.dV;
sig.dI(mask) = s.dI;
sig.Throttled(mask) = s.Throttled;
sig.Valid(mask) = s.Valid;
sig.Ppot(mask) = s.Ppot;
sig.LossKw(mask) = s.LossKw;
if isfield(s, "CurrentDrop")
    sig.CurrentDrop(mask) = s.CurrentDrop;
    sig.VoltageDrop(mask) = s.VoltageDrop;
    sig.SoilingHint(mask) = s.SoilingHint;
    sig.Quadrant(mask) = s.Quadrant;
end
end
