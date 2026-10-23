function makeGolden(note)
%MAKEGOLDEN Regresyon testlerinin altın değerlerini (tests/golden/core_golden.mat) yeniden kaydeder.
%   makeGolden("neden")  — YALNIZCA bir sonucun bilerek değiştiği durumlarda çalıştırın (ör. bir kural
%   düzeltildi ve yeni sonuç incelendi). Gerekçe dosyaya ve tests/golden/GECMIS.md'ye yazılır; eski
%   altın dosya tarihli yedek olarak saklanır. Testler, kod değiştiğinde sonuçların SESSİZCE değişmesini
%   yakalamak içindir: kırmızı test = "bir şey değişti, bilerek mi?" sorusu.
arguments
    note (1,1) string
end
root = fileparts(fileparts(mfilename("fullpath")));
addpath(root, fullfile(root, "tests"));
setupGes();
env = goldenEnv();
G = struct();
for part = ["assess" "decisions" "visual" "m1" "thermal"]
    fprintf("  %s...\n", part);
    G.(part) = coreCases(part, env);
end
G.Meta = struct("Created", string(datetime("now")), "Note", note, "Matlab", version);
dirG = fullfile(root, "tests", "golden");
if ~isfolder(dirG), mkdir(dirG); end
f = fullfile(dirG, "core_golden.mat");
if isfile(f)
    copyfile(f, fullfile(dirG, "core_golden_" + string(datetime("now"), "yyyyMMdd_HHmmss") + ".mat"));
end
save(f, "G");
writelines(sprintf("- %s: %s", string(datetime("now"), "yyyy-MM-dd HH:mm"), note), fullfile(dirG, "GECMIS.md"), WriteMode="append");
fprintf("Altın değerler kaydedildi: %s\n", f);
end
