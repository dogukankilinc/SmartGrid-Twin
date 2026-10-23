%% S00_CREATE_HOLDOUT  Test (hold-out) haftalık SMA CSV dosyalarını eğitim havuzundan ayırır.
% SmartGridLab'ta tek evirici (K01-INV01 / WR13TL22-8231) vardır; Huawei projesindeki gibi
% "cihaz dışlama" yapılamaz, bölme KRONOLOJİKTİR (cfg.split.testStart = 04 Ekim 2026):
%   Eğitim   : 27 Tem – 19 Eyl 2026 (8 hafta)   | Doğrulama: 20 Eyl – 03 Eki 2026 (2 hafta)
%   Test     : >= 04 Eki 2026 (cfg.split.holdoutFiles; 2 haftalık dosya)
% Test dosyaları data/ altından data_holdout/ altına KOPYALANIR (ham veri silinmez/taşınmaz);
% s01 eğitim havuzunu kurarken bu dosya adlarını dışlar, böylece test haftaları hiçbir
% eğitim, ölçekleme, kapasite veya eşik adımına sızmaz. Betik tekrar çalıştırılabilir.

clear;                                                  % betikler ortak çalışma alanını paylaşır
addpath(fileparts(fileparts(mfilename("fullpath"))));   % proje kökü
setupGes();
cfg = gesConfig();
src = cfg.paths.rawTrain;
dst = cfg.paths.rawHoldout;
if ~isfolder(dst)
    mkdir(dst);
end

holdNames = cfg.split.holdoutFiles(:);
copied = strings(0, 1);
missing = strings(0, 1);
for k = 1:numel(holdNames)
    from = fullfile(src, holdNames(k));
    to = fullfile(dst, holdNames(k));
    if ~isfile(from) && isfile(to)
        copied(end+1, 1) = holdNames(k); %#ok<AGROW>        % zaten ayrılmış
        continue
    end
    if ~isfile(from)
        missing(end+1, 1) = holdNames(k); %#ok<AGROW>
        continue
    end
    copyfile(from, to);
    copied(end+1, 1) = holdNames(k); %#ok<AGROW>
end
assert(isempty(missing), "Test dosyası bulunamadı: %s", strjoin(missing, "; "));

% Doğrulama: test paketi yalnızca testStart sonrasını kapsamalı; eğitim havuzu (test adları hariç)
% testStart öncesinde bitmeli.
catH = ges.io.scanReports(dst, ExpandSma=false);
assert(height(catH) == numel(holdNames), "Test paketinde %d yerine %d dosya var.", numel(holdNames), height(catH));
catT = ges.io.scanReports(src, ExpandSma=false);
catT = catT(~ismember(catT.File, fullfile(src, holdNames)) & ~endsWith(catT.File, holdNames), :);
[t0T, t1T] = spanOf(catT.File);
[t0H, t1H] = spanOf(catH.File);
fprintf("Eğitim havuzu: %d dosya, %s – %s\n", height(catT), string(min(t0T), "dd.MM.yyyy"), string(max(t1T), "dd.MM.yyyy"));
fprintf("Test paketi  : %d dosya, %s – %s\n", height(catH), string(min(t0H), "dd.MM.yyyy"), string(max(t1H), "dd.MM.yyyy"));
assert(max(t1T) < cfg.split.testStart + hours(1) + days(0) || max(dateshift(t1T, "start", "day")) <= cfg.split.testStart, ...
    "Eğitim havuzu test başlangıcından sonrasını içeriyor!");

manifest = [
    "# Test (hold-out) paketi"
    ""
    "Cihaz: " + cfg.split.holdoutInverter + "  (SMA WR13TL22-8231, tek evirici; bölme kronolojik)"
    "Oluşturulma: " + string(datetime("now", Format="yyyy-MM-dd HH:mm"))
    "Test başlangıcı: " + string(cfg.split.testStart, "yyyy-MM-dd")
    ""
    "Bu klasördeki haftalık dosyalar HİÇBİR eğitim, doğrulama, ölçekleme,"
    "kümeleme veya eşik ayarı adımında kullanılmaz. Sadece nihai uçtan uca"
    "değerlendirme içindir."
    ""
    "## data/ altından KOPYALANAN dosyalar (s01 eğitim havuzundan adıyla dışlar)"
    "- " + copied];
writelines(manifest, fullfile(dst, "MANIFEST.md"));
fprintf("Kopyalanan/ayrılan: %d dosya. Test paketi: %s\n", numel(copied), dst);

function [t0, t1] = spanOf(files)
% Her dosyanın ilk/son zaman damgası (ges.ingest.fileSpan).
t0 = NaT(numel(files), 1, TimeZone=string(missing)); t1 = t0;
for k = 1:numel(files)
    [a, b] = ges.ingest.fileSpan(files(k));
    t0(k) = a; t1(k) = b;
end
end
