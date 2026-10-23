classdef ReplayEngine < handle
    %REPLAYENGINE Otonom akışın simülasyonu: tarihsel veriyi 15 dk adımlarla "canlı gibi" oynatır.
    %   eng = ges.runtime.ReplayEngine(cfg, startTime, endTime)
    %   snap = eng.step(k)  — saati k adım ilerletir ve anlık durumu döndürür
    %   Her adımda SCADA'dan yeni 15 dk verisi "düşmüş" gibi davranılır: sayısal ajanın
    %   sonuçları (sağlık durumu, beklenen güç) o ana kadar olan veriyle hesaplanmıştır
    %   (s05 dedektörleri nedenseldir). Sahada bu sınıfın yerini klasörü izleyen canlı
    %   alım katmanı alır; arayüz aynı snapshot yapısını kullanır.
    %   Test dilimi (>= testStart) bu sınıfla OYNATILMAZ.

    properties (SetAccess = private)
        Times (:,1) datetime            % oynatma ızgarası
        Index (1,1) double = 1          % mevcut adım
        Ids (:,1) string                % invertör kimlikleri (eğitim havuzu)
        Cabin (:,1) double
        Inv (:,1) double
        State                           % nT × n categorical sağlık durumu
        Pact single                     % nT × n gerçek DC güç (kW)
        Pexp single                     % nT × n beklenen DC güç (kW)
        PexpWork single                 % nT × n yalnızca çalışan stringlerle beklenen DC güç (kW)
        NumDead uint8                   % nT × n o anda ölü string sayısı
        DeadMask uint8                  % nT × n ölü string bit maskesi (hava tahmini için)
        Tcab single                     % nT × n invertör iç sıcaklığı (°C) — ısıl kısma bildirimi
        ThrLoss single                  % nT × n gizli ısıl kısma kaybı (kW, v2-B01)
        Thr logical                     % nT × n o adımda ısıl kısma imzası var mı (v2-B01)
        Infos cell                      % n × 1 invertör künyeleri (info struct)
        Kc (:,1) double                 % clear-sky indeksi
        Gref (:,1) double               % referans ışınım
        PoaCs (:,1) double              % aynı düzlemde bulutsuz gökyüzü ışınımı (günlük açıklık için)
        Elev (:,1) double               % güneş yüksekliği (°)
        Tamb (:,1) double               % ortam sıcaklığı (°C; sensör güneşte ısınıyor)
        Tmod (:,1) double               % modül sıcaklığı (°C)
        HoldoutIds (:,1) string         % haritada gösterilen ama verisi gizli test cihazları
        LoadSeconds (1,1) double = NaN  % açılış süresi (önbellekten / diskten)
        FromCache (1,1) logical = false
    end

    properties (Access = private)
        StepAct (:,1) double            % adım başına tesis gerçek / beklenen gücü (energySeries önbelleği)
        StepExp (:,1) double
    end

    methods
        function obj = ReplayEngine(cfg, startTime, endTime)
            arguments
                cfg (1,1) struct
                startTime (1,1) datetime
                endTime (1,1) datetime
            end
            if endTime >= cfg.split.testStart && ~isfield(cfg, "workspace")
                error("ges:runtime:testSlice", "Test dilimi (%s sonrası) replay ile oynatılamaz.", ...
                    string(cfg.split.testStart, "yyyy-MM-dd"));
            end
            t0 = tic;
            % Açılış önbelleği: 99×2 büyük .mat dosyasını (~20 s) her açılışta okumak yerine
            % oynatma matrisleri tek küçük dosyada tutulur; kaynak dosyalar değişirse yenilenir.
            cacheDir = fullfile(cfg.paths.root, "artifacts", "runtime");
            if isfield(cfg.paths, "runtime")
                cacheDir = cfg.paths.runtime;                % yüklenen veri seti: kendi önbelleği
            end
            cacheFile = fullfile(cacheDir, "replay_v6_" + string(startTime, "yyyyMMddHHmm") + "_" + ...
                string(endTime, "yyyyMMddHHmm") + ".mat");
            srcFiles = [dir(fullfile(cfg.paths.anomaly, "K*.mat"));
                dir(fullfile(cfg.paths.processed, "train", "inverter", "K*.mat"))];
            c = dir(cacheFile);
            if ~isempty(c) && c.datenum > max([srcFiles.datenum])
                S = load(cacheFile).replay;
                obj.FromCache = true;
            else
                S = ges.runtime.ReplayEngine.build(cfg, startTime, endTime);
                if ~isfolder(cacheDir)
                    mkdir(cacheDir);
                end
                replay = S;
                save(cacheFile, "replay", "-v7");
            end
            for f = string(fieldnames(S))'
                obj.(f) = S.(f);
            end
            % Gündüz ölçümü olmayan adım "veri yok"tur: adım durumu yalnızca cihazın veri aralığı içinde
            % "offline" oluyordu; dışa aktarımı biten cihaz (Kabin 12, 23.05.2025 sonrası) yeşil görünüyordu
            obj.State(isnan(obj.Pact) & obj.State ~= "night") = "offline";
            num = double(split(extractAfter(obj.Ids, "K"), "-INV"));
            obj.Cabin = num(:, 1);
            obj.Inv = num(:, 2);
            obj.HoldoutIds = "K02-INV21";              % cfg.split.holdoutDevices'ın kısa kimliği
            if isfield(cfg, "workspace") || ismember(obj.HoldoutIds, obj.Ids)
                obj.HoldoutIds = strings(0, 1);          % yüklenen veri setinde gizli cihaz yok
            end
            obj.LoadSeconds = toc(t0);
        end

        function dev = devices(obj)
            %DEVICES Hava tahmini için invertör künyeleri + şimdiye kadarki son ölü-string maskesi.
            i = obj.Index;
            dev = struct("Id", cellstr(obj.Ids), "info", obj.Infos, "DeadMask", uint8(0));
            day = obj.Gref(1:i) > 100;
            for k = 1:numel(obj.Ids)
                rows = find(day & ~isnan(obj.Pact(1:i, k)), 1, "last");
                if ~isempty(rows)
                    dev(k).DeadMask = obj.DeadMask(rows, k);
                end
                dev(k).Id = obj.Ids(k);
            end
        end

        function snap = step(obj, k)
            %STEP Saati k adım ilerletir (sona gelince durur) ve anlık durumu döndürür.
            arguments
                obj
                k (1,1) double {mustBeInteger, mustBePositive} = 1
            end
            prev = obj.Index;
            obj.Index = min(obj.Index + k, numel(obj.Times));
            snap = obj.snapshot(prev);
        end

        function snap = seek(obj, t)
            %SEEK Saati verilen ana atlar (ileri veya geri); atlamada bildirim üretilmez.
            [~, obj.Index] = min(abs(obj.Times - t));
            snap = obj.snapshot(obj.Index);
        end

        function [t0, t1] = range(obj)
            t0 = obj.Times(1);
            t1 = obj.Times(end);
        end

        function tf = atEnd(obj)
            tf = obj.Index >= numel(obj.Times);
        end

        function snap = snapshot(obj, prevIndex)
            %SNAPSHOT Mevcut adımın durumu; prevIndex verilirse aradaki yeni alarmlar da döner.
            arguments
                obj
                prevIndex (1,1) double = obj.Index
            end
            i = obj.Index;
            snap.Time = obj.Times(i);
            snap.State = string(obj.State(i, :))';
            snap.Pact = obj.Pact(i, :)';
            snap.Pexp = obj.Pexp(i, :)';
            snap.NumDead = obj.NumDead(i, :)';
            snap.Tcab = double(obj.Tcab(i, :))';
            snap.ThrLossKw = double(obj.ThrLoss(i, :))';
            reporting = ~isnan(snap.Pact) & ~isnan(snap.Pexp);
            snap.NumReporting = nnz(~isnan(snap.Pact));
            snap.PlantKw = double(sum(max(snap.Pact(reporting), 0)));
            snap.PlantExpectedKw = double(sum(snap.Pexp(reporting)));
            snap.NumAlarm = nnz(snap.State == "alarm");
            snap.NumWarning = nnz(snap.State == "warning");
            snap.NumChronic = nnz(snap.State == "chronic");
            snap.Kc = obj.Kc(i);
            snap.G = obj.Gref(i);
            % Bildirim politikası (alarm yorgunluğunu önler): yeni adımlarda
            %   * "alarm" durumuna GEÇİŞ, veya
            %   * uyarı/alarm durumunun kesintisiz SustainSteps adıma (2 saat) ULAŞMASI.
            % Kısa süreli %10-15 sapmalar haritada turuncu görünür ama bildirim üretmez.
            snap.NewAlerts = strings(0, 1);
            if i > prevIndex
                sustainSteps = 8;
                first = max(prevIndex - sustainSteps, 1);
                block = string(obj.State(first:i, :));
                bad = ismember(block, ["warning" "alarm"]);
                alarm = block == "alarm";
                runLen = zeros(size(bad));
                runLen(1, :) = bad(1, :);
                for r = 2:size(bad, 1)
                    runLen(r, :) = bad(r, :) .* (runLen(r - 1, :) + 1);
                end
                newRows = (first:i)' > prevIndex;
                alarmRise = [false(1, size(alarm, 2)); alarm(2:end, :) & ~alarm(1:end-1, :)];
                hit = any((runLen == sustainSteps | alarmRise) & newRows, 1);
                snap.NewAlerts = obj.Ids(hit);
            end
        end

        function T = series(obj, id, t0, t1)
            %SERIES Bir invertörün [t0, t1) aralığındaki gerçek/beklenen güç ve ışınım serisi
            %   (şimdiye kadar). t1 verilmezse t0'ın günü.
            arguments
                obj
                id (1,1) string
                t0 (1,1) datetime
                t1 (1,1) datetime = dateshift(t0, "start", "day") + days(1)
            end
            if nargin < 4
                t0 = dateshift(t0, "start", "day");
            end
            k = find(obj.Ids == id, 1);
            rows = obj.Times >= t0 & obj.Times < t1 & obj.Times <= obj.Times(obj.Index);
            T = timetable(obj.Times(rows), obj.Pact(rows, k), obj.Pexp(rows, k), obj.Gref(rows), ...
                VariableNames=["Pact" "Pexp" "G"]);
        end

        function T = energySeries(obj, t0, t1, by)
            %ENERGYSERIES Tesis enerjisi (gerçek / beklenen, kWh) gün veya ay bazında, ŞİMDİYE kadar.
            %   T = eng.energySeries(t0, t1, "day" | "month") — Time, Eact, Eexp, Perf (%).
            %   Yalnızca verisi olan gündüz adımları toplanır (assess ile aynı kural).
            arguments
                obj
                t0 (1,1) datetime
                t1 (1,1) datetime
                by (1,1) string {mustBeMember(by, ["day" "month"])} = "day"
            end
            [act, ex] = obj.plantSteps();
            tNow = obj.Times(obj.Index);
            rows = find(obj.Times >= t0 & obj.Times < t1 & obj.Times <= tNow);
            unit = ifelse(by == "day", "day", "month");
            bins = dateshift(obj.Times(rows), "start", unit);
            stepDur = caldays(1);
            if by == "month"
                stepDur = calmonths(1);
            end
            edges = (dateshift(t0, "start", unit):stepDur:dateshift(t1 - seconds(1), "start", unit))';
            [tf, g] = ismember(bins, edges);
            Eact = accumarray(g(tf), act(rows(tf)), [numel(edges) 1]) * 0.25;
            Eexp = accumarray(g(tf), ex(rows(tf)), [numel(edges) 1]) * 0.25;
            future = edges > tNow;
            Eact(future) = NaN;
            Eexp(future) = NaN;
            T = table(edges, Eact, Eexp, 100 * Eact ./ Eexp, VariableNames=["Time" "Eact" "Eexp" "Perf"]);
        end

        function A = assess(obj, horizon)
            %ASSESS Anlık / günlük / haftalık performans değerlendirmesi (yalnızca şimdiye kadarki veri).
            %   A = eng.assess("instant" | "day" | "week") — tüm invertörler için:
            %     State  : ufuk durumu (n×1). Anlık: o adımın durumu. Günlük: bugün (00:00 → şimdi;
            %              gün doğmadıysa dünün tamamı) en az 1 saat (4 adım) süren EN AĞIR durum.
            %              Haftalık: son 7 günün en az 2'sinde (her biri ≥ 1 saat) görülen en ağır
            %              durum (tekrarlayan sorun); tek günlük olaylar Days sütunlarında görünür.
            %              Ağırlık sırası: alarm > uyarı > kronik > şebeke > ısıl kısma > izle > sağlıklı.
            %     Ratio  : anlık P/P_beklenen; günlük/haftalık performans = Σ gerçek / Σ beklenen enerji
            %     Eact, Eexp (kWh), kayıp dağılımı LossThermal / LossDead / LossGrid / LossOther (kWh)
            %     Hours (n×9) ve Days (n×9): stateNames() sırasıyla gündüz saatleri / ≥1 saat görülen gün.
            %              "thermal" sütunu durum değil GERÇEK kısılmış adımlardan sayılır (durum, zikzak
            %              yüzünden son 2 saatin ≥ ¼'ü kısılmışsa sürer; teşhis panelindeki süreyle aynı olsun)
            %     Plant: tesis toplamları ve gökyüzü (açıklık Kd, gün sınıfları)
            %   Enerji yalnızca verisi olan gündüz adımlarında toplanır: veri yok (iletişim kesintisi)
            %   adımları kayıp sayılmaz (sayaç E_life bu aralıklarda üretim gösterebiliyor), süresi
            %   ayrıca raporlanır.
            arguments
                obj
                horizon (1,1) string {mustBeMember(horizon, ["instant" "day" "week"])}
            end
            names = ges.anomaly.stateNames();
            order = ["alarm" "warning" "chronic" "grid" "thermal" "watch"];      % ağırdan hafife
            minSteps = 4;                                                       % 1 saat (etiketleme ile aynı)
            i = obj.Index;
            tNow = obj.Times(i);
            n = numel(obj.Ids);
            A.Horizon = horizon;
            A.Names = names;

            day0 = dateshift(tNow, "start", "day");
            if nnz(obj.Times >= day0 & obj.Times <= tNow & obj.Elev > 5) < minSteps
                day0 = day0 - days(1);                    % gün henüz doğmadı → dünün tamamı
                dayEnd = min(day0 + days(1) - minutes(15), tNow);
            else
                dayEnd = tNow;
            end
            switch horizon
                case "instant"
                    A.T0 = tNow;
                    A.T1 = tNow;
                    A.Label = "Anlık (" + string(tNow, "dd.MM.yyyy HH:mm") + ")";
                case "day"
                    A.T0 = day0;
                    A.T1 = dayEnd;
                    if dayEnd < tNow
                        A.Label = "Günlük: " + string(day0, "dd.MM.yyyy") + " (tam gün; bugün güneş henüz doğmadı)";
                    else
                        A.Label = "Günlük: " + string(day0, "dd.MM.yyyy") + " 00:00–" + string(dayEnd, "HH:mm");
                    end
                case "week"
                    A.T0 = max(day0 - days(6), obj.Times(1));
                    A.T1 = tNow;
                    A.Label = "Haftalık: " + string(A.T0, "dd.MM") + "–" + string(tNow, "dd.MM.yyyy HH:mm") + " (son 7 gün)";
            end
            rows = find(obj.Times >= A.T0 & obj.Times <= A.T1);
            codes = double(obj.State(rows, :));                % stateNames sırasıyla 1..9
            pact = double(obj.Pact(rows, :));
            pexp = double(obj.Pexp(rows, :));
            pwork = double(obj.PexpWork(rows, :));
            thr = double(obj.ThrLoss(rows, :));
            idx = @(s) find(names == s);
            evalRows = codes ~= idx("night") & codes ~= idx("offline") & ~isnan(pact) & ~isnan(pexp);
            gridRows = evalRows & codes == idx("grid");
            other = evalRows & ~gridRows;
            sum0 = @(x, m) sum(x .* m, 1, "omitnan")' * 0.25;
            A.Eexp = sum0(pexp, evalRows);
            A.Eact = sum0(max(pact, 0), evalRows);
            A.LossGrid = sum0(pexp - pact, gridRows);
            A.LossThermal = sum0(thr, other);
            A.LossDead = sum0(max(pexp - pwork, 0), other);
            A.LossOther = A.Eexp - A.Eact - A.LossGrid - A.LossThermal - A.LossDead;
            hit = false([size(codes) numel(names)]);
            for s = 1:numel(names)
                hit(:, :, s) = codes == s;
            end
            hit(:, :, idx("thermal")) = obj.Thr(rows, :) & codes ~= idx("night");
            A.Hours = reshape(sum(hit, 1), n, []) * 0.25;
            dayOf = dateshift(obj.Times(rows), "start", "day");
            [g, dl] = findgroups(dayOf);
            A.Days = zeros(n, numel(names));
            for d = 1:numel(dl)
                A.Days = A.Days + (reshape(sum(hit(g == d, :, :), 1), n, []) >= minSteps);
            end
            litSteps = sum(codes ~= idx("night"), 1)';
            offShare = A.Hours(:, idx("offline")) * 4 ./ max(litSteps, 1);

            st = repmat("ok", n, 1);
            switch horizon
                case "instant"
                    st = string(obj.State(i, :))';
                    A.Ratio = double(obj.Pact(i, :))' ./ double(obj.Pexp(i, :))';
                    A.Ratio(~(double(obj.Pexp(i, :))' > 0.5)) = NaN;
                case "day"
                    for s = flip(order)                   % hafiften ağıra: ağır olan üzerine yazar
                        st(A.Hours(:, idx(s)) * 4 >= minSteps) = s;
                    end
                case "week"
                    for s = flip(order)
                        st(A.Days(:, idx(s)) >= 2) = s;
                    end
            end
            if horizon ~= "instant"
                st(st == "ok" & offShare >= 0.5) = "offline";
                st(litSteps == 0) = "night";
                A.Ratio = A.Eact ./ A.Eexp;
                A.Ratio(~(A.Eexp > 1)) = NaN;
            end
            A.State = st;

            % Tesis toplamı ve gökyüzü (ges.prep.dailySummary ile aynı eşikler: Kd < 0,4 kapalı,
            % Kd ≥ 0,75 ve VI < 2,5 açık, diğerleri parçalı)
            P.Eact = sum(A.Eact);
            P.Eexp = sum(A.Eexp);
            lit = obj.Elev(rows) > 5 & ~isnan(obj.Gref(rows)) & ~isnan(obj.PoaCs(rows));
            P.Kd = sum(obj.Gref(rows(lit))) / sum(obj.PoaCs(rows(lit)));
            P.SkyDays = zeros(1, 3);                       % açık / parçalı / kapalı gün sayısı
            for d = 1:numel(dl)
                r = rows(g == d);
                m = obj.Elev(r) > 5 & ~isnan(obj.Gref(r)) & ~isnan(obj.PoaCs(r));
                if nnz(m) < minSteps
                    continue
                end
                kd = sum(obj.Gref(r(m))) / sum(obj.PoaCs(r(m)));
                pair = m(2:end) & m(1:end-1);
                dG = abs(diff(obj.Gref(r)));
                dCs = abs(diff(obj.PoaCs(r)));
                vi = sum(dG(pair)) / sum(dCs(pair));
                if kd < 0.4
                    P.SkyDays(3) = P.SkyDays(3) + 1;
                elseif kd >= 0.75 && vi < 2.5
                    P.SkyDays(1) = P.SkyDays(1) + 1;
                else
                    P.SkyDays(2) = P.SkyDays(2) + 1;
                end
            end
            A.Plant = P;
        end
    end

    methods (Access = private)
        function [act, ex] = plantSteps(obj)
            % Adım başına tesis toplamı (yalnız verisi olan gündüz adımları); ilk çağrıda bir kez hesaplanır
            if isempty(obj.StepAct)
                names = ges.anomaly.stateNames();
                codes = double(obj.State);
                pact = double(obj.Pact);
                pexp = double(obj.Pexp);
                ok = codes ~= find(names == "night") & codes ~= find(names == "offline") & ~isnan(pact) & ~isnan(pexp);
                pact(~ok) = 0;
                pexp(~ok) = 0;
                obj.StepAct = sum(max(pact, 0), 2);
                obj.StepExp = sum(pexp, 2);
            end
            act = obj.StepAct;
            ex = obj.StepExp;
        end
    end

    methods (Static, Access = private)
        function S = build(cfg, startTime, endTime)
            % İşlenmiş invertör ve olay dosyalarından oynatma matrislerini kurar (yavaş yol).
            meteo = load(fullfile(cfg.paths.processed, "shared", "meteo_ref.mat")).meteoRef;
            win = meteo.Time >= startTime & meteo.Time <= endTime;
            S.Times = meteo.Time(win);
            S.Kc = meteo.Kc(win);
            S.Gref = meteo.G_ref(win);
            S.PoaCs = meteo.PoaCsRef(win);
            S.Elev = meteo.Elevation(win);
            S.Tamb = meteo.T_amb(win);
            S.Tmod = meteo.T_mod(win);
            files = dir(fullfile(cfg.paths.anomaly, "K*.mat"));         % v2: kısma-farkında durumlar
            S.Ids = sort(erase(string({files.name})', ".mat"));
            n = numel(S.Ids);
            nT = numel(S.Times);
            S.Pact = nan(nT, n, "single");             % tüm veri aralığı (~53 bin adım × 99) için single
            S.Pexp = nan(nT, n, "single");
            S.PexpWork = nan(nT, n, "single");
            S.NumDead = zeros(nT, n, "uint8");
            S.DeadMask = zeros(nT, n, "uint8");
            S.Tcab = nan(nT, n, "single");
            S.ThrLoss = zeros(nT, n, "single");
            S.Thr = false(nT, n);
            S.Infos = cell(n, 1);
            st = repmat(categorical("offline", ges.anomaly.stateNames()), nT, n);
            for k = 1:n
                A = load(fullfile(cfg.paths.anomaly, S.Ids(k) + ".mat"), "Steps").Steps;
                D = load(fullfile(cfg.paths.processed, "train", "inverter", S.Ids(k) + ".mat"), "TT", "info");
                [tf, loc] = ismember(S.Times, A.Time);
                st(tf, k) = A.HealthState(loc(tf));
                S.Pexp(tf, k) = A.Pdc_exp(loc(tf));
                S.PexpWork(tf, k) = A.PdcWork_exp(loc(tf));
                if ismember("ThrottleLossKw", A.Properties.VariableNames)
                    S.ThrLoss(tf, k) = A.ThrottleLossKw(loc(tf));
                    S.Thr(tf, k) = A.Throttle(loc(tf));
                end
                [tf, loc] = ismember(S.Times, D.TT.Time);
                S.Pact(tf, k) = D.TT.P_dc(loc(tf));
                S.NumDead(tf, k) = D.TT.NumDead(loc(tf));
                S.DeadMask(tf, k) = D.TT.DeadMask(loc(tf));
                S.Tcab(tf, k) = D.TT.T_cab(loc(tf));
                S.Infos{k} = D.info;
            end
            S.State = st;
        end
    end
end

function v = ifelse(c, a, b)
if c
    v = a;
else
    v = b;
end
end
