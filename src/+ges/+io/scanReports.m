function catalog = scanReports(root, opts)
%SCANREPORTS Bir klasör ağacındaki tüm SMA Sunny Portal ve Huawei raporlarını kataloglar.
%   catalog = ges.io.scanReports(root) her rapor dosyası için File, Folder,
%   Bytes ve ges.io.parseDeviceName sütunlarını içeren bir tablo döndürür.
%   Birleşik SMA Sunny Portal dosyaları (Kind == "sma_combined") hem evirici
%   (K01-INV01 / WR13TL22-8231), hem meteoroloji (K01-METEO), hem de tesis
%   sayacı (PLANT) verilerini içerdiğinden otomatik olarak bu 3 mantıksal
%   cihaz kaydına genişletilir.

arguments
    root (1,1) string {mustBeFolder}
    opts.Exclude (:,1) string = strings(0,1)
    opts.ExpandSma (1,1) logical = true
end

% Önce doğrudan root içindeki CSV'leri, yoksa alt klasörleri tara
files = [dir(fullfile(root, "Analysis Pro*.csv")); dir(fullfile(root, "Report_*.csv"))];
if isempty(files)
    files = [dir(fullfile(root, "**", "Analysis Pro*.csv")); dir(fullfile(root, "**", "Report_*.csv"))];
end
if isempty(files)
    files = dir(fullfile(root, "*.csv"));
end

% Aynı tam dosya yoluna sahip mükerrer dir sonuçlarını tekilleştir
if ~isempty(files)
    fullPaths = fullfile(string({files.folder})', string({files.name})');
    [~, keepIdx] = unique(fullPaths, "stable");
    files = files(keepIdx);
end

n = numel(files);
if n == 0
    catalog = table(strings(0,1), strings(0,1), zeros(0,1), strings(0,1), strings(0,1), ...
        strings(0,1), nan(0,1), nan(0,1), nan(0,1), ...
        VariableNames=["File" "Folder" "Bytes" "Device" "Id" "Kind" "Cabin" "Inv" "StringTag"]);
    return
end

File = strings(n,1);
Folder = strings(n,1);
Bytes = zeros(n,1);
for k = 1:n
    File(k) = fullfile(files(k).folder, files(k).name);
    [~, Folder(k)] = fileparts(files(k).folder);
    Bytes(k) = files(k).bytes;
end

meta = ges.io.parseDeviceName(string({files.name})');
catalog = [table(File, Folder, Bytes), meta];

% Adından tanınmayan dosyalar içerikten sınıflandırılır
for k = find(catalog.Kind == "unknown")'
    kind = ges.io.classifyByHeader(catalog.File(k));
    if kind == "plant"
        catalog.Kind(k) = "plant";
        catalog.Id(k) = "PLANT";
    elseif kind == "sma_combined"
        catalog.Kind(k) = "sma_combined";
        catalog.Device(k) = "WR13TL22-8231";
        catalog.Id(k) = "K01-INV01";
        catalog.Cabin(k) = 1;
        catalog.Inv(k) = 1;
        catalog.StringTag(k) = 1;
    elseif kind == "inverter"
        catalog.Kind(k) = "inverter";
    elseif kind == "meteo"
        catalog.Kind(k) = "meteo";
    end
end

% Birleşik SMA raporlarını 3 mantıksal cihaza (inverter, meteo, plant) genişlet
if opts.ExpandSma && any(catalog.Kind == "sma_combined")
    outRows = table();
    for k = 1:height(catalog)
        row = catalog(k, :);
        if row.Kind == "sma_combined"
            rInv = row;
            rInv.Kind = "inverter";
            rInv.Device = "WR13TL22-8231";
            rInv.Id = "K01-INV01";
            rInv.Cabin = 1;
            rInv.Inv = 1;
            rInv.StringTag = 1;

            rMet = row;
            rMet.Kind = "meteo";
            rMet.Device = "SmartGridLab-Meteo";
            rMet.Id = "K01-METEO";
            rMet.Cabin = 1;
            rMet.Inv = NaN;
            rMet.StringTag = NaN;

            rPlt = row;
            rPlt.Kind = "plant";
            rPlt.Device = "SmartGridLab";
            rPlt.Id = "PLANT";
            rPlt.Cabin = 1;
            rPlt.Inv = NaN;
            rPlt.StringTag = NaN;

            outRows = [outRows; rInv; rMet; rPlt]; %#ok<AGROW>
        else
            outRows = [outRows; row]; %#ok<AGROW>
        end
    end
    catalog = outRows;
end

drop = ismember(catalog.Device, opts.Exclude) | ismember(catalog.Id, opts.Exclude);
if any(drop)
    warning("ges:io:excludedDevices", "%d dosya hariç tutuldu: %s", ...
        nnz(drop), strjoin(unique(catalog.Device(drop)), ", "));
    catalog(drop,:) = [];
end
end
