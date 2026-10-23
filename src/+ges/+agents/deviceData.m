function d = deviceData(ctx, id)
%DEVICEDATA Bir invertörün işlenmiş verisi, M1 beklentisi ve künyesi (ctx önbelleğinden).
%   d = ges.agents.deviceData(ctx, id) — d.TT, d.Steps, d.D (günlük özet), d.info;
%   HER ÇAĞRIDA ctx.Now ve öncesine süzülür. Önbellek (containers.Map, tutamaç) veriyi
%   ctx.Horizon'a kadar tutar; böylece replay sırasında saat ilerledikçe araçlar geleceği
%   görmez ama diskten yeniden okuma da yapılmaz.
key = char(id);
if isKey(ctx.Cache, key)
    full = ctx.Cache(key);
else
    cfg = ctx.Cfg;
    proc = fullfile(cfg.paths.processed, ctx.Split);
    S = load(fullfile(proc, "inverter", id + ".mat"), "TT", "D", "info");
    A = load(fullfile(cfg.paths.anomaly, id + ".mat"), "Steps");       % v2 adımları (kısma dahil)
    % v2: gizli ısıl kısma imzası (string V/I; gerilimsiz invertörde güç+sıcaklık, B02) adımlara eklenir
    [TTk, full.ThrottleSource] = ges.prep.mergeThrottle(S.TT, cfg, id);
    full.TT = TTk(TTk.Time <= ctx.Horizon, :);
    full.Steps = A.Steps(A.Steps.Time <= ctx.Horizon, :);
    full.D = S.D(S.D.Time <= ctx.Horizon, :);
    full.info = S.info;
    if ctx.Cache.Count >= 40                       % bellek sınırı (~30 MB/invertör): en eski girdiyi at
        k = keys(ctx.Cache);
        remove(ctx.Cache, k{1});
    end
    ctx.Cache(key) = full;
end
d.TT = full.TT(full.TT.Time <= ctx.Now, :);
d.Steps = full.Steps(full.Steps.Time <= ctx.Now, :);
d.D = full.D(full.D.Time <= dateshift(ctx.Now, "start", "day"), :);
d.info = full.info;
d.ThrottleSource = full.ThrottleSource;   % "VI" (string gerilim+akım) | "P" (güç+sıcaklık, B02) | ""
end
