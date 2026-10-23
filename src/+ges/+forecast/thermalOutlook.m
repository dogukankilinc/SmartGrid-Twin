function T = thermalOutlook(E, K, tNow, opts)
%THERMALOUTLOOK Yarın için invertör bazında ısıl kısma ve Faiman hücre sıcaklığı tahmini ("melez" yöntem).
%   T = ges.forecast.thermalOutlook(E, K, tNow) — E: ges.runtime.ReplayEngine, K: k01_thermal.mat içeriği
%   (models, fleet). Yöntem:
%     yarın kısma saati = son tamamlanan günün GERÇEK kısma saati
%                        + ısıl ikizin [M(yarının havası) − M(o günün havası)] farkı
%   T: Id, BaseDay, BaseHours, PredHours, PredLossKwh, LossPerHour, TcabMaxPred, TcellMaxPred, InvLossKwhPred.
arguments
    E
    K (1,1) struct
    tNow (1,1) datetime
    opts.Weather (1,1) string {mustBeMember(opts.Weather, ["measured" "persist"])} = "measured"
    opts.Target (1,1) datetime = NaT            % tahmin edilen gün (varsayılan: yarın)
end
today = dateshift(tNow, "start", "day");
target = opts.Target;
if isnat(target)
    target = today + days(1);
end
% son tamamlanan gün: hedeften önceki gün tamamsa o, değilse bir önceki
base = target - days(1);
if base + hours(21) > tNow
    base = base - days(1);
end
rowsOf = @(d) find(E.Times >= d & E.Times < d + days(1));
rb = rowsOf(base);
if isempty(rb)
    [~, idxLast] = max(E.Times(E.Times <= tNow));
    base = dateshift(E.Times(idxLast), "start", "day");
    rb = rowsOf(base);
end
rt = rowsOf(target);
if opts.Weather == "persist" || isempty(rt) || numel(rt) ~= numel(rb)
    rw = rb;                                             % yarının havası = son tamamlanan günün havası
else
    rw = rt;
end
n = numel(E.Ids);
if isfield(K, "models") && ~isempty(K.models)
    ids = string({K.models.Id});
    A0 = median(cell2mat(arrayfun(@(m) m.Model.A(:)', K.models, UniformOutput=false)), 1)';
else
    ids = strings(0, 1);
    A0 = [5.0; 1.0; 25.0; -2.0];
end
if isfield(K, "fleet") && numel(K.fleet) == 2 && ~any(isnan(K.fleet))
    fleetB = K.fleet;
else
    fleetB = [-24.0; 0.40];
end
T = table(E.Ids, repmat(base, n, 1), zeros(n, 1), zeros(n, 1), zeros(n, 1), zeros(n, 1), nan(n, 1), nan(n, 1), zeros(n, 1), ...
    VariableNames=["Id" "BaseDay" "BaseHours" "PredHours" "PredLossKwh" "LossPerHour" "TcabMaxPred" "TcellMaxPred" "InvLossKwhPred"]);
w7 = find(E.Times >= tNow - days(7) & E.Times <= tNow);
if isprop(E, "WindSpeed") && ~isempty(E.WindSpeed)
    wBase = E.WindSpeed(rb);
    wTarg = E.WindSpeed(rw);
else
    wBase = repmat(0.7, numel(rb), 1);
    wTarg = repmat(0.7, numel(rw), 1);
end
for k = 1:n
    j = find(ids == E.Ids(k), 1);
    if isempty(j)
        M = struct("A", A0, "B", fleetB, "Pooled", true, "Depth", 0.3);   % model yok (yeni/test cihazı): filo
    else
        M = K.models(j).Model;
    end
    baseH = nnz(E.Thr(rb, k)) / 4;
    pB = ges.forecast.predictThrottle(M, E.Times(rb), E.Tamb(rb), E.Gref(rb), double(E.PexpWork(rb, k)), ...
        Fleet=fleetB, Elevation=E.Elev(rb), WindSpeed=wBase);
    pT = ges.forecast.predictThrottle(M, E.Times(rw), E.Tamb(rw), E.Gref(rw), double(E.PexpWork(rw, k)), ...
        Fleet=fleetB, Elevation=E.Elev(rw), WindSpeed=wTarg);
    T.BaseHours(k) = baseH;
    T.PredHours(k) = min(max(baseH + pT.Hours - pB.Hours, 0), 16);
    thr7 = nnz(E.Thr(w7, k)) / 4;
    lph = sum(double(E.ThrLoss(w7, k)), "omitnan") * 0.25 / max(thr7, eps);
    if thr7 < 1
        lph = M.Depth * max(double(E.PexpWork(rw, k)), [], "omitnan");   % geçmiş yoksa derinlik × tepe güç
    end
    if isnan(lph) || lph < 0
        lph = 0;
    end
    T.LossPerHour(k) = lph;
    T.PredLossKwh(k) = T.PredHours(k) * lph;
    sunMask = E.Gref(rw) > 250;
    if any(sunMask)
        T.TcabMaxPred(k) = max(pT.Tcab(sunMask), [], "omitnan");
        T.TcellMaxPred(k) = max(pT.TcellDyn(sunMask), [], "omitnan");
    end
    T.InvLossKwhPred(k) = pT.InvLossKwh;
end
T.Properties.UserData = struct("Target", target, "Base", base, "Weather", opts.Weather);
end
