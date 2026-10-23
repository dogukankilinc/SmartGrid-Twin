function v = coreCases(part, env)
%CORECASES Regresyon testlerinin "altın" (golden) değerlerini üreten sabit vakalar.
%   v = coreCases(part, env) — env: struct(cfg, eng, fleet) (tCoreRegression/setupOnce veya makeGolden).
%   Aynı fonksiyon hem altın değerleri kaydetmek (makeGolden) hem de testte yeniden hesaplamak için
%   kullanılır; böylece test ile kayıt arasında kod farkı olamaz. Vakalar bilerek küçük tutuldu (~1 dk).
%   part:
%     "assess"    — 20.05.2025 15:00'te tesis değerlendirmesi (anlık/günlük/haftalık durum sayıları, enerji, kayıplar)
%     "decisions" — 4 invertör × Mayıs 2025: sensör / komşu / uzlaşı kararları (çekirdek mod, CNN yok)
%     "visual"    — aynı invertörlerin Mayıs ilk 5 günü: çok etiketli CNN olasılıkları (araştırma katmanı)
%     "m1"        — beklenen güç doğruluğu (Mayıs 2025, sağlıklı ve geçerli adımlar, kapasiteye göre nMAE)
%     "thermal"   — K02-INV07 ısıl ikiz katsayıları (yalnız 01.05.2025 öncesi veriyle)
tz = env.cfg.data.timeZone;
ids = ["K02-INV07" "K15-INV11" "K03-INV46" "K12-INV05"];   % string+kısma · gizli string · gerilimsiz (B02) · K12
may0 = datetime(2025, 5, 1, TimeZone=tz);
may1 = datetime(2025, 6, 1, TimeZone=tz);
switch part
    case "assess"
        env.eng.seek(datetime(2025, 5, 20, 15, 0, 0, TimeZone=tz));
        names = ges.anomaly.stateNames();
        for h = ["instant" "day" "week"]
            A = env.eng.assess(h);
            v.(h).StateCounts = arrayfun(@(s) nnz(A.State == s), names);
            v.(h).Eact = sum(A.Eact);
            v.(h).Eexp = sum(A.Eexp);
            v.(h).Losses = [sum(A.LossThermal) sum(A.LossDead) sum(A.LossGrid) sum(A.LossOther)];
            v.(h).Kd = A.Plant.Kd;
        end
    case "decisions"
        T = ges.opinions.dayTable(env.cfg, env.fleet, may0, may1, Ids=ids, Verbose=false);
        v = table(T.Id, T.Day, string(arrayfun(@(o) o.Label, T.O1)), string(arrayfun(@(o) o.Label, T.O3)), ...
            string(arrayfun(@(c) c.Label, T.C)), string(arrayfun(@(c) c.Level, T.C)), T.PeerF.Ratio, ...
            VariableNames=["Id" "Day" "Sensor" "Peer" "Consensus" "Level" "PeerRatio"]);
    case "visual"
        M = load(fullfile(env.cfg.paths.models, "cnn_ml", "resnet18_ml.mat"), "net", "thr", "classesOut", "inputSize");
        norm = load(fullfile(env.cfg.paths.models, "scalogram_norm.mat"));
        X = zeros(64, 64, 3, 0, "uint8");
        key = strings(0, 1);
        for id = ids
            S = load(fullfile(env.cfg.paths.processed, "train", "inverter", id + ".mat"), "TT", "info");
            A = load(fullfile(env.cfg.paths.anomaly, id + ".mat"), "Steps").Steps;
            for d = may0 + days(0:4)
                [sig, ok] = ges.scalogram.dailySignals(S.TT, A, S.info.Capacity, d);
                if ok
                    X(:, :, :, end+1) = ges.scalogram.makeImages(norm.fb, sig, norm.scale); %#ok<AGROW>
                    key(end+1) = id + "|" + string(d, "yyyy-MM-dd"); %#ok<AGROW>
                end
            end
        end
        P = predict(M.net, dlarray(single(imresize(X, M.inputSize(1:2))), "SSCB"));
        v = struct("Key", key, "Probs", double(extractdata(P))', "Thr", M.thr, "Classes", M.classesOut);
    case "m1"
        % v2-C01 ile AYNI tanım: ges.model.m1Features "Healthy" maskesi (aydınlık, birincil meteo, şebekede, arıza/
        % kısma kodu yok, kırpma yok, ölü string yok …) ve kısılmamış adımlar (V/I imzası; imzasız invertörde
        % iç sıcaklık > 56 °C dışlanır); hata = |beklenen (çalışan stringler) − P_dc| / kapasite, Mayıs 2025.
        bundle = load(fullfile(env.cfg.paths.models, env.cfg.files.m1)).bundle;
        nmae = nan(numel(ids), 1);
        for i = 1:numel(ids)
            S = load(fullfile(env.cfg.paths.processed, "train", "inverter", ids(i) + ".mat"), "TT", "info");
            TT = S.TT;
            thrFile = fullfile(env.cfg.paths.throttle, ids(i) + ".mat");
            if isfile(thrFile)
                Th = load(thrFile, "Time", "Throttled");
                [tf, loc] = ismember(TT.Time, Th.Time);
                TT.qThrottle = false(height(TT), 1);
                TT.qThrottle(tf) = Th.Throttled(loc(tf));
            else
                TT.qThrottle = TT.T_cab > 56 & TT.Elevation > 15;
            end
            f = bundle.Fingerprints(bundle.Fingerprints.Id == ids(i), :);
            [~, ~, aux] = ges.model.m1Features(TT, S.info, struct("AmPm", f.AmPm, "Vmean", mean(S.info.Vmppt), "Cabin", f.Cabin));
            A = load(fullfile(env.cfg.paths.anomaly, ids(i) + ".mat"), "Steps").Steps;
            [tf, loc] = ismember(TT.Time, A.Time);
            pw = nan(height(TT), 1);
            pw(tf) = A.PdcWork_exp(loc(tf));
            ok = aux.Healthy & ~TT.qThrottle & TT.Time >= may0 & TT.Time < may1 & ~isnan(pw);
            nmae(i) = mean(abs(pw(ok) - TT.P_dc(ok))) / S.info.Capacity;
        end
        v = table(ids', nmae, VariableNames=["Id" "nMAE"]);
    case "thermal"
        id = "K02-INV07";
        TT = load(fullfile(env.cfg.paths.processed, "train", "inverter", id + ".mat"), "TT").TT;
        A = load(fullfile(env.cfg.paths.anomaly, id + ".mat"), "Steps").Steps;
        [tf, loc] = ismember(TT.Time, A.Time);
        pwork = nan(height(TT), 1);
        pwork(tf) = A.PdcWork_exp(loc(tf));
        Th = load(fullfile(env.cfg.paths.throttle, id + ".mat"), "Time", "Throttled", "Valid", "LossKw");
        [tf, loc] = ismember(TT.Time, Th.Time);
        thr = false(height(TT), 1);
        ev = false(height(TT), 1);
        loss = zeros(height(TT), 1);
        thr(tf) = Th.Throttled(loc(tf));
        ev(tf) = Th.Valid(loc(tf));
        loss(tf) = double(Th.LossKw(loc(tf)));
        v = ges.forecast.fitThermalModel(TT, thr, ev, loss, pwork, Before=may0);
    otherwise
        error("Bilinmeyen vaka: %s", part);
end
end
