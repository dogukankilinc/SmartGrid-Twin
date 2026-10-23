function env = goldenEnv()
%GOLDENENV Regresyon testleri ve makeGolden için ortak ortam: yapılandırma, oynatma motoru, komşu matrisi.
%   Oynatma motoru panelle aynı aralıkta açılır → önbellekten (~1 s) gelir.
cfg = gesConfig();
tz = cfg.data.timeZone;
eng = ges.runtime.ReplayEngine(cfg, datetime(2023, 12, 1, 4, 30, 0, TimeZone=tz), datetime(2025, 5, 31, 21, 0, 0, TimeZone=tz));
env = struct("cfg", cfg, "eng", eng, "fleet", ges.opinions.fleetFromEngine(eng));
end
