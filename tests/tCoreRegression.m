function tests = tCoreRegression
%TCOREREGRESSION Kritik sayıların otomatik kontrolü — kod değiştikçe sonuçların sessizce bozulmasını yakalar.
%   Üç tür test:
%   A) YENİDEN ÜRETİM: bugünkü kod, kayıtlı çıktıları (beklenen güç, adım bayrakları, olaylar, sağlık durumu,
%      ısıl kısma imzası, gün etiketleri) birebir yeniden üretiyor mu? (panel bu kayıtlı çıktıları kullanır)
%   B) ALTIN DEĞER: sabit vakalarda (tests/coreCases.m) değerlendirme, üç görüş/uzlaşı kararları, CNN
%      olasılıkları ve ısıl ikiz katsayıları kayıtlı altın değerlere eşit mi? (bilerek değişince: makeGolden)
%   C) KABUL EŞİĞİ: doğrulanmış başarımın altına düşülmüyor mu? (RAPOR.md §9.19'daki sayılar, pay bırakılarak)
%      ve güvenlik kuralları (test dilimi / test invertörü sızıntı koruması, veri yok = "offline").
%   Süre ~1-2 dk (önbellekli oynatma motoru). Çalıştırma: runAllTests
tests = functiontests(localfunctions);
end

function setupOnce(tc)
root = fileparts(fileparts(mfilename("fullpath")));
addpath(root, fullfile(root, "tests"));
setupGes();
tc.TestData.env = goldenEnv();
f = fullfile(root, "tests", "golden", "core_golden.mat");
tc.assertTrue(isfile(f), "Altın değer dosyası yok: önce makeGolden(""ilk kayıt"") çalıştırın.");
tc.TestData.G = load(f).G;
end

%% ===================================================================== A) yeniden üretim
function testAnomalyPipelineReproducesArtifacts(tc)
% M1 beklentisi → dedektörler → olaylar → sağlık durumu zinciri (v2-I01 ile aynı çağrılar)
cfg = tc.TestData.env.cfg;
bundle = load(fullfile(cfg.paths.models, cfg.files.m1)).bundle;
for id = ["K02-INV07" "K03-INV46"]                      % V/I imzalı · gerilimsiz (güç+sıcaklık imzası)
    S = load(fullfile(cfg.paths.processed, "train", "inverter", id + ".mat"), "TT", "info");
    [TT, src] = ges.prep.mergeThrottle(S.TT, cfg, id);
    sigName = "V/I imzası";
    if src == "P", sigName = "güç+sıcaklık imzası"; end
    f = bundle.Fingerprints(bundle.Fingerprints.Id == id, :);
    ex = ges.anomaly.expectedPower(bundle, TT, S.info, struct("AmPm", f.AmPm, "Vmean", f.Vmean, "Cabin", f.Cabin));
    s = ges.anomaly.detectSteps(TT, ex);
    events = ges.anomaly.inverterEvents(TT, ex, s, S.info.Id, f.Cabin, sigName);
    state = ges.anomaly.healthState(TT, s, events);
    ref = load(fullfile(cfg.paths.anomaly, id + ".mat"));
    tc.verifyEqual(ex.Pdc, ref.Steps.Pdc_exp, "AbsTol", 1e-6, id + ": beklenen güç (M1) değişti");
    tc.verifyEqual(ex.PdcWork, ref.Steps.PdcWork_exp, "AbsTol", 1e-6, id + ": çalışan stringlerle beklenen güç değişti");
    tc.verifyEqual(state, ref.Steps.HealthState, id + ": sağlık durumu dizisi değişti");
    tc.verifyEqual(s.Throttle, ref.Steps.Throttle, id + ": kısma adımları değişti");
    tc.verifyEqual(height(events), height(ref.Events), id + ": olay sayısı değişti");
    tc.verifyEqual(events(:, ["Type" "PV" "Severity" "Start" "End"]), ref.Events(:, ["Type" "PV" "Severity" "Start" "End"]), ...
        id + ": olay kataloğu değişti");
end
end

function testThrottleSignatureReproducesArtifact(tc)
% Gizli ısıl kısma (string V/I imzası, nedensel 120 günlük zarf) — v2-B01 çıktısı
cfg = tc.TestData.env.cfg;
id = "K02-INV07";
D = load(fullfile(cfg.paths.processed, "train", "inverter", id + ".mat"), "TT", "info");
sig = ges.anomaly.throttleSignatureRolling(D.TT, D.info);
ref = load(fullfile(cfg.paths.throttle, id + ".mat"), "Throttled", "Valid");
tc.verifyEqual(sig.Throttled, ref.Throttled, "Kısma imzası (V/I) değişti");
tc.verifyEqual(sig.Valid, ref.Valid, "Kısma imzasının değerlendirilebildiği adımlar değişti");
end

function testDayLabelsReproduceArtifact(tc)
% Etiketleme fonksiyonları (1. görüş) — v2-L01 gün etiketleri
cfg = tc.TestData.env.cfg;
root = cfg.paths.root;
L = load(fullfile(root, "artifacts", "v2", "cnn", "day_labels_v2.mat")).labels;
catalog = load(fullfile(cfg.paths.anomaly, "events_catalog.mat")).catalog;
for id = ["K02-INV07" "K15-INV11"]
    S = load(fullfile(cfg.paths.processed, "train", "inverter", id + ".mat"), "TT", "D", "info");
    TT = ges.prep.mergeThrottle(S.TT(S.TT.Time < cfg.split.testStart, :), cfg, id);
    A = load(fullfile(cfg.paths.anomaly, id + ".mat"), "Steps").Steps;
    A = A(ismember(A.Time, TT.Time), :);
    F = ges.label.applyLabelingFunctions(ges.label.dayFeatures(TT, A, S.D, S.info, catalog(catalog.Id == id, :)));
    ref = L(L.Id == id, :);
    tc.verifyEqual(F.Day, ref.Day, id + ": gün listesi değişti");
    tc.verifyEqual(string(F.Label), string(ref.Label), id + ": gün etiketleri değişti");
    tc.verifyEqual(F.Votes, ref.Votes, id + ": etiketleme oyları değişti");
end
end

%% ===================================================================== B) altın değerler
function testAssessmentGolden(tc)
v = coreCases("assess", tc.TestData.env);
g = tc.TestData.G.assess;
for h = ["instant" "day" "week"]
    tc.verifyEqual(v.(h).StateCounts, g.(h).StateCounts, h + ": durum sayıları değişti");
    tc.verifyEqual([v.(h).Eact v.(h).Eexp], [g.(h).Eact g.(h).Eexp], "RelTol", 1e-9, h + ": enerji toplamları değişti");
    tc.verifyEqual(v.(h).Losses, g.(h).Losses, "AbsTol", 1e-6, h + ": kayıp dağılımı değişti");
    tc.verifyEqual(v.(h).Eexp - v.(h).Eact, sum(v.(h).Losses), "AbsTol", 1e-6, h + ": kayıp kalemleri toplam kayba eşit olmalı");
end
end

function testThreeOpinionDecisionsGolden(tc)
v = coreCases("decisions", tc.TestData.env);
g = tc.TestData.G.decisions;
tc.verifyEqual(v(:, ["Id" "Day"]), g(:, ["Id" "Day"]), "Değerlendirilen günler değişti");
tc.verifyEqual(v.Sensor, g.Sensor, "1. görüş (sensör kuralları) kararları değişti");
tc.verifyEqual(v.Peer, g.Peer, "3. görüş (komşu karşılaştırması) kararları değişti");
tc.verifyEqual(v.Consensus, g.Consensus, "Uzlaşı kararları değişti");
tc.verifyEqual(v.Level, g.Level, "Uzlaşı düzeyleri değişti");
tc.verifyEqual(v.PeerRatio, g.PeerRatio, "AbsTol", 1e-9, "Komşu oranları değişti");
end

function testVisualModelGolden(tc)
cfg = tc.TestData.env.cfg;
tc.assumeTrue(cfg.layers.research && isfile(fullfile(cfg.paths.models, "cnn_ml", "resnet18_ml.mat")), ...
    "Araştırma katmanı kapalı veya model yok");
v = coreCases("visual", tc.TestData.env);
g = tc.TestData.G.visual;
tc.verifyEqual(v.Key, g.Key, "CNN'e giren günler değişti");
tc.verifyEqual(v.Probs, g.Probs, "AbsTol", 2e-3, "Çok etiketli CNN olasılıkları değişti (skalogram veya model)");
tc.verifyEqual(v.Thr, g.Thr, "CNN karar eşikleri değişti");
end

function testThermalModelGolden(tc)
v = coreCases("thermal", tc.TestData.env);
g = tc.TestData.G.thermal;
for f = intersect(string(fieldnames(g))', string(fieldnames(v))')
    if isnumeric(g.(f)) || islogical(g.(f))
        tc.verifyEqual(v.(f), g.(f), "AbsTol", 1e-9, "Isıl ikiz alanı değişti: " + f);
    end
end
end

function testExpectedPowerGolden(tc)
v = coreCases("m1", tc.TestData.env);
tc.verifyEqual(v.nMAE, tc.TestData.G.m1.nMAE, "AbsTol", 1e-9, "Beklenen güç doğruluğu değişti");
end

%% ===================================================================== C) kabul eşikleri ve güvenlik
function testExpectedPowerAcceptance(tc)
% Doğrulanmış (v2-C01, Mayıs 2025, sağlıklı + kısılmamış): 99 invertörün medyanı %2,15, 90. yüzdelik %3,18,
% en kötüsü %4,10. Bu 4 invertörde ölçülen: %1,03 · %1,65 · %2,06 · %3,08. Kabul: her biri ≤ %4,5, ortalama ≤ %3.
v = coreCases("m1", tc.TestData.env);
tc.verifyLessThanOrEqual(max(v.nMAE), 0.045, "Beklenen güç hatası kabul sınırını aştı");
tc.verifyLessThanOrEqual(mean(v.nMAE), 0.03, "Beklenen güç ortalama hatası kabul sınırını aştı");
end

function testPeerConfirmsDeadStringsAcceptance(tc)
% Bağımsız teyit: sensörün 0 A dediği günlerde komşu karşılaştırması string kadar güç eksikliğini görmeli.
% Eğitim döneminde ölçülen: teyit %87.5, çürütme %0.4, sağlıklı günde yanlış iddia ~%7 (v3-M01).
% Kabul: teyit ≥ %80, çürütme ≤ %2, sağlıklı günde komşu sorun iddiası ≤ %10.
env = tc.TestData.env;
tz = env.cfg.data.timeZone;
ids = ["K02-INV07" "K02-INV31" "K12-INV05" "K15-INV11"];
T = ges.opinions.dayTable(env.cfg, env.fleet, datetime(2024, 6, 1, TimeZone=tz), datetime(2024, 9, 1, TimeZone=tz), ...
    Ids=ids, Verbose=false);
j = ges.opinions.classes() == "string_fault";
lab1 = string(arrayfun(@(o) o.Label, T.O1));
kind = string(arrayfun(@(o) o.StringKind, T.O1));
dead = lab1 == "string_fault" & kind == "dead" & arrayfun(@(o) o.Available, T.O3);
tc.assumeGreaterThan(nnz(dead), 20, "Bu invertörlerde yeterli ölü string günü yok");
st = arrayfun(@(o) o.Stance(j), T.O3(dead));
tc.verifyGreaterThanOrEqual(mean(st > 0), 0.80, "Komşu teyidi kabul sınırının altında");
tc.verifyLessThanOrEqual(mean(st < 0), 0.02, "Komşu çürütmesi kabul sınırının üstünde");
healthy = lab1 == "healthy" & arrayfun(@(o) o.Available, T.O3);
claim = arrayfun(@(o) o.Label ~= "healthy" && o.Label ~= "", T.O3(healthy));
tc.verifyLessThanOrEqual(mean(claim), 0.10, "Komşu görüşünün sağlıklı günde yanlış iddiası kabul sınırının üstünde");
end

function testConsensusRarelyRaisesFaultOnHealthyDays(tc)
% Sensör sağlıklı derken uzlaşının sorun kararı vermesi (tek görüşün yanlış alarmı) nadir olmalı.
g = coreCases("decisions", tc.TestData.env);
h = g.Sensor == "healthy";
tc.verifyLessThanOrEqual(mean(~ismember(g.Consensus(h), ["healthy" "uncertain"])), 0.05);
end

function testTestSliceGuard(tc)
% Test dilimi (≥ 01.06.2025) replay ile oynatılamaz; ajan bağlamı ondan veri göremez
cfg = tc.TestData.env.cfg;
tz = cfg.data.timeZone;
tc.verifyError(@() ges.runtime.ReplayEngine(cfg, datetime(2025, 5, 1, TimeZone=tz), cfg.split.testStart + days(1)), ...
    "ges:runtime:testSlice");
ctx = ges.agents.loadContext(cfg, datetime(2025, 5, 20, TimeZone=tz), Horizon=datetime(2025, 7, 1, TimeZone=tz), Layers="core");
tc.verifyLessThan(ctx.Horizon, cfg.split.testStart);
end

function testHoldoutInverterHidden(tc)
eng = tc.TestData.env.eng;
tc.verifyFalse(ismember("K02-INV21", eng.Ids), "Test invertörü oynatma verisinde olmamalı");
tc.verifyEqual(eng.HoldoutIds, "K02-INV21");
end

function testMissingDataShownOffline(tc)
% Kabin 12 dışa aktarımı 23.05.2025'te bitti: sonrasında gündüz "veri yok" görünmeli (yeşil değil)
eng = tc.TestData.env.eng;
tz = tc.TestData.env.cfg.data.timeZone;
i = find(eng.Times == datetime(2025, 5, 26, 12, 0, 0, TimeZone=tz), 1);
k12 = eng.Cabin == 12;
tc.verifyTrue(all(eng.State(i, k12) == "offline"));
end
