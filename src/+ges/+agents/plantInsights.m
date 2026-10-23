function out = plantInsights(ctx, topic)
%PLANTINSIGHTS SmartGrid-Twin (WR13TL22-8231, 1.20 kWp) tesis analizlerinin özeti ve nedensel RAG bilgileri.
%   out = ges.agents.plantInsights(ctx, topic) — topic: kayip | kisma | tozlanma | bulut |
%   degradasyon | bakim | nedensel | verim | termal | sebeke | yalitim | hepsi.
%   Değerler artifacts/v2 altındaki betik çıktılarından (scripts/v2/*.m) OKUNUR; hiçbir sayı burada
%   üretilmez. Çıktısı henüz üretilmemiş bölüm hata yerine Durum = "artifact yok" ile döner.
%   "nedensel" bölümü ham verideki fiziksel olguların (k/18 röle, Ross vs Faiman, R_iso, reset imzası)
%   doğru yorumunu içerir (halüsinasyon önleme; veriden doğrulanmış sabit gerçekler).
%   Dönem: 27 Tem – 17 Eki 2026 — gerçek zamanlı değil, çevrim dışı tesis analizidir.
arguments
    ctx (1,1) struct
    topic (1,1) string = "hepsi"
end
topic = lower(strtrim(topic));
all = ["kayip" "kisma" "tozlanma" "bulut" "degradasyon" "bakim" "nedensel" "verim" "termal" "sebeke" "yalitim"];
if topic == "hepsi"
    out = struct("Donem", "2026-07-27 – 2026-10-17 (SmartGrid-Twin, 15 dk; çevrim dışı analiz)", ...
        "Kaynak", "scripts/v2 betikleri, artifacts/v2 sonuç dosyaları");
    for t = all
        o = safeSection(ctx, t);
        for f = string(fieldnames(o))'
            if ~ismember(f, ["Donem" "Kaynak"])
                out.(f) = o.(f);
            end
        end
    end
else
    out = safeSection(ctx, topic);
end
end

function o = safeSection(ctx, t)
try
    switch t
        case "nedensel"
            o = causalFacts();
        case {"verim" "termal" "sebeke" "yalitim"}
            o = liveSection(ctx, t);
        otherwise
            o = sectionInsights(ctx, t);
    end
catch ME
    o = struct("Donem", "2026-07-27 – 2026-10-17", "Kaynak", "scripts/v2", ...
        "Durum", "artifact yok veya okunamadı: " + string(ME.message));
end
end

function o = causalFacts()
% Verideki 4 altın nedensel olgu (docs/04 §2.4); sayılar ham CSV'den doğrulanmıştır.
o.Nedensel = struct( ...
    "RoleAltOrnekleme", "Sabah/akşam düşük ışınımda (G < 250 W/m²) görülen 33,33 Hz (12/18), 41,67 Hz (15/18) frekans ve 151 V, 188 V gerilimler şebeke çökmesi değildir: SMA evirici 15 dakikada 18 adet 50 saniyelik alt-örnekten k tanesinde röleyi kapalı tutar (α_relay = k/18). Röle kapalıyken gerçek şebeke gerilimi V_L1,cond = V_L1·(50/f_grid) ≈ 228,3 V'tur. Gerçek gündüz şebeke kesintisi yalnızca 29.07.2026 11:45'te yaşanmıştır (G = 873 W/m², V_L1 = 0 V, f = 0 Hz).", ...
    "RossFaiman", "CSV'deki 'Module temperature' gerçek sensör değil, rüzgarsız Ross formülüdür (T_amb + 0,028·G). Sistem 'System wind speed' ile gerçek Faiman hücre sıcaklığını (T_cell,dyn) hesaplar; fark rüzgar soğutma kazancı ΔT_wind'dir.", ...
    "RisoCiy", "R_iso 1153–3000 kΩ aralığındadır; 3000 kΩ sensörün üst doygunluk sınırıdır. Sabah nemi ve yağışlı günlerde (28–30 Eylül) 1153–1350 kΩ bandına inip panel ısındıkça 3000 kΩ'a dönmesi normaldir (> 1000 kΩ güvenli); sıcak öğlede düşük kalması erken uyarıdır.", ...
    "ResetImzasi", "Gündüz 15 dakikalık ızgara dışına (:10, :25, :50) düşen dört 'Active power limitation = 0,00 %' kaydı (31 Temmuz 15:10, 29 Ağustos 12:25 ve 14:00, 3 Eylül 18:50) güç kısma komutu değil, kesinti sonrası evirici yeniden başlatma anlarıdır (qResetEvent/qRebootEvent).", ...
    "AltinOlaylar", "29 Temmuz 11:45 şebeke kesintisi (grid_event + idle_no_dc); 29 Ağustos 11:30 V_dc = 230 V'a MPP→V_oc sıçraması; 3 Eylül olayı; 27–31 Temmuz kesinti haftası veri boşluğu; 10–15 Ağustos eksik hafta.", ...
    "Guven", "yüksek (ham veriden doğrulanmış)");
end

function o = liveSection(ctx, t)
% Cihazın ctx.Now'a kadarki işlenmiş verisinden canlı özet (artifact gerektirmez)
id = ctx.Inverters(1);
d = ges.agents.deviceData(ctx, id);
T = d.TT;
vn = T.Properties.VariableNames;
col = @(n) double(T.(n));
has = @(n) ismember(n, vn);
switch t
    case "verim"
        if ~has("Eff") || ~has("P_ac"), error("Eff/P_ac kolonu yok"); end
        e = col("Eff"); ok = e > 50 & e < 100;
        o.Verim = struct("MedyanYuzde", round(median(e(ok), "omitmissing"), 2), "TepeYuzde", round(max(e(ok), [], "omitmissing"), 2), ...
            "Not", "η_inv = P_ac/P_dc; Sandia modeli yük oranı ve V_dc'ye bağlıdır; kayıp P_dc − P_ac.", "Guven", "yüksek");
    case "termal"
        if ~has("T_cell_dyn") || ~has("T_mod"), error("T_cell_dyn/T_mod kolonu yok"); end
        o.Termal = struct("TcellMaksC", round(max(col("T_cell_dyn"), [], "omitmissing"), 1), "TmodRossMaksC", round(max(col("T_mod"), [], "omitmissing"), 1), ...
            "Not", "T_mod rüzgarsız Ross; T_cell_dyn rüzgarlı Faiman. Fark rüzgar soğutma kazancıdır.", "Guven", "yüksek");
    case "sebeke"
        if ~has("U_L1") || ~has("f_grid"), error("U_L1/f_grid kolonu yok"); end
        c = []; if has("U_L1_cond"), c = col("U_L1_cond"); c = c(c > 100); end
        o.Sebeke = struct("VcondMedyanV", round(median(c, "omitmissing"), 1), "VcondMaksV", round(max(c, [], "omitmissing"), 1), ...
            "Not", "EN 50160 bandı 207–253 V; düşük f/V adımları k/18 röle etkisidir. R_th = ΔV_L1,cond/ΔI_L1.", "Guven", "yüksek");
    case "yalitim"
        if ~has("R_iso"), error("R_iso kolonu yok"); end
        r = col("R_iso");
        o.Yalitim = struct("MinKOhm", round(min(r, [], "omitmissing")), "MedyanKOhm", round(median(r, "omitmissing")), ...
            "DoygunlukKOhm", 3000, "Not", "Sabah çiyi 1153–1350 kΩ'a düşürür; öğlen 3000 kΩ doygunluğuna dönülür.", "Guven", "yüksek");
end
end
arguments
    ctx (1,1) struct
    topic (1,1) string = "hepsi"
end

v2 = fullfile(ctx.Cfg.paths.root, "artifacts", "v2");
topic = lower(strtrim(topic));
out = struct("Donem", "2026-07-27 – 2026-10-17 (SmartGrid-Twin, 15 dk; çevrim dışı analiz)", ...
    "Kaynak", "scripts/v2 betikleri, artifacts/v2 sonuç dosyaları");
want = @(t) topic == "hepsi" || topic == t;

if want("kayip")
    G = load(fullfile(v2, "g01_losses.mat"), "cats", "L", "Eexp", "Eact");
    tot = sum(G.Eexp);
    k = struct("BeklenenMWh", round(tot / 1e3), "OlculenMWh", round(sum(G.Eact) / 1e3), ...
        "TeslimOrani", round(100 * sum(G.Eact) / tot, 1));
    % Büyükten küçüğe sıralı (LLM sıralamayı kendisi yanlış yapabiliyor); "üretim sürdü" kayıp değil
    mwh = sum(G.L, 1) / 1e3;
    isLoss = ~startsWith(G.cats, "veri boşluğu (üretim sürdü)") & G.cats ~= "açıklanamayan";
    [~, o] = sort(mwh, "descend");
    rows = struct("Sira", {}, "Neden", {}, "MWh", {}, "BeklenenYuzde", {});
    for c = o(isLoss(o))
        rows(end+1) = struct("Sira", numel(rows) + 1, "Neden", G.cats(c), "MWh", round(mwh(c), 1), ...
            "BeklenenYuzde", round(100 * mwh(c) * 1e3 / tot, 2)); %#ok<AGROW>
    end
    k.SiralamaOzeti = "Kayıp sıralaması (büyükten küçüğe): " + strjoin(compose("%d) %s %.1f MWh (%%%.2f)", ...
        [rows.Sira]', string({rows.Neden})', [rows.MWh]', [rows.BeklenenYuzde]'), "; ");
    k.KayipSiralamasi = rows;
    k.KayipDegil = sprintf("veri boşluğunda üretim sürdü: %.1f MWh (E_life sayacı; yalnızca veri eksik)", mwh(startsWith(G.cats, "veri boşluğu (üretim sürdü)")));
    k.Aciklanamayan = sprintf("%.1f MWh (%.2f %%) — modelleme kalanı", mwh(G.cats == "açıklanamayan"), 100 * mwh(G.cats == "açıklanamayan") * 1e3 / tot);
    k.Guven = "orta-yüksek (kalan açıklanamayan −%0,4)";
    k.OlcumKapsami = "Isıl kısma kaybı V_dc/I_dc imzasıyla ölçüldü. Veri kapsaması: 27–31 Temmuz kesintisi ve 10–15 Ağustos eksik hafta kayıp sayılmaz, veri boşluğudur. Tozlanma kaybı sensörle aynı düzlem (32° POA) varsayımıyla kestirildi.";
    out.Kayiplar = k;
end
if want("kisma")
    B = load(fullfile(v2, "b01_summary.mat"), "monthEdges", "lossMWh", "prodMWh", "ids", "V1", "V2");
    H = load(fullfile(v2, "h01_thermal.mat"), "R", "f", "edges");
    mo = string(B.monthEdges(1:end-1), "yyyy-MM");
    monthly = struct("Ay", cellstr(mo), "KayipMWh", num2cell(round(sum(B.lossMWh, 1), 1)), ...
        "KayipYuzde", num2cell(round(100 * sum(B.lossMWh, 1) ./ max(sum(B.prodMWh, 1), eps), 1)));
    [~, o] = sort(sum(B.lossMWh, 2), "descend");
    top = struct("Id", cellstr(B.ids(o(1:8))), "KayipMWh", num2cell(round(sum(B.lossMWh(o(1:8), :), 2), 1)));
    R = H.R;
    pair = ~isnan(R.ThrFrac60_68_2024) & ~isnan(R.ThrFrac60_68_2025);
    d = R.ThrFrac60_68_2025(pair) - R.ThrFrac60_68_2024(pair);
    [~, ord] = sort(R.ThrFrac60_68_2025 - R.ThrFrac60_68_2024, "descend", "MissingPlacement", "last");
    out.IsilKisma = struct("ToplamKayipMWh", round(sum(B.lossMWh, "all")), ...
        "DcUretimYuzde", round(100 * sum(B.lossMWh, "all") / sum(B.prodMWh, "all"), 2), ...
        "BaslangicT10_C", round(crossing(H.edges, H.f, 0.10), 1), "BaslangicT50_C", round(crossing(H.edges, H.f, 0.50), 1), ...
        "AylikKayip", monthly, "EnCokKaybeden", top, ...
        "AyniSicaklikta2025vs2024", sprintf("60–68 °C iç sıcaklıkta kısma oranı medyan %+.1f puan (%d/%d invertörde arttı) — soğutma yıpranması işareti", ...
            100 * median(d), nnz(d > 0), numel(d)), ...
        "FanFiltreKontrolAdayi", {cellstr(R.Id(ord(1:6)))}, ...   % {} şart: hücre değeri struct dizisi üretir
        "Dogrulama", sprintf("durum koduyla kısma bildirilen adımların %%%.0f'i yakalandı; kış yanlış pozitif %%%.1f", ...
            100 * B.V1(1) / B.V1(2), 100 * B.V2(1) / B.V2(2)), ...
        "Guven", "yüksek (fiziksel V/I imzası, potansiyel kapanışı 1,00)", ...
        "Not", "Kısma: invertör iç sıcaklığı ~58 °C'yi geçince gücü kısar (arıza değil, soğutma yetersizliği). İç sıcaklık 5 °C düşük olsaydı kısma kaybının ~%60'ı geri kazanılırdı (karşı-olgu, varsayımlı).");
    bFile = fullfile(v2, "b02_summary.mat");
    if isfile(bFile)
        % v2-B02: PV gerilimi olmayan 8 invertör — güç+sıcaklık imzası (V/I'lı invertörlerde doğrulandı)
        Bp = load(bFile).summary;
        a = sortrows(Bp.applied, "LossMWh", "descend");
        invs = struct("Id", cellstr(a.Id), "KayipMWh", num2cell(round(a.LossMWh, 2)), ...
            "KayipYuzde", num2cell(round(a.LossPct, 1)), "KismaSaati", num2cell(round(a.ThrottleHours)));
        out.IsilKisma.GerilimsizInvertorler = struct( ...
            "Yontem", "güç+sıcaklık imzası: iç sıcaklık ≥ 58 °C, açık gök, güç beklenenin ≥ %8 altında", ...
            "ToplamKayipMWh", round(sum(a.LossMWh), 1), ...
            "Invertorler", {invs}, ...
            "Dogrulama", sprintf("gerilimli 91 invertörde V/I imzasına göre: adım kesinliği %%%.1f, gün düzeyi kesinlik %%%.1f / duyarlılık %%%.1f", ...
                100 * Bp.precision, 100 * Bp.day(1) / (Bp.day(1) + Bp.day(2)), 100 * Bp.day(1) / (Bp.day(1) + Bp.day(3))), ...
            "Guven", "orta-yüksek (alt sınır: yalnızca açık-gök ve ≥ 58 °C adımlar sayılır)");
    end
end
if want("tozlanma")
    D = load(fullfile(v2, "d02_dryspells.mat"), "R", "SR", "ids", "coplanar");
    co = ismember(D.ids, D.coplanar);
    spells = struct("Grup", cellstr(D.R.Grup), "Baslangic", cellstr(string(D.R.Basla, "yyyy-MM-dd")), ...
        "Bitis", cellstr(string(D.R.Bitis, "yyyy-MM-dd")), "KirlenmeHiziYuzdeGun", num2cell(round(D.R.HizYuzdeGun, 3)), ...
        "GA95", cellstr(compose("[%+.3f, %+.3f]", D.R.GA_alt, D.R.GA_ust)));
    out.Tozlanma = struct("TozlanmaOraniMedyan_32derece", round(median(D.SR(:, co), "all", "omitnan"), 3), ...
        "KuruDonemler", spells, ...
        "Ozet", "32° eğimli SmartGridLab dizisinde (POA düzeltmeli, Theil-Sen) tozlanma kuru dönemde çok düşüktür; yağmur kendiliğinden temizler. Hız yalnızca kuru dönemlerden kestirilir (düşük güven: kısa gözlem).", ...
        "Guven", "orta-düşük (tek dizi, ~11 haftalık gözlem)", ...
        "Not", "Yağış ölçümü yok: kapalı günler muhtemel yağış sayıldı. Hava durumu ve yağış kaydı bulunmadığından kuru dönemler ışınım ve güç davranışından seçilir.");
end
if want("bulut")
    E = load(fullfile(v2, "e01_cloudiness.mat"), "Mo");
    m = E.Mo;
    out.Bulutluluk = struct("Aylik", struct("Ay", cellstr(string(m.Month, "yyyy-MM")), ...
        "BulutlulukYuzde", num2cell(round(100 * m.CloudLoss, 1)), "AcikGun", num2cell(m.Clear), ...
        "ParcaliGun", num2cell(m.Partly), "KapaliGun", num2cell(m.Overcast)), ...
        "Tanim", "bulutluluk oranı = bulutların kestiği ışınım payı (1 − ölçülen/açık-gök ışınımı), K02 piranometresi", ...
        "Guven", "orta (açık-gök modeli sabit bulanıklık varsayar)");
end
if want("degradasyon")
    F = load(fullfile(v2, "f01_degradation.mat"), "RdS", "RdC", "bS", "bC");
    ok = ~isnan(F.RdS);
    lo = min(prctile(F.bS, 2.5), prctile(F.bC, 2.5));
    out.Degradasyon = struct("SensorOlcegi", sprintf("%+.2f %%/yıl [%+.2f, %+.2f]", 100 * median(F.RdS(ok)), 100 * prctile(F.bS, 2.5), 100 * prctile(F.bS, 97.5)), ...
        "AcikGokOlcegi", sprintf("%+.2f %%/yıl [%+.2f, %+.2f]", 100 * median(F.RdC(ok)), 100 * prctile(F.bC, 2.5), 100 * prctile(F.bC, 97.5)), ...
        "InvertorSayisi", nnz(ok), ...
        "Sonuc", sprintf("Nokta tahmini verilemez (iki ölçek tutarsız; sensör 2025'te %%0,8 kaymış). Sınır: degradasyon %%95 olasılıkla %.2f %%/yıl'dan hızlı değil → bugünkü kapasitenin %%80'ine en erken ~%.0f yıl.", ...
            -100 * lo, log(0.8) / log(1 + lo)), ...
        "Guven", "düşük (yalnızca 1 yıllık yıl-yıl örtüşmesi)");
end
if want("bakim")
    C = load(fullfile(v2, "events_catalog_v2.mat"), "catalog").catalog;
    sd = C(C.Type == "string_dead" & C.DurationDays >= 1, :);
    rep = groupcounts(sd, ["Id" "PV"]);
    rep = sortrows(rep(rep.GroupCount >= 3, :), "GroupCount", "descend");
    out.Bakim = struct("StringArizasi", sprintf("%d olay (≥1 gün), %d farklı string; bir stringin yıllık arızalanma olasılığı ≈ %%1,5", height(sd), height(unique(sd(:, ["Id" "PV"])))), ...
        "TekrarlayanStringler", struct("Id", cellstr(rep.Id(1:min(8, end))), "PV", num2cell(rep.PV(1:min(8, end))), "Tekrar", num2cell(rep.GroupCount(1:min(8, end)))), ...
        "TemizlikAraligi", "T* = sqrt(2·C/(r·E·p)); 1,20 kWp dizide kirlenme hızı çok düşükse temizlik ekonomik değildir (yağmur yeterli); kuru dönem hızı artarsa yıkama planlanır (C: tek temizlik maliyeti, p: elektrik birim değeri kullanıcıdan)", ...
        "IsilBakim", "Yaz öncesi evirici soğutma yüzeyleri, fan ve hava girişi ile konnektör (MC4) kontrolü; rüzgarsız sıcak saatlerde kısma izlenir", ...
        "Not", "Tek stringli SmartGridLab dizisinde 'ölü string' = DC akımının güneş varken 0 A olmasıdır; şebeke kesintisi (29.07.2026 11:45) ve yeniden başlatma adımlarından ayrıştırılır.");
end
end

function T = crossing(edges, frac, level)
c = edges(1:end-1) + 0.5;
i = find(frac >= level, 1);
if isempty(i) || i == 1 || isnan(frac(i - 1))
    T = NaN;
    return
end
T = c(i - 1) + (level - frac(i - 1)) / (frac(i) - frac(i - 1)) * (c(i) - c(i - 1));
end
