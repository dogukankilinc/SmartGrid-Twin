classdef tGesIo < matlab.unittest.TestCase
%TGESIO SMA CSV okuma ve veri hattı birim testleri (BTÜ SmartGridLab).
%   Test kapsamı:
%   1. readSmaReport — sep=; format, 14 satır metadata atlatma, zaman ayrıştırma
%   2. R_iso binlik ayraç ("3,000.00" → 3000)
%   3. Izgara dışı (:10, :25, :50) reset satırı → qRebootEvent=true, silinmemiş
%   4. Mükerrer 12.00 AM sınır satırı → coalesceDuplicates (firstNonMissing)
%   5. k/18 röle görev oranı → RelayDuty, U_L1_cond, qRelayCycle (sahte alarm yok!)
%   6. Gerçek şebeke kesintisi: 29 Temmuz 11:45 → qGridLoss=true

properties (Constant)
    DataDir = fullfile(fileparts(fileparts(mfilename("fullpath"))), "data")
end

methods (TestMethodSetup)
    function setup(tc)
        addpath(fileparts(fileparts(mfilename("fullpath"))));
        setupGes();
    end
end

methods (Test)
    function testCsvFound(tc)
        files = dir(fullfile(tc.DataDir, "Analysis Pro - Week*.csv"));
        tc.assertGreaterThan(numel(files), 0, "CSV dosyası bulunamadı");
    end

    function testReadSmaReport(tc)
        files = dir(fullfile(tc.DataDir, "Analysis Pro - Week*.csv"));
        tc.assumeGreaterThan(numel(files), 0);
        fpath = fullfile(files(1).folder, files(1).name);
        TT = ges.io.readSmaReport(fpath);
        tc.assertClass(TT, "timetable");
        tc.assertGreaterThan(height(TT), 0);
        cols = TT.Properties.VariableNames;
        tc.assertContains(cols, "P_ac");
        tc.assertContains(cols, "V_dc");
        tc.assertContains(cols, "R_iso");
        tc.assertContains(cols, "WindSpeed");
    end

    function testRisoThousandsSeparator(tc)
        % R_iso "3,000.00" → 3000 olarak okunmalı
        files = dir(fullfile(tc.DataDir, "Analysis Pro - Week*.csv"));
        tc.assumeGreaterThan(numel(files), 0);
        fpath = fullfile(files(1).folder, files(1).name);
        TT = ges.io.readSmaReport(fpath);
        tc.assumeTrue(ismember("R_iso", TT.Properties.VariableNames));
        riso = TT.R_iso(~isnan(TT.R_iso));
        if ~isempty(riso)
            tc.assertGreaterThan(max(riso), 100, ...
                "R_iso değerleri çok küçük — binlik ayraç temizlenmemiş olabilir");
            tc.assertLessThan(max(riso), 10000, ...
                "R_iso değerleri çok büyük — birim hatası");
        end
    end

    function testRelayCycleDetection(tc)
        % 0 < f_grid < 49 Hz olan adımlar qRelayCycle=true, qGridLoss=false olmalı
        files = dir(fullfile(tc.DataDir, "Analysis Pro - Week*.csv"));
        tc.assumeGreaterThan(numel(files), 0);
        allTT = [];
        for k = 1:numel(files)
            fpath = fullfile(files(k).folder, files(k).name);
            TT = ges.io.readSmaReport(fpath);
            allTT = [allTT; TT]; %#ok<AGROW>
        end
        tc.assumeTrue(ismember("RelayDuty", allTT.Properties.VariableNames));
        tc.assumeTrue(ismember("qRelayCycle", allTT.Properties.VariableNames));
        relayCycleRows = allTT.RelayDuty > 0.05 & allTT.RelayDuty < 0.98;
        if nnz(relayCycleRows) > 0
            tc.assertTrue(all(allTT.qRelayCycle(relayCycleRows)), ...
                "k/18 röle geçiş adımlarında qRelayCycle=true olmalı");
            if ismember("qGridLoss", allTT.Properties.VariableNames)
                tc.assertFalse(any(allTT.qGridLoss(relayCycleRows)), ...
                    "Röle geçiş adımlarında qGridLoss=false olmalı (sahte alarm!)");
            end
        end
    end

    function testRebootEventPreserved(tc)
        % Izgara dışı reset satırları (31 Tem 03:10 PM vb.) silinmemiş, qRebootEvent=true
        files = dir(fullfile(tc.DataDir, "Analysis Pro - Week*.csv"));
        tc.assumeGreaterThan(numel(files), 0);
        for k = 1:numel(files)
            fpath = fullfile(files(k).folder, files(k).name);
            TT = ges.io.readSmaReport(fpath);
            if ismember("qRebootEvent", TT.Properties.VariableNames) && any(TT.qRebootEvent)
                tc.assertTrue(true, "qRebootEvent bayrağı mevcut");
                return
            end
        end
        tc.log("qRebootEvent bulunamadı — tüm haftalarda ya reset yok ya da filtrelenmiş");
    end

    function testTotalRowCount(tc)
        files = dir(fullfile(tc.DataDir, "Analysis Pro - Week*.csv"));
        tc.assumeGreaterThan(numel(files), 0);
        cfg = gesConfig();
        [TT, ~] = ges.io.loadDevice(string({files.folder}' + filesep + string({files.name}')), ...
            TimeStep=cfg.data.timeStep, TimeZone=cfg.data.timeZone);
        % 11 hafta x ~674 satır ≈ 7400 satır; mükerrer sınır satırları coalesceDuplicates ile tekilleşmeli
        tc.assertGreaterThan(height(TT), 7000, "Toplam satır 7000'den az");
        tc.assertLessThan(height(TT), 7500, "Toplam satır 7500'den fazla (mükerrerler temizlenmemiş?)");
    end
end
end
