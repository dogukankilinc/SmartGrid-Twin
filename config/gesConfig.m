function cfg = gesConfig()
%GESCONFIG BTÜ SmartGridLab GES yapay zeka asistanının merkezi yapılandırması.
%   cfg = gesConfig() proje yollarını, eğitim/doğrulama/test ayrımını ve
%   SmartGridLab (SMA Data Manager M + WR13TL22-8231 1.20 kWp tek fazlı evirici
%   + Satellite Sensor) saha sabitlerini döndürür.

root = string(fileparts(fileparts(mfilename("fullpath"))));

cfg.paths.root = root;
dataDir = fullfile(root, "data");
if isfolder(dataDir) && ~isempty(dir(fullfile(dataDir, "*.csv")))
    rawDir = dataDir;
else
    rawDir = root;
end
cfg.paths.dataRaw     = rawDir;
cfg.paths.rawTrain    = rawDir;
cfg.paths.rawHoldout  = fullfile(root, "data_holdout");
cfg.paths.dataHoldout = fullfile(root, "data_holdout");
cfg.paths.interim     = fullfile(root, "artifacts", "interim");
cfg.paths.processed   = fullfile(root, "artifacts", "processed");
cfg.paths.models      = fullfile(root, "artifacts", "models");
cfg.paths.scalogram   = fullfile(root, "scalogram_v2");
cfg.paths.anomaly     = fullfile(root, "artifacts", "processed", "train", "anomaly_v2");
cfg.paths.throttle    = fullfile(root, "artifacts", "v2", "throttle");
cfg.paths.throttleP   = fullfile(root, "artifacts", "v2", "throttle_p");
cfg.files.m1          = "m1_expected_power_v2eval.mat";
cfg.files.cnnDir      = "cnn_v2";

% SmartGridLab (BTÜ Mimar Sinan Yerleşkesi, Yıldırım/Bursa) saha ve dizi sabitleri
cfg.site.name            = "BTÜ SmartGridLab GES";
cfg.site.latitude        = 40.1878;
cfg.site.longitude       = 29.1289;
cfg.site.altitude        = 155;
cfg.site.panelTiltDeg    = 32;
cfg.site.panelAzimuthDeg = 180;
cfg.site.sensorTiltDeg   = 0;
cfg.site.sensorAzimuthDeg = 180;

% Üst düzey (top-level) kısayol sabitleri (tüm modüllerle tam uyumluluk için)
cfg.panelTiltDeg       = 32;
cfg.panelAzimuthDeg    = 180;
cfg.inverterCapacityKw = 1.20;
cfg.dcCapacityKwp      = 1.20;
cfg.nInverters         = 1;
cfg.nStringsDefault    = 1;
cfg.vmpNominal         = 195;
cfg.vocNominal         = 242;
cfg.impNominal         = 5.15;
cfg.rIsoWarnKOhm       = 1500;
cfg.rIsoCritKOhm       = 500;

% Veri ve donanım parametreleri
cfg.data.vendor          = "SMA";
cfg.data.timeStep        = minutes(15);
cfg.data.timeZone        = "Europe/Istanbul";
cfg.data.ratedAcPower    = 1.20;              % kW, SMA Sunny Boy WR13TL22-8231
cfg.data.dcCapacityKwp   = 1.20;              % kWp, P_ac / P_ac_spec = 1.200 kWp
cfg.data.numPhases       = 1;                 % Tek faz (L1)
cfg.data.numMppts        = 1;
cfg.data.numStrings      = 1;
cfg.data.vmpNominal      = 195;               % V
cfg.data.vocNominal      = 242;               % V
cfg.data.impNominal      = 5.15;              % A
cfg.data.rIsoWarnKOhm    = 1500;              % kOhm (sabah nem/çiğ uyarı eşiği)
cfg.data.rIsoCritKOhm    = 500;               % kOhm (kritik yalıtım arızası eşiği)
cfg.data.meteoCabins     = 1;                 % K01-METEO (SmartGridLab & Satellite Sensor)
cfg.data.primaryMeteo    = "K01";

% Sızıntısız kronolojik blok bölmesi (Tek evirici: 27 Tem – 18 Eki 2026, 11 hafta)
% Eğitim: 27 Temmuz – 19 Eylül 2026 | Doğrulama: 20 Eylül – 03 Ekim 2026 | Test: >= 04 Ekim 2026
cfg.split.mode            = "temporal";
cfg.split.holdoutDevices  = strings(0, 1);    % Cihaz dışlama yok (tek evirici K01-INV01)
cfg.split.holdoutInverter = "K01-INV01";
cfg.split.holdoutCabin    = 1;
cfg.split.validationStart = datetime(2026, 9, 20, 0, 0, 0, TimeZone="Europe/Istanbul");
cfg.split.testStart       = datetime(2026, 10, 4, 0, 0, 0, TimeZone="Europe/Istanbul");
cfg.split.holdoutFiles    = [
    "Analysis Pro - Week - Data Manager Smart Grid Laboratory - 2026-10-04 - 2026-10-10.csv"
    "Analysis Pro - Week - Data Manager Smart Grid Laboratory - 2026-10-11 - 2026-10-17.csv"
    ];

% Katmanlar: ÇEKİRDEK her zaman çalışır; ARAŞTIRMA (CNN, LLM/VLM, federe) isteğe bağlıdır.
cfg.layers.research = true;
end
