%% A01_DATA_INVENTORY  SmartGridLab veri envanteri ve temel istatistikler.
% 11 haftalık SMA CSV dosyasını tarar; satır sayısı, eksik veri oranı,
% hafta boşlukları, özel olaylar (reset, relay-cycle, grid-loss) ve
% 21 sütunun özet istatistiklerini raporlar.

clear;
addpath(fileparts(fileparts(fileparts(mfilename("fullpath")))));
setupGes();
cfg = gesConfig();

catalog = ges.io.scanReports(cfg.paths.rawTrain);
fprintf("Bulunan kayıt dosyası sayısı: %d\n\n", height(catalog));
disp(catalog(:, ["Id" "Kind" "File"]));

% Tüm CSV dosyalarını birleştirerek yükle
[TT, report] = ges.io.loadDevice(catalog.File, ...
    TimeStep=cfg.data.timeStep, TimeZone=cfg.data.timeZone);
fprintf("\nToplam yüklenen adım: %d  (%.1f gün)\n", height(TT), height(TT)*15/1440);
fprintf("Tarih aralığı: %s — %s\n", string(TT.Time(1),"yyyy-MM-dd HH:mm"), ...
    string(TT.Time(end),"yyyy-MM-dd HH:mm"));

% Hafta boşluğu tespiti (10–15 Ağustos)
allDays  = dateshift(TT.Time, "start", "day");
dayUniq  = unique(allDays);
dayDiffs = diff(dayUniq);
gapIdx   = find(dayDiffs > caldays(1));
if ~isempty(gapIdx)
    fprintf("\n⚠ Gün boşlukları tespit edildi:\n");
    for g = 1:numel(gapIdx)
        fprintf("  %s → %s  (%d gün)\n", string(dayUniq(gapIdx(g)),"yyyy-MM-dd"), ...
            string(dayUniq(gapIdx(g)+1),"yyyy-MM-dd"), days(dayDiffs(gapIdx(g))));
    end
end

% Olay bayrakları özeti
cols21 = TT.Properties.VariableNames;
fprintf("\n--- Sütun Doluluk Raporu ---\n");
for fn = string(cols21)
    v = TT.(fn);
    if isnumeric(v) || islogical(v)
        pct = 100 * sum(~isnan(double(v))) / height(TT);
        fprintf("  %-35s  dolu=%%%.1f  min=%.3g  max=%.3g\n", fn, pct, ...
            min(v,[],"all","omitmissing"), max(v,[],"all","omitmissing"));
    end
end

% Özel olay sayıları
if ismember("qRebootEvent", TT.Properties.VariableNames)
    fprintf("\nqRebootEvent (yeniden başlatma): %d adım\n", nnz(TT.qRebootEvent));
end
if ismember("qRelayCycle", TT.Properties.VariableNames)
    fprintf("qRelayCycle (k/18 röle geçişi): %d adım\n", nnz(TT.qRelayCycle));
end
if ismember("qGridLoss", TT.Properties.VariableNames)
    fprintf("qGridLoss (gerçek şebeke kesintisi): %d adım\n", nnz(TT.qGridLoss));
end
if ismember("qLowInsulation", TT.Properties.VariableNames)
    fprintf("qLowInsulation (R_iso < %g kOhm): %d adım\n", cfg.rIsoWarnKOhm, nnz(TT.qLowInsulation));
end

% Haftalık özet tablo
fprintf("\n--- Haftalık Üretim Özeti ---\n");
if ismember("P_ac", TT.Properties.VariableNames)
    wk = week(TT.Time);
    yr = year(TT.Time);
    [g, uw] = findgroups([yr wk]);
    wkE  = splitapply(@(p) sum(p,"omitmissing")*0.25, TT.P_ac, g);
    wkMx = splitapply(@(p) max(p,[],"omitmissing"), TT.P_ac, g);
    wkN  = splitapply(@sum, ~isnan(TT.P_ac), g);
    T = table(uw, wkN, round(wkE,2), round(wkMx,3), ...
        VariableNames=["YilHafta" "AktifAdim" "Uretim_kWh" "MaxGuc_kW"]);
    disp(T);
    fprintf("TOPLAM üretim: %.1f kWh  /  %d hafta  (PR hesabı için G_poa gereklidir)\n", ...
        sum(wkE), numel(unique(wk)));
end
