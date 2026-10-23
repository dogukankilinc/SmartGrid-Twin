function fleet = fleetFromEngine(eng)
%FLEETFROMENGINE Komşu / Öz-Akran karşılaştırması (3. görüş) için güç ve elektriksel ikiz matrisi.
%   fleet = ges.opinions.fleetFromEngine(eng) — eng: ges.runtime.ReplayEngine.
%   Çok eviricili filoda aynı kabindeki benzer yönelimli komşuların indislerini (Peers) kurar;
%   tek eviricili SmartGridLab (WR13TL22-8231) sisteminde ise Elektriksel İkiz (DC/AC/Şebeke L1/R_iso)
%   ve Nedensel Tarihsel Benzer-Gün Öz-Akran (Self-Peer k-NN) kanallarını hazırlar.
fleet.Times = eng.Times;
fleet.Ids = eng.Ids;
fleet.Pdc = eng.Pact;
fleet.Elev = eng.Elev;
fleet.Rising = [diff(eng.Elev) > 0; false];
n = numel(eng.Ids);
fleet.Capacity = nan(n, 1);
fleet.Rated = nan(n, 1);
fleet.NumStrings = nan(n, 1);
fleet.Peers = cell(n, 1);
for k = 1:n
    info = eng.Infos{k};
    if isempty(info)
        continue
    end
    fleet.Capacity(k) = info.Capacity;
    fleet.Rated(k) = info.Rated;
    fleet.NumStrings(k) = max(nnz(info.Installed), 1);
    if isfield(info, "Peers") && ~isempty(info.Peers)
        p = find(ismember(eng.Ids, string(info.Peers)));
        fleet.Peers{k} = p(p ~= k);
    else
        fleet.Peers{k} = [];
    end
end

% Tek evirici / zenginleştirilmiş elektriksel ikiz sinyalleri (ReplayEngine'de mevcutsa kopyasız bağlanır)
optFields = ["Pac" "PacSys" "Vdc" "Idc" "UL1" "Vgrid" "IL1" "Igrid" "Fgrid" "Riso" "Gref" "Gpoa" "Tmod" "Tcell" "Tamb" "Wind" "SchedP" "Pexp"];
for fn = optFields
    if isprop(eng, fn) || isfield(eng, fn)
        fleet.(fn) = eng.(fn);
    end
end

% Eğer tek eviriciyse ve ReplayEngine yalnızca temel alanları taşıyorsa, cihazın işlenmiş TT tablosunu
% önbelleğe bağla ki Katman 3A (L1 şebeke, V_dc, I_dc, R_iso) ve Katman 3B (Öz-Akran) %100 çalışsın
if n == 1 && ~isfield(fleet, "UL1")
    try
        if isprop(eng, "Cfg") || isfield(eng, "Cfg")
            cfg = eng.Cfg;
            fMat = fullfile(cfg.paths.processed, "train", "inverter", fleet.Ids(1) + ".mat");
            if ~isfile(fMat)
                files = dir(fullfile(cfg.paths.processed, "train", "inverter", "*.mat"));
                if ~isempty(files)
                    fMat = fullfile(files(1).folder, files(1).name);
                end
            end
            if isfile(fMat)
                S = load(fMat, "TT");
                fleet.SingleTT = S.TT;
            end
        end
    catch
    end
end
end
