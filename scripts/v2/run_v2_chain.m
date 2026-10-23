function run_v2_chain(steps)
%RUN_V2_CHAIN v2 analiz zincirini (nedensel kısma algılayıcısıyla) sırayla yeniden üretir.
%   run_v2_chain() — Sıra: B01 kısma → B02 gerilimsiz invertör kısması → D02 tozlanma → F01 degradasyon → C01 M1-v2 → G01 kayıplar →
%   H01 ısıl ikiz → H02 conformal → I01 çalışma zamanı dosyaları → J01 test invertörü.
%   Alt betikler `clear` yaptığı için temel çalışma alanında (evalin) çalıştırılır; bu fonksiyonun
%   değişkenleri etkilenmez. Her adımın günlüğü artifacts/logs/v2_*.log; özet v2_chain.log.
%   Statik-zarf sürümünün çıktıları *_static.* olarak arşivlendi (makalede karşılaştırma için).
arguments
    steps (1,:) string = ["b01_throttle_scan" "b02_throttle_power_only" "d02_soiling_dryspells" "f01_degradation" "c01_train_m1_v2" ...
        "g01_losses_reliability" "h01_thermal_twin" "h02_conformal_alarm" "i01_build_anomaly_v2" "k01_thermal_forecast" ...
        "k02_early_warning" "j01_holdout_eval_v2"]
end
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
chainLog = fullfile(root, "artifacts", "logs", "v2_chain.log");
writelines("=== v2 zinciri " + string(datetime("now")), chainLog);
for s = steps
    t = tic;
    try
        evalin("base", sprintf("run('%s')", strrep(fullfile(root, "scripts", "v2", s + ".m"), "'", "''")));
        writelines(sprintf("%-26s tamam (%.0f s)", s, toc(t)), chainLog, WriteMode="append");
    catch err
        writelines(sprintf("%-26s HATA: %s @ %s:%d", s, err.message, err.stack(1).name, err.stack(1).line), chainLog, WriteMode="append");
        break
    end
end
writelines("=== v2 zinciri bitti " + string(datetime("now")), chainLog, WriteMode="append");
end
