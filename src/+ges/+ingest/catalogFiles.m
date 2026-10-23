function catalog = catalogFiles(files, kinds)
%CATALOGFILES Yüklenen ham rapor dosyalarının cihaz kataloğu (Veri sayfası ve işleme hattı için).
%   catalog = ges.ingest.catalogFiles(files, kinds) — Birleşik SMA Sunny Portal dosyaları
%   (Kind == "sma_combined") algılandığında otomatik olarak hem "inverter" (K01-INV01),
%   hem "meteo" (K01-METEO), hem de "plant" (PLANT) kayıtlarını üretir.

arguments
    files (:,1) string
    kinds (:,1) string = repmat("", numel(files), 1)
end
[~, nm, ext] = fileparts(files);
names = nm + ext;
meta = ges.io.parseDeviceName(names);
Note = strings(numel(files), 1);
kindTr = dictionary(["sma_combined" "meteo" "inverter" "logger" "loggerControl" "plant" "unknown"], ...
    ["birleşik SMA raporu" "meteoroloji" "invertör" "SmartLogger" "SmartLogger" "tesis sayacı" "bilinmiyor"]);

outFiles = strings(0, 1);
outNames = strings(0, 1);
outMeta = table();
outNote = strings(0, 1);

for k = 1:numel(files)
    rowMeta = meta(k, :);
    if rowMeta.Kind == "unknown" && isfile(files(k))
        h = ges.io.classifyByHeader(files(k));
        if h ~= "unknown"
            rowMeta.Kind = h;
        elseif kinds(k) ~= ""
            rowMeta.Kind = kinds(k);
            Note(k) = "tür seçilen düğmeden";
        end
        if rowMeta.Kind == "plant"
            rowMeta.Id = "PLANT";
        end
    end

    if rowMeta.Kind == "sma_combined"
        noteSma = "Birleşik SMA Sunny Portal raporu (Evirici + Sensör + Sistem)";
        rInv = rowMeta; rInv.Kind = "inverter"; rInv.Device = "WR13TL22-8231"; rInv.Id = "K01-INV01"; rInv.Cabin = 1; rInv.Inv = 1; rInv.StringTag = 1;
        rMet = rowMeta; rMet.Kind = "meteo";    rMet.Device = "SmartGridLab-Meteo"; rMet.Id = "K01-METEO"; rMet.Cabin = 1; rMet.Inv = NaN; rMet.StringTag = NaN;
        rPlt = rowMeta; rPlt.Kind = "plant";    rPlt.Device = "SmartGridLab"; rPlt.Id = "PLANT"; rPlt.Cabin = 1; rPlt.Inv = NaN; rPlt.StringTag = NaN;

        outFiles = [outFiles; repmat(files(k), 3, 1)]; %#ok<AGROW>
        outNames = [outNames; repmat(names(k), 3, 1)]; %#ok<AGROW>
        outMeta  = [outMeta; rInv; rMet; rPlt]; %#ok<AGROW>
        outNote  = [outNote; repmat(noteSma, 3, 1)]; %#ok<AGROW>
        continue
    end

    want = kinds(k);
    if want ~= "" && rowMeta.Kind ~= want && ~(want == "logger" && rowMeta.Kind == "loggerControl")
        Note(k) = "dosya adına göre " + kindTr(rowMeta.Kind) + " olarak tanındı";
    end
    if rowMeta.Kind == "unknown"
        Note(k) = "tanınmadı: SMA Analysis Pro CSV veya Report_Kabin<N>-INV<NN>_… biçiminde olmalı";
    end

    outFiles(end+1, 1) = files(k); %#ok<AGROW>
    outNames(end+1, 1) = names(k); %#ok<AGROW>
    outMeta = [outMeta; rowMeta]; %#ok<AGROW>
    outNote(end+1, 1) = Note(k); %#ok<AGROW>
end

catalog = [table(outFiles, outNames, VariableNames=["File" "Name"]), outMeta, table(outNote, VariableNames="Note")];
end
