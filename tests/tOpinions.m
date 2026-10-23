classdef tOpinions < matlab.unittest.TestCase
%TOPINIONS 3-Görüş uzlaşı sistemi birim testleri (SmartGrid-Twin, tek evirici).
%   Test kapsamı:
%   1. consensus: boş ajan listesinde "veri_yok" döner
%   2. sensorOpinion: qGridLoss=true → "grid_event" kararı
%   3. peerOpinion: tek eviricili sistemde Available=true (elektriksel ikiz veya öz-akran k-NN)
%   4. classes: 6 sınıf, doğru sıra
%   5. consensus: sensör hard=true çelişkiyi geçersiz kılar

methods (TestMethodSetup)
    function setup(tc)
        addpath(fileparts(fileparts(mfilename("fullpath"))));
        setupGes();
    end
end

methods (Test)
    function testClasses(tc)
        c = ges.opinions.classes();
        tc.assertEqual(numel(c), 6);
        tc.assertEqual(c(1), "grid_event");
        tc.assertEqual(c(end), "healthy");
    end

    function testConsensusEmpty(tc)
        ops = struct("Available", false, "Key", "sensor", ...
            "Stance", zeros(1,6), "Label", "healthy", "Level", "none", ...
            "Check", false, "Summary", "");
        f = ges.opinions.consensus(ops);
        tc.assertEqual(f.Label, "veri_yok");
    end

    function testSensorGridEvent(tc)
        % Tek sensor, qGridLoss=true → grid_event
        cls = ges.opinions.classes();
        stance = zeros(1, numel(cls));
        stance(cls == "grid_event") = 1;
        op = struct("Available", true, "Key", "sensor", ...
            "Stance", stance, "Label", "grid_event", "Level", "uzlasi", ...
            "Hard", true, "Check", false, "Summary", "L1=0V f=0Hz", ...
            "Scores", stance, "Evidence", struct());
        f = ges.opinions.consensus(op);
        tc.assertEqual(f.Label, "grid_event");
    end

    function testPeerOpinionSingleInverter(tc)
        % Tek eviricili sistemde peerOpinion Available=true dönmeli
        cfg   = gesConfig();
        files = dir(fullfile(cfg.paths.rawTrain, "Analysis Pro - Week*.csv"));
        tc.assumeGreaterThan(numel(files), 0);
        fpath = fullfile(files(1).folder, files(1).name);
        TT    = ges.io.readSmaReport(fpath);
        TT    = TT(~isnan(TT.P_ac), :);
        tc.assumeGreaterThan(height(TT), 50);
        % Geçerli bir günü seç
        d     = dateshift(TT.Time(round(end/2)), "start", "day");
        info  = struct("Capacity",1.20,"Rated",1.20,"NumStrings",1,"Peers",strings(0,1));
        fleet = struct("Ids","K01-INV01","Pdc",TT.P_ac,"Times",TT.Time,"Capacity",1.20, ...
            "Rated",1.20,"NumStrings",1,"Peers",{{[]}},"SingleTT",TT);
        op = ges.opinions.peerOpinion(fleet, TT, info, 1, d);
        tc.assertTrue(op.Available, "Tek eviricili sistemde peerOpinion Available=true bekleniyor");
    end

    function testConsensusHealthy(tc)
        cls = ges.opinions.classes();
        stance = zeros(1, numel(cls));
        stance(cls == "healthy") = 1;
        op1 = struct("Available",true,"Key","sensor","Stance",stance,"Label","healthy", ...
            "Level","uzlasi","Hard",false,"Check",false,"Summary","","Scores",stance,"Evidence",struct());
        op2 = op1; op2.Key = "peer";
        f = ges.opinions.consensus([op1 op2]);
        tc.assertEqual(f.Label, "healthy");
        tc.assertFalse(f.Check);
    end
end
end
