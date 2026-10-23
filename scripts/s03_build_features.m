%% S03_BUILD_FEATURES  Faz 1b-ii: Kalite bayrakları, POA transpozisyonu, Faiman sıcaklığı ve türetilmiş öznitelikler.
% SmartGridLab (BTÜ, SMA WR13TL22-8231 1.20 kWp, Satellite Sensor) için uyarlanmış.
%
% Girdi : artifacts/interim/{train,holdout}, orientation.mat (s02)
% Çıktı :
%   artifacts/processed/shared/meteo_ref.mat    — tesis referans meteorolojisi (G_poa, T_cell_dyn, v_b.)
%   artifacts/processed/{train,holdout}/inverter/K01-INV01.mat
%         TT   : 15 dk işlenmiş zaman serisi + tüm kanonik/alias sütunlar + bayraklar
%         D    : günlük özet (ges.prep.dailySummary)
%         info : kapasite, nominal güç, kurulu string sayısı, komşular (tek evirici → kendisi)

clear;
addpath(fileparts(fileparts(mfilename("fullpath"))));
setupGes();
cfg = gesConfig();
interim   = cfg.paths.interim;
processed = cfg.paths.processed;
isTrainTime = @(t) t < cfg.split.validationStart;

%% 1) Güneş geometrisi, uydu sensörü, POA transpozisyonu
O = load(fullfile(interim, "train", "orientation.mat"));
orientation = O.orientation;

M = load(fullfile(interim, "train", "meteo", "K01-METEO.mat")).TT;
t = M.Time;
geo = ges.solar.solarGeometry(t, cfg.site);
night = geo.Elevation < -2;

% GHI -> G_poa (HDKR + ASHRAE IAM, beta≈32°)
arrRow = orientation(orientation.Id == "K01-INV01", :);
tiltArr = arrRow.Tilt; azArr = arrRow.Azimuth;
gPoa = ges.solar.transposeGhiToPoa(M.G, geo.Zenith, geo.Azimuth, ...
    tiltArr, azArr, geo.GhiCs, geo.DhiCs);
gPoa(night) = 0;

% Meteo kalite bayrağı
[vMeteo, reasonM] = ges.prep.meteoQuality(M.G, geo.PoaCs, geo.Elevation);
kc = M.G ./ max(geo.PoaCs, 1);  kc(geo.PoaCs < 30) = NaN;

% Faiman dinamik hücre sıcaklığı (WindSpeed kullanır — CSV'de Sütun 19)
[tCellDyn, tCellVdc, deltaTWind] = ges.solar.cellTemperatureFaiman( ...
    M.T_amb, gPoa, M.WindSpeed, cfg);

% Referans meteoroloji objesi
meteoRef = timetable(t, M.G, gPoa, kc, geo.Elevation, geo.Azimuth, ...
    M.T_amb, M.T_mod, M.WindSpeed, tCellDyn, deltaTWind, vMeteo, ...
    VariableNames=["G_horiz" "G_poa" "Kc" "Elevation" "SunAzimuth" ...
    "T_amb" "T_mod" "WindSpeed" "T_cell_dyn" "DeltaT_wind" "MeteoOk"]);
sharedDir = fullfile(processed, "shared");
if ~isfolder(sharedDir); mkdir(sharedDir); end
save(fullfile(sharedDir, "meteo_ref.mat"), "meteoRef");
fprintf("Referans meteoroloji kaydedildi (%d adım).\n", height(meteoRef));

%% 2) Eğitim ve holdout invertör dosyalarını işle
splits = ["train"];
if isfolder(fullfile(interim, "holdout")); splits(end+1) = "holdout"; end

for sp = splits
    invDir = fullfile(interim, sp, "inverter");
    if ~isfolder(invDir); continue; end
    invFiles = dir(fullfile(invDir, "*.mat"));
    for fi = 1:numel(invFiles)
        fname = fullfile(invFiles(fi).folder, invFiles(fi).name);
        S = load(fname, "TT");
        TT = S.TT;
        id = string(erase(invFiles(fi).name, ".mat"));
        fprintf("[%s] %s işleniyor...\n", sp, id);

        % Meteo ile eşleştir
        Msync = retime(meteoRef, TT.Time, "linear");

        % Kanonik sütun adları + alias bağlantıları (Ajan 1 şeması)
        if ~ismember("P_dc", TT.Properties.VariableNames) && ...
                ismember("V_dc", TT.Properties.VariableNames) && ismember("I_dc", TT.Properties.VariableNames)
            TT.P_dc = TT.V_dc .* TT.I_dc / 1000;
        end
        if ismember("P_dc", TT.Properties.VariableNames) && ismember("P_ac", TT.Properties.VariableNames)
            TT.Eff     = TT.P_ac ./ max(TT.P_dc, 1e-4);
            TT.Eta_inv = TT.Eff;
        end
        % Şebeke alias
        if ismember("U_L1", TT.Properties.VariableNames)
            if ~ismember("V_grid", TT.Properties.VariableNames); TT.V_grid = TT.U_L1; end
            if ~ismember("U_ab",   TT.Properties.VariableNames); TT.U_ab   = TT.U_L1; end
        end
        if ismember("I_L1", TT.Properties.VariableNames)
            if ~ismember("I_grid", TT.Properties.VariableNames); TT.I_grid = TT.I_L1; end
            if ~ismember("I_a",    TT.Properties.VariableNames); TT.I_a    = TT.I_L1; end
        end
        % RelayDuty ve koşullu şebeke gerilimi (statusFlags zaten yazabilir)
        if ismember("f_grid", TT.Properties.VariableNames) && ~ismember("RelayDuty", TT.Properties.VariableNames)
            TT.RelayDuty = min(max(TT.f_grid / 50, 0), 1);
            TT.U_L1_cond = TT.U_L1 ./ max(TT.RelayDuty, 1/18);
            TT.U_L1_cond(TT.RelayDuty < 0.05) = NaN;
        end
        % Görünür güç, güç faktörü, reaktif güç
        if ismember("U_L1", TT.Properties.VariableNames) && ismember("I_L1", TT.Properties.VariableNames)
            TT.S_ac = TT.U_L1 .* TT.I_L1 / 1000;   % kVA alias P_grid_app
            TT.P_grid_app = TT.S_ac;
            TT.PF   = TT.P_ac ./ max(TT.S_ac, 1e-4);
            TT.PF(TT.S_ac < 0.01) = NaN;
            TT.Q_ac = sqrt(max(TT.S_ac.^2 - TT.P_ac.^2, 0));
            TT.Q_grid = TT.Q_ac;
        end
        % Meteo sütunlarını TT'ye ekle (henüz yoksa)
        for fn = ["G_poa" "T_cell_dyn" "DeltaT_wind" "T_cell_faiman" "T_cell_vdc"]
            if ~ismember(fn, TT.Properties.VariableNames) && ismember(fn, Msync.Properties.VariableNames)
                TT.(fn) = Msync.(fn);
            end
        end
        if ~ismember("G_ref",  TT.Properties.VariableNames) && ismember("G_poa",TT.Properties.VariableNames)
            TT.G_ref = TT.G_poa;
        end

        % Günlük özet
        D = ges.prep.dailySummary(TT, cfg.site);

        % info struct (kapasite, nominal, tek string)
        info.Id          = id;
        info.Capacity    = cfg.dcCapacityKwp;    % kWp
        info.Rated       = cfg.inverterCapacityKw;
        info.Installed   = ones(1, cfg.nStringsDefault, "logical");
        info.NumStrings  = cfg.nStringsDefault;
        info.Vmp         = cfg.vmpNominal;
        info.Voc         = cfg.vocNominal;
        info.Imp         = cfg.impNominal;
        info.Peers       = strings(0,1);  % tek evirici → komşu yok
        info.Tilt        = tiltArr;
        info.Azimuth     = azArr;

        % Kaydet
        outDir = fullfile(processed, sp, "inverter");
        if ~isfolder(outDir); mkdir(outDir); end
        save(fullfile(outDir, id + ".mat"), "TT", "D", "info");
        fprintf("  → %s (satır=%d, sütun=%d)\n", id, height(TT), width(TT));
    end
end

fprintf("\ns03 tamamlandı. İşlenen cihazlar artifacts/processed altında.\n");
