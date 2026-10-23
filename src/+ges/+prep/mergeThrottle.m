function [TT, source] = mergeThrottle(TT, cfg, id)
%MERGETHROTTLE Gizli ısıl kısma imzasını işlenmiş invertör verisine ekler (panel, teşhis ve değerlendirme ortak).
%   [TT, source] = ges.prep.mergeThrottle(TT, cfg, id) — eklenen sütunlar: qThrottle, ThrottleLossKw, Ppot.

TT.qThrottle = false(height(TT), 1);
TT.ThrottleLossKw = zeros(height(TT), 1);
TT.Ppot = nan(height(TT), 1);
source = "";
thrFile = fullfile(cfg.paths.throttle, id + ".mat");
thrFileP = fullfile(cfg.paths.throttleP, id + ".mat");
if isfile(thrFile)
    Th = load(thrFile, "Time", "Throttled", "LossKw", "Ppot");
    [tf, loc] = ismember(TT.Time, Th.Time);
    TT.Ppot(tf) = double(Th.Ppot(loc(tf)));
    source = "VI";
elseif isfile(thrFileP)
    Th = load(thrFileP, "Time", "Throttled", "LossKw");
    [tf, loc] = ismember(TT.Time, Th.Time);
    source = "P";
else
    return
end
TT.qThrottle(tf) = Th.Throttled(loc(tf));
TT.ThrottleLossKw(tf) = double(Th.LossKw(loc(tf)));
end
