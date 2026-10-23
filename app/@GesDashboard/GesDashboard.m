classdef GesDashboard < handle
    %GESDASHBOARD SmartGrid-Twin & GES dijital ikiz paneli — üst menülü çok sayfalı arayüz, her sayfada asistan.
    %   app = GesDashboard() — 15 dk adımlarla oynatır; başlıktaki tarih/saat seçiciyle veri aralığında
    %   istenen ana atlanır.
    %   Sayfalar (üst menü): Genel Bakış · Saha Haritası · Analiz · Tahmin & Erken Uyarı · Raporlar ·
    %   Bildirimler · Veri · Yardım. Sağdaki asistan YALNIZCA açık sayfanın içeriğiyle yanıt verir
    %   (ges.agents.PageChat: sayfa içeriği parçalara bölünür, soruyla en ilgili parçalar seçilir).

    properties (Access = private)
        Cfg struct
        Engine                          % ges.runtime.ReplayEngine
        Ctx struct                      % ajan bağlamı (Now her tikte güncellenir)
        Timer
        StepsPerTick (1,1) double = 1
        Horizon (1,1) string = "instant"
        AssessCache = struct("index", NaN, "day", [], "week", [], "instant", [])
        Page (1,1) string = "overview"
        Selected string = string.empty
        ChartMode (1,1) string = "power"
        MapNode (1,1) string = "WR13TL22-8231"
        LastDiagnosis = []
        DiagTime = NaT
        PageChat                        % ges.agents.PageChat
        Memory = struct("Time", {}, "Page", {}, "Title", {}, "Text", {})
        Notifications = struct("time", {}, "kind", {}, "tag", {}, "text", {}, "token", {}, "llm", {}, "pending", {})
        ChatLog = struct("role", {}, "text", {}, "tools", {}, "page", {}, "go", {})
        ChatTyping string = ""
        Pending cell = {}
        BusyLabels string = string.empty
        TokenCounter (1,1) double = 0
        CabinNoteTime                   % containers.Map: kabin -> son toplu bildirim zamanı
        ThermalNoteTime                 % containers.Map: kabin/invertör -> son ısıl kısma bildirimi
        PeriodCache                     % containers.Map: "Id|yyyyMMdd" -> tamamlanmış günün periodView kaydı
        EnergyMode (1,1) string = "week"
        RenderKey struct = struct()     % sayfa -> son çizim anahtarı (gereksiz yeniden çizimi önler)
        Forecast = []                   % son hava/üretim tahmini
        BaseRange struct                % eğitim veri setinin oynatma aralığı
        Dataset (1,1) string = ""       % "" = eğitim verisi; aksi halde workspace/<ad>
        Layers (1,1) string = "full"    % "full": çekirdek + araştırma katmanı | "core": yalnız çekirdek

        Fig
        Header struct = struct()
        NavButtons struct = struct()
        PagePanels struct = struct()
        Outer
        Ov struct = struct()            % Genel Bakış
        Mp struct = struct()            % Saha Haritası
        An struct = struct()            % Analiz
        Fc struct = struct()            % Tahmin & Erken Uyarı
        Rp struct = struct()            % Raporlar
        Nt struct = struct()            % Bildirimler
        Dt struct = struct()            % Veri
        Hp struct = struct()            % Yardım
        Ch struct = struct()            % asistan paneli
    end

    properties (Constant, Access = private)
        Pages = ["overview" "map" "analysis" "forecast" "reports" "notify" "data" "help"]
        PageTitles = ["Genel Bakış" "Saha Haritası" "Analiz" "Tahmin & Erken Uyarı" "Raporlar" "Bildirimler" "Veri" "Yardım"]
        PageIcons = ["📊" "🗺" "📈" "🔮" "📑" "🔔" "📂" "❓"]
        PageTopics = [ ...
            "tesis toplam anlık güç AC DC güç, evirici dönüşüm verimi eta, özgül güç kW/kWp, bugünkü aylık toplam üretim enerjisi, performans yüzdesi, haftalık aylık yıllık enerji grafiği, gökyüzü hava sıcaklık ışınım rüzgar hızı Faiman Ross hücre sıcaklığı, L1 şebeke gerilimi frekansı k/18 röle, yalıtım direnci R_iso, son 7 gün özeti"
            "SmartGrid-Twin 5 düğümlü topoloji haritası, METEO-SmartGrid-Twin PV-ARRAY WR13TL22-8231 GRID-PCC DATA-MANAGER düğümleri, kabin haritası, kutucuklar ve renkleri, durum alarm uyarı ısıl kısma kronik veri yok, anlık günlük haftalık değerlendirme, sayaç mutabakatı"
            "seçili invertörün 4 modlu mühendislik grafiği: güç ve POA ışınım, DC gerilim V_dc akım I_dc ve 4-kadranlı MPP zarfı, evirici verimi ve Faiman/Ross termal rüzgar ikizi, L1 şebeke gerilimi U_L1,cond frekans ve R_iso yalıtım direnci; skalogram (günlük / 7 günlük), teşhis ajanları 3 görüş CNN VLM elektriksel ikiz ve öz-akran karar, olaylar geçmişi, saha geri bildirimi"
            "gelecek tahmini, 48 saatlik üretim tahmini, hava ve rüzgar tahmini, yarın ısıl kısma ve termal kayıp tahmini, arıza riski, erken uyarı, R_iso yalıtım direnci düşüşü, kısa kopma, geriye dönük doğrulama, öncü süre"
            "kayıp dağılımı şelalesi, evirici verim eğrisi Sandia modeli, ısıl kısma ve Faiman rüzgar soğutması analizi, L1 şebeke gerilim yükselmesi Thevenin empedansı R_th, R_iso sabah çiyi nem profili, tozlanma oranı kirlenme hızı, bulutluluk oranı, degradasyon, bakım temizlik aralığı"
            "bildirimler, alarm ve uyarı mesajları, kart geçmişi, LLM ile yazılan bildirimler"
            "veri yükleme, dosya ekleme, SMA Sunny Portal Data Manager birleşik CSV dosyaları, meteoroloji kabin invertör tesis sayacı dosyaları, klasörden toplu yükleme, yüklü veri envanteri"
            "sözlük, kavramların açıklaması: ısıl kısma nedir, string, MPP zarfı, beklenen güç, performans, skalogram, tozlanma, bulutluluk, trip, kronik, erken uyarı, k/18 röle yasası, U_L1,cond, Faiman rüzgar soğutması, R_iso yalıtım direnci, 0.00% reset el-sıkışması"]
        Classes = ["healthy" "string_fault" "inverter_trip" "thermal_derating" "soiling" "grid_event"]
        ClassNamesTr = ["Sağlıklı" "String / DC dizi arızası" "Evirici arızası/trip" "Isıl kısma (güç düşürme)" "Tozlanma" "Şebeke/L1 olayı"]
        StateTr = dictionary(["ok" "watch" "thermal" "warning" "alarm" "chronic" "grid" "offline" "night"], ...
            ["Sağlıklı" "İzle" "Isıl kısma" "Uyarı" "ALARM" "Kronik (bakım kaydı)" "Şebeke/L1 olayı" "Veri yok" "Gece"])
        StateLower = dictionary(["ok" "watch" "thermal" "warning" "alarm" "chronic" "grid" "offline" "night"], ...
            ["sağlıklı" "izle" "ısıl kısma" "uyarı" "alarm" "kronik" "şebeke/L1 olayı" "veri yok" "gece"])
        StateColor = dictionary(["ok" "watch" "thermal" "warning" "alarm" "chronic" "grid" "offline" "night"], ...
            ["#2e9d58" "#b8900f" "#c2185b" "#ef8a2c" "#d93025" "#c8741f" "#7b4fb0" "#9aa5b1" "#46525f"])
        HorizonTr = dictionary(["instant" "day" "week"], ["Anlık" "Günlük" "Haftalık"])
        ChartModes = ["power" "dc_mpp" "eff_thermal" "grid_riso"]
        ChartModeTitles = [ ...
            "1) Güç (P_dc, P_ac, P_exp) & POA Işınım"
            "2) DC Bara & 4-Kadranlı MPP Zarfı (V_dc, V_mp, I_dc)"
            "3) Evirici Verimi (η_inv) & Termal/Rüzgar İkizi (Faiman vs Ross)"
            "4) L1 Şebeke Kalitesi (U_L1,cond, f_grid, k/18) & R_iso Yalıtım"]
        ThermalShare = 0.25
        ThermalNoteGap = hours(3)
        CabinNoteGap = hours(2)
        MaxDiagnosesPerTick = 3
    end

    methods
        function app = GesDashboard(opts)
            arguments
                opts.Start (1,1) datetime = NaT(TimeZone="Europe/Istanbul")
                opts.End (1,1) datetime = NaT(TimeZone="Europe/Istanbul")
                opts.DataStart (1,1) datetime = NaT(TimeZone="Europe/Istanbul")
                opts.Page (1,1) string = "overview"
                opts.Visible (1,1) logical = true
                opts.Dataset (1,1) string = ""
                opts.Layers (1,1) string {mustBeMember(opts.Layers, ["auto" "full" "core"])} = "auto"
            end
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            addpath(root);
            setupGes();
            app.Cfg = gesConfig();
            tz = app.Cfg.data.timeZone;
            if isfield(app.Cfg.split, "validationStart") && year(app.Cfg.split.validationStart) >= 2026
                defDataStart = datetime(2026, 7, 27, 0, 0, 0, TimeZone=tz);
                defStart     = datetime(2026, 8, 29, 10, 0, 0, TimeZone=tz);
                defEnd       = app.Cfg.split.testStart - minutes(15);
            else
                defDataStart = datetime(2023, 12, 1, 4, 30, 0, TimeZone=tz);
                defStart     = datetime(2025, 5, 1, 5, 0, 0, TimeZone=tz);
                defEnd       = datetime(2025, 5, 31, 21, 0, 0, TimeZone=tz);
            end
            if isnat(opts.DataStart), opts.DataStart = defDataStart; end
            if isnat(opts.Start),     opts.Start = defStart;         end
            if isnat(opts.End),       opts.End = defEnd;             end

            app.Layers = opts.Layers;
            if app.Layers == "auto"
                app.Layers = ifelse(app.Cfg.layers.research, "full", "core");
            end
            app.BaseRange = struct("Start", min(opts.DataStart, opts.Start), "End", opts.End, "Now", opts.Start);
            app.Engine = ges.runtime.ReplayEngine(app.Cfg, min(opts.DataStart, opts.Start), opts.End);
            app.Engine.seek(opts.Start);
            app.Ctx = ges.agents.loadContext(app.Cfg, app.Engine.Times(app.Engine.Index), Horizon=opts.End, Layers=app.Layers);
            app.Ctx.Replay = app.Engine;
            app.Ctx.Fleet = ges.opinions.fleetFromEngine(app.Engine);
            app.PageChat = ges.agents.PageChat();
            app.CabinNoteTime = containers.Map("KeyType", "double", "ValueType", "any");
            app.ThermalNoteTime = containers.Map("KeyType", "char", "ValueType", "any");
            app.PeriodCache = containers.Map("KeyType", "char", "ValueType", "any");
            app.Selected = app.Engine.Ids(1);
            app.buildUi(opts.Visible);
            app.applyLayers();
            app.Timer = timer(Period=1, ExecutionMode="fixedSpacing", BusyMode="drop", ...
                TimerFcn=@(~, ~) app.onTick(), ErrorFcn=@(~, e) app.addNotification("Zamanlayıcı hatası: " + e.Data.message, "error"));
            app.showPage(opts.Page);
            if opts.Dataset ~= ""
                app.loadDataset(opts.Dataset);
            end
            app.warmUp();
        end

        %% Otomasyon / test arayüzü (zamanlayıcısız, deterministik)
        function runTicks(app, n)
            for i = 1:n
                app.onTick();
            end
            drawnow;
        end

        function selectInverter(app, id)
            id = string(id);
            if ~ismember(id, app.Engine.Ids) && ~isempty(app.Engine.Ids)
                id = app.Engine.Ids(1);
            end
            app.select(id);
            drawnow;
        end

        function setChartMode(app, mode)
            %SETCHARTMODE Analiz ve Harita grafik modunu değiştirir: "power" | "dc_mpp" | "eff_thermal" | "grid_riso"
            mode = string(mode);
            if ~ismember(mode, app.ChartModes)
                error("Geçersiz grafik modu: %s", mode);
            end
            app.ChartMode = mode;
            if isfield(app.An, "ChartMode") && isvalid(app.An.ChartMode)
                app.An.ChartMode.Value = char(mode);
            end
            app.renderPage(true);
            drawnow limitrate;
        end

        function selectMapNode(app, node)
            %SELECTMAPNODE Haritadaki 5 topoloji düğümünden birini seçer.
            node = string(node);
            app.MapNode = node;
            mapModes = dictionary(["METEO-SmartGrid-Twin" "PV-ARRAY" "WR13TL22-8231" "GRID-PCC" "DATA-MANAGER"], ...
                ["eff_thermal" "dc_mpp" "power" "grid_riso" "power"]);
            if isKey(mapModes, node)
                app.ChartMode = mapModes(node);
                if isfield(app.An, "ChartMode") && isvalid(app.An.ChartMode)
                    app.An.ChartMode.Value = char(app.ChartMode);
                end
            end
            app.renderMapPage(true);
            drawnow limitrate;
        end

        function showPage(app, name, tab)
            arguments
                app
                name
                tab = []
            end
            key = app.pageKey(name);
            if key == ""
                error("Bilinmeyen sayfa: %s", name);
            end
            app.Page = key;
            for p = app.Pages
                on = p == key;
                app.PagePanels.(p).Visible = on;
                b = app.NavButtons.(p);
                if on
                    b.BackgroundColor = [0.10 0.45 0.91];
                    b.FontColor = [1 1 1];
                else
                    b.BackgroundColor = [1 1 1];
                    b.FontColor = [0.15 0.18 0.22];
                end
            end
            app.Ch.Title.Text = "💬 Asistan · " + app.PageTitles(app.Pages == key) + " sayfası";
            if ~isempty(tab)
                tg = [];
                if key == "forecast", tg = app.Fc.Tabs; elseif key == "reports", tg = app.Rp.Tabs; end
                if ~isempty(tg)
                    if isnumeric(tab)
                        tg.SelectedTab = tg.Children(tab);
                    else
                        k = find(startsWith(string({tg.Children.Title}), string(tab), IgnoreCase=true), 1);
                        if ~isempty(k), tg.SelectedTab = tg.Children(k); end
                    end
                end
            end
            app.renderPage(true);
            drawnow limitrate;
        end

        function ask(app, question)
            app.Ch.Input.Value = char(question);
            app.onChat();
        end

        function pin(app)
            app.onPin();
        end

        function c = pageChunks(app, name)
            c = app.pageContext(app.pageKey(name));
        end

        function requestVlm(app)
            app.onVlm();
        end

        function importData(app, folder, name)
            d = dir(fullfile(folder, "**", "*.csv"));
            app.Dt.Files = table();
            app.dataAppend(string(fullfile({d.folder}, {d.name}))', repmat("", numel(d), 1));
            app.Dt.Name.Value = char(name);
            ws = fullfile(app.Cfg.paths.root, "workspace", string(name));
            if isfolder(ws)
                rmdir(ws, "s");
            end
            app.dataProcess();
        end

        function pickForecastEvent(app, row)
            app.onEventPick(struct("Selection", row, "UserData", app.Fc.EvTable.UserData));
            drawnow;
        end

        function useDataset(app, name)
            app.loadDataset(name);
        end

        function requestWeather(app)
            app.onWeather();
        end

        function goTo(app, t)
            app.seekTo(t);
        end

        function setHorizon(app, h)
            app.applyHorizon(string(h));
            drawnow;
        end

        function v = detailText(app)
            v = [regexprep(string(app.Mp.Title.Text), "<[^>]+>", ""); string(app.Mp.Summary.Text)];
            v = replace(v, "&nbsp;", " ");
        end

        function tf = isBusy(app)
            tf = ~isempty(app.BusyLabels);
        end

        function v = notifications(app)
            v = strings(numel(app.Notifications), 1);
            for k = 1:numel(app.Notifications)
                n = app.Notifications(k);
                v(k) = n.time + "  [" + n.kind + ifelse(n.llm, ", LLM", "") + ifelse(n.pending, ", LLM bekleniyor", "") + "]  " + n.text;
            end
        end

        function v = chatText(app)
            v = strings(0, 1);
            for m = app.ChatLog
                who = ifelse(m.role == "user", "Siz [" + m.page + "]: ", "Asistan: ");
                v(end+1, 1) = who + m.text + ifelse(m.go ~= "", "   [→ " + m.go + "]", "") + ...
                    ifelse(m.tools ~= "", "   [" + m.tools + "]", ""); %#ok<AGROW>
            end
            if app.ChatTyping ~= ""
                v(end+1, 1) = "Asistan: " + app.ChatTyping;
            end
        end

        function v = agentText(app)
            v = string(app.An.Agent.Value);
        end

        function saveScreenshot(app, file)
            drawnow;
            exportapp(app.Fig, file);
        end

        function delete(app)
            if ~isempty(app.Timer) && isvalid(app.Timer)
                stop(app.Timer);
                delete(app.Timer);
            end
            for k = 1:numel(app.Pending)
                try
                    cancel(app.Pending{k});
                catch
                end
            end
            if ~isempty(app.Fig) && isvalid(app.Fig)
                delete(app.Fig);
            end
        end
    end

    methods (Access = private)
        buildUi(app, visible)
        buildOverview(app, parent)
        renderOverview(app, force)
        buildMapPage(app, parent)
        renderMapPage(app, force)
        buildAnalysis(app, parent)
        renderAnalysis(app, force)
        buildForecast(app, parent)
        renderForecast(app, force)
        buildReports(app, parent)
        buildNotifyPage(app, parent)
        buildDataPage(app, parent)
        renderDataPage(app, force)
        buildHelpPage(app, parent)
        buildForecastTabs(app)
        drawWeather(app)
        onEventPick(app, src)
        chunks = pageContext(app, page)

        function dt = dtHours(app)
            if isprop(app.Engine, "DtHours") && ~isempty(app.Engine.DtHours) && ~isnan(app.Engine.DtHours)
                dt = double(app.Engine.DtHours);
            else
                dt = 0.25;
            end
        end

        function setEnergyMode(app, m)
            app.EnergyMode = m;
            app.renderOverview(true);
        end

        function onTablePick(app, src)
            % Tablodan invertör veya tarih seçimi → Analiz sayfası
            if isempty(src.Selection) || isempty(src.UserData)
                return
            end
            r = src.Selection(1);
            if r <= numel(src.UserData)
                u = src.UserData(r);
                if isdatetime(u)
                    app.seekTo(min(u + hours(12), app.Engine.Times(end)));
                    app.showPage("analysis");
                else
                    app.select(string(u));
                    app.showPage("analysis");
                end
            end
        end

        function mapInit(app)
            cabins = unique(app.Engine.Cabin)';
            allIds = sort([app.Engine.Ids; app.Engine.HoldoutIds]);
            c = struct("cabin", {}, "ids", {});
            for cb = cabins
                ids = allIds(startsWith(allIds, sprintf("K%02d-", cb)));
                if isempty(ids)
                    ids = allIds(app.Engine.Cabin == cb);
                end
                c(end+1) = struct("cabin", cb, "ids", {cellstr(ids)}); %#ok<AGROW>
            end
            sendEventToHTMLSource(app.Mp.Html, "init", struct("cabins", c, "holdout", {cellstr(app.Engine.HoldoutIds)}));
            app.RenderKey.map = "";
            app.renderMapPage(true);
        end

        %% ------------------------------------------------------------------ Veri sayfası
        function dataAdd(app, kind)
            names = dictionary(["sma_combined" "meteo" "inverter" "logger" "plant"], ...
                ["SMA Birleşik Rapor (SmartGridLab)" "Meteoroloji" "Kabin / invertör" "SmartLogger" "Tesis sayacı"]);
            lbl = "CSV";
            if isKey(names, kind), lbl = names(kind); end
            [f, folder] = uigetfile("*.csv", lbl + " dosyası seçin (birden fazla seçilebilir)", MultiSelect="on");
            figure(app.Fig);
            if isequal(f, 0)
                return
            end
            files = string(fullfile(folder, f))';
            kArg = ifelse(kind == "sma_combined", "", kind);
            app.dataAppend(files, repmat(kArg, numel(files), 1));
        end

        function dataAddFolder(app)
            folder = uigetdir(app.Cfg.paths.root, "Ham rapor klasörünü seçin (alt klasörler dahil)");
            figure(app.Fig);
            if isequal(folder, 0)
                return
            end
            d = dir(fullfile(folder, "**", "*.csv"));
            files = string(fullfile({d.folder}, {d.name}))';
            app.dataAppend(files, repmat("", numel(files), 1));
        end

        function dataAppend(app, files, kinds)
            app.Dt.Progress.Text = sprintf("%d dosya inceleniyor…", numel(files));
            drawnow;
            c = ges.ingest.catalogFiles(files, kinds);
            c.First = NaT(height(c), 1, TimeZone=app.Cfg.data.timeZone);
            c.Last = NaT(height(c), 1, TimeZone=app.Cfg.data.timeZone);
            for k = 1:height(c)
                [f0, f1] = ges.ingest.fileSpan(c.File(k));
                if ~isnat(f0) && isempty(f0.TimeZone), f0.TimeZone = app.Cfg.data.timeZone; end
                if ~isnat(f1) && isempty(f1.TimeZone), f1.TimeZone = app.Cfg.data.timeZone; end
                c.First(k) = f0;
                c.Last(k) = f1;
            end
            if isempty(app.Dt.Files)
                app.Dt.Files = c;
            else
                keyNew = c.File + "|" + c.Kind + "|" + c.Id;
                keyOld = app.Dt.Files.File + "|" + app.Dt.Files.Kind + "|" + app.Dt.Files.Id;
                app.Dt.Files = [app.Dt.Files; c(~ismember(keyNew, keyOld), :)];
            end
            app.Dt.Progress.Text = "";
            app.renderDataPage(true);
        end

        function dataClear(app)
            app.Dt.Files = table();
            app.renderDataPage(true);
        end

        function dataProcess(app)
            c = app.Dt.Files;
            if isempty(c)
                uialert(app.Fig, "Önce CSV dosyası ekleyin.", "Veri");
                return
            end
            name = string(regexprep(char(strtrim(app.Dt.Name.Value)), "[^\w\-]", "_"));
            if name == ""
                name = "yeni_veri";
            end
            if isfolder(fullfile(app.Cfg.paths.root, "workspace", name))
                sel = uiconfirm(app.Fig, sprintf("'%s' adlı veri seti zaten var. Üzerine yazılsın mı?", name), "Veri seti", ...
                    Options=["Üzerine yaz" "Vazgeç"], DefaultOption=2, CancelOption=2);
                if sel ~= "Üzerine yaz"
                    return
                end
            end
            if strcmp(app.Timer.Running, "on")
                app.togglePlay();
            end
            app.Dt.Process.Enable = "off";
            app.Dt.Log.Value = "";
            try
                ges.ingest.buildWorkspace(gesConfig(), c, name, Progress=@(msg) app.dataProgress(msg));
                app.loadDataset(name);
            catch err
                app.dataProgress("HATA: " + err.message);
                uialert(app.Fig, err.message, "Veri işlenemedi");
            end
            app.Dt.Process.Enable = "on";
        end

        function dataProgress(app, msg)
            app.Dt.Progress.Text = msg;
            app.Dt.Log.Value = [string(app.Dt.Log.Value); string(datetime("now"), "HH:mm:ss") + "  " + msg];
            drawnow limitrate;
        end

        function loadDataset(app, name)
            name = string(name);
            if strcmp(app.Timer.Running, "on")
                app.togglePlay();
            end
            cfg = ges.ingest.workspaceConfig(gesConfig(), name);
            if name == ""
                r = app.BaseRange;
                t0 = r.Start;
                t1 = r.End;
                tStart = r.Now;
            else
                m = load(fullfile(cfg.paths.workspace, "manifest.mat")).manifest;
                t0 = m.Start;
                t1 = m.End;
                tStart = dateshift(t0, "start", "day") + days(1) + hours(12);
            end
            app.Header.Busy.Text = "⏳ veri seti yükleniyor…";
            drawnow;
            app.Cfg = cfg;
            app.Dataset = name;
            app.Engine = ges.runtime.ReplayEngine(cfg, t0, t1);
            snap = app.Engine.seek(tStart);
            app.Ctx = ges.agents.loadContext(cfg, snap.Time, Horizon=t1, Layers=app.Layers);
            app.Ctx.Replay = app.Engine;
            app.Ctx.Fleet = ges.opinions.fleetFromEngine(app.Engine);
            app.AssessCache = struct("index", NaN, "day", [], "week", [], "instant", []);
            app.PeriodCache = containers.Map("KeyType", "char", "ValueType", "any");
            app.RenderKey = struct();
            app.LastDiagnosis = [];
            app.DiagTime = NaT;
            app.Selected = app.Engine.Ids(1);
            app.An.Inverter.Items = app.Engine.Ids;
            app.An.Inverter.Value = app.Selected;
            app.Header.Title.Text = cfg.site.name + " Dijital İkiz" + ifelse(app.Layers == "core", "  ·  çekirdek mod", "") + ...
                ifelse(name == "", "", "  ·  veri seti: " + name);
            app.Header.Date.Limits = [datetime(year(t0), month(t0), day(t0)), datetime(year(t1), month(t1), day(t1))];
            app.Header.Date.Value = datetime(year(snap.Time), month(snap.Time), day(snap.Time));
            app.Header.Hour.Value = hour(snap.Time);
            app.Header.Minute.Value = 15 * floor(minute(snap.Time) / 15);
            app.renderHeader(snap);
            app.mapInit();
            app.Header.Busy.Text = "✓ hazır";
            msg = "Eğitim veri setine dönüldü.";
            if name ~= ""
                msg = sprintf("Veri seti '%s' yüklendi: %d evirici, %s – %s.", name, numel(app.Engine.Ids), ...
                    string(t0, "dd.MM.yyyy"), string(t1, "dd.MM.yyyy"));
            end
            app.addNotification(msg, "system");
            app.renderPage(true);
            app.renderDataPage(true);
        end

        function key = pageKey(app, name)
            name = string(name);
            key = "";
            if strlength(strtrim(name)) == 0
                return
            end
            if any(app.Pages == name)
                key = name;
                return
            end
            fold = @(s) lower(replace(string(s), ["ı" "İ" "ş" "Ş" "ğ" "Ğ" "ü" "Ü" "ö" "Ö" "ç" "Ç"], ...
                ["i" "i" "s" "s" "g" "g" "u" "u" "o" "o" "c" "c"]));
            n = fold(strtrim(name));
            t = fold(app.PageTitles);
            k = find(t == n, 1);
            if isempty(k)
                k = find(startsWith(t, n) | startsWith(n, extractBefore(t + " ", " ")), 1);
            end
            if ~isempty(k)
                key = app.Pages(k);
            end
        end

        function renderPage(app, force)
            arguments
                app
                force (1,1) logical = false
            end
            switch app.Page
                case "overview"
                    app.renderOverview(force);
                case "map"
                    app.renderMapPage(force);
                case "analysis"
                    app.renderAnalysis(force);
                case "forecast"
                    app.renderForecast(force);
                case "data"
                    app.renderDataPage(force);
            end
        end

        function applyLayers(app)
            if app.Layers ~= "core"
                return
            end
            app.Header.Title.Text = app.Cfg.site.name + " Dijital İkiz  ·  çekirdek mod";
            app.An.Explain.Enable = "off";
            app.An.Explain.Tooltip = "LLM araştırma katmanındadır; çekirdek modda kapalı";
            app.An.Vlm.Enable = "off";
            app.An.Vlm.Tooltip = "VLM araştırma katmanındadır; çekirdek modda kapalı";
            app.Nt.LlmCheck.Value = false;
            app.Nt.LlmCheck.Enable = "off";
            app.Ch.Input.Placeholder = "Asistan (LLM) çekirdek modda kapalı — tam mod: GES_Baslat";
        end

        function warmUp(app)
            try
                c = app.Ctx;
                c.Now = c.Horizon;
                ges.agents.diagnoseDay(c, app.Engine.Ids(1), c.Now - days(1));
            catch
            end
            if app.Layers == "core"
                return
            end
            app.startLlm("LLM yükleniyor", {struct("role", "user", "content", "ok")}, ...
                {"Model", app.Ctx.Model, "Timeout", 180}, @(~, ~) []);
        end

        function onPanelReady(app, ev, which)
            if ev.HTMLEventName == "goPage"
                app.showPage(string(ev.HTMLEventData.page));
                return
            end
            if ev.HTMLEventName ~= "ready"
                return
            end
            if which == "notify"
                app.pushNotifications();
            else
                app.pushChat();
            end
        end

        function pushNotifications(app)
            sendEventToHTMLSource(app.Nt.Html, "set", struct("items", {num2cell(app.Notifications)}));
        end

        function pushChat(app)
            items = app.ChatLog;
            for k = 1:numel(items)
                if items(k).go ~= ""
                    items(k).go = app.PageTitles(app.Pages == items(k).go);
                end
            end
            goKeys = string({app.ChatLog.go});
            sendEventToHTMLSource(app.Ch.Html, "set", struct("items", {num2cell(items)}, "typing", app.ChatTyping, ...
                "goKeys", {cellstr(goKeys)}));
        end

        %% ------------------------------------------------------------------ arka plan işleri
        function startLlm(app, label, messages, llmArgs, onDone)
            app.setBusy(label, true);
            f = ges.llm.ollamaChatAsync(messages, @(reply, err) app.llmDone(label, onDone, reply, err), llmArgs{:});
            app.trackFuture(f);
        end

        function llmDone(app, label, onDone, reply, err)
            if ~isvalid(app) || isempty(app.Fig) || ~isvalid(app.Fig)
                return
            end
            app.setBusy(label, false);
            try
                onDone(reply, err);
            catch e
                app.addNotification("Hata (" + label + "): " + e.message, "error");
            end
        end

        function trackFuture(app, f)
            keep = cellfun(@(x) x.State ~= "finished", app.Pending);
            app.Pending = [app.Pending(keep), {f}];
        end

        function setBusy(app, label, on)
            if on
                app.BusyLabels(end+1) = label;
            else
                k = find(app.BusyLabels == label, 1);
                app.BusyLabels(k) = [];
            end
            if isempty(app.BusyLabels)
                app.Header.Busy.Text = "✓ hazır";
                app.Header.Busy.FontColor = [0.2 0.55 0.3];
            else
                app.Header.Busy.Text = "⏳ arka planda: " + strjoin(unique(app.BusyLabels, "stable"), ", ");
                app.Header.Busy.FontColor = [0.75 0.45 0.05];
            end
        end

        %% ------------------------------------------------------------------ harita köprüsü
        function onHtmlEvent(app, src, event)
            try
                switch event.HTMLEventName
                    case "ready"
                        app.mapInit();
                    case "tileClicked"
                        id = string(event.HTMLEventData.id);
                        if ~ismember(id, [app.Engine.Ids; app.Engine.HoldoutIds])
                            error("Geçersiz cihaz kimliği.");
                        end
                        app.select(id);
                    case "nodeClicked"
                        app.selectMapNode(string(event.HTMLEventData.node));
                    case "horizon"
                        app.applyHorizon(string(event.HTMLEventData.h));
                end
            catch err
                sendEventToHTMLSource(src, "error", err.message);
            end
        end

        %% ------------------------------------------------------------------ akış
        function togglePlay(app)
            if strcmp(app.Timer.Running, "on")
                stop(app.Timer);
                app.Header.Play.Text = "▶ Oynat";
            else
                start(app.Timer);
                app.Header.Play.Text = "⏸ Duraklat";
            end
        end

        function setSpeed(app, k)
            app.StepsPerTick = k;
        end

        function toggleChat(app, src)
            if app.Outer.ColumnWidth{2} == 0
                app.Outer.ColumnWidth{2} = 380;
                src.Text = "💬 Asistanı gizle";
            else
                app.Outer.ColumnWidth{2} = 0;
                src.Text = "💬 Asistanı göster";
            end
        end

        function onSeek(app)
            d = app.Header.Date.Value;
            if isnat(d)
                return
            end
            t = datetime(year(d), month(d), day(d), app.Header.Hour.Value, app.Header.Minute.Value, 0, ...
                TimeZone=app.Engine.Times(1).TimeZone);
            app.seekTo(t);
        end

        function seekTo(app, t)
            [t0, t1] = app.Engine.range();
            if t < t0 || t > t1
                uialert(app.Fig, sprintf("Seçilebilir aralık: %s – %s.", ...
                    string(t0, "dd.MM.yyyy HH:mm"), string(t1, "dd.MM.yyyy HH:mm")), "Zamana atla");
                return
            end
            snap = app.Engine.seek(t);
            app.Ctx.Now = snap.Time;
            app.Header.Date.Value = datetime(year(snap.Time), month(snap.Time), day(snap.Time));
            app.Header.Hour.Value = hour(snap.Time);
            app.Header.Minute.Value = 15 * floor(minute(snap.Time) / 15);
            app.CabinNoteTime = containers.Map("KeyType", "double", "ValueType", "any");
            app.ThermalNoteTime = containers.Map("KeyType", "char", "ValueType", "any");
            app.DiagTime = NaT;
            app.renderHeader(snap);
            app.renderPage(true);
            app.addNotification(sprintf("Zaman %s'e alındı (%d/%d evirici veri gönderiyor).", ...
                string(snap.Time, "dd.MM.yyyy HH:mm"), snap.NumReporting, numel(snap.Pact)), "seek");
        end

        function onTick(app)
            if app.Engine.atEnd()
                stop(app.Timer);
                app.Header.Play.Text = "▶ Oynat";
                app.addNotification("Oynatma sonu: " + string(app.Engine.Times(end), "dd.MM.yyyy HH:mm"), "system");
                return
            end
            snap = app.Engine.step(app.StepsPerTick);
            app.Ctx.Now = snap.Time;
            app.renderHeader(snap);
            alerts = snap.NewAlerts;
            if ~isempty(alerts)
                [~, loc] = ismember(alerts, app.Engine.Ids);
                known = snap.NumDead(loc) > 0;
                individual = alerts(known);
                alerts = alerts(~known);
                cabs = strings(0, 1);
                if ~isempty(alerts)
                    [g, cabs] = findgroups(extractBetween(alerts(:), "K", "-"));
                end
                for k = 1:numel(cabs)
                    ids = alerts(g == k);
                    if numel(ids) >= 4
                        app.cabinNote(str2double(cabs(k)), ids, snap.Time);
                    else
                        individual = [individual; ids]; %#ok<AGROW>
                    end
                end
                for id = individual(1:min(app.MaxDiagnosesPerTick, end))'
                    app.handleAlert(id, snap.Time);
                end
            end
            app.thermalNotes(snap);
            app.renderPage(false);
        end

        function renderHeader(app, snap)
            app.Header.Time.Text = string(snap.Time, "dd MMM yyyy  HH:mm");
        end

        function thermalNotes(app, snap)
            th = snap.State == "thermal";
            if ~any(th)
                return
            end
            i = app.Engine.Index;
            dt = app.dtHours();
            winSteps = max(1, round(2 / dt) - 1);
            loss2h = sum(double(app.Engine.ThrLoss(max(1, i - winSteps):i, :)), 1, "omitnan")' * dt;
            for c = unique(app.Engine.Cabin)'
                inC = app.Engine.Cabin == c & snap.State ~= "night" & snap.State ~= "offline";
                n = nnz(inC);
                k = nnz(th & inC);
                if n == 0 || k == 0
                    continue
                end
                key = sprintf("cabin%d", c);
                if n == 1
                    key = char(app.Engine.Ids(find(inC, 1)));
                    if isKey(app.ThermalNoteTime, key) && snap.Time - app.ThermalNoteTime(key) < app.ThermalNoteGap
                        continue
                    end
                    app.ThermalNoteTime(key) = snap.Time;
                    app.addNotification(sprintf("SmartGrid-Twin (%s): evirici ısıl kısmada / MPP dışı güç düşürmede (sıcaklık %.1f °C, son 2 saatte kayıp ≈ %s). " + ...
                        "Rüzgar soğutmasını ve havalandırmayı kontrol edin.", ...
                        key, snap.Tcab(find(inC, 1)), energyText(sum(loss2h(th & inC)))), "check", snap.Time, "", "ISIL KISMA");
                elseif k / n >= app.ThermalShare
                    if isKey(app.ThermalNoteTime, key) && snap.Time - app.ThermalNoteTime(key) < app.ThermalNoteGap
                        continue
                    end
                    app.ThermalNoteTime(key) = snap.Time;
                    tc = snap.Tcab(th & inC);
                    app.addNotification(sprintf("Kabin %d: %d/%d invertör ısıl kısmada (iç sıcaklık %.0f–%.0f °C), son 2 saatte kısma kaybı ≈ %s. " + ...
                        "Arıza değil, soğutma yetersizliği: kabin havalandırması, invertör fanları ve toz filtrelerini kontrol edin.", ...
                        c, k, n, min(tc), max(tc), energyText(sum(loss2h(th & inC)))), "info", snap.Time, "", "ISIL KISMA");
                elseif k / n <= 0.10
                    for idx = find(th & inC)'
                        key = char(app.Engine.Ids(idx));
                        if isKey(app.ThermalNoteTime, key) && snap.Time - app.ThermalNoteTime(key) < hours(24)
                            continue
                        end
                        app.ThermalNoteTime(key) = snap.Time;
                        num = double(regexp(app.Engine.Ids(idx), "\d+", "match"));
                        app.addNotification(sprintf("Kabin-%d INV-%02d: kabin komşuları normalken bu invertör ısıl kısmada (iç sıcaklık %.0f °C, son 2 saatte kayıp ≈ %s). " + ...
                            "İnvertöre özgü soğutma sorunu şüphesi: fanları ve toz filtresini kontrol edin.", ...
                            num(1), num(2), snap.Tcab(idx), energyText(loss2h(idx))), "check", snap.Time, "", "ISIL KISMA");
                    end
                end
            end
        end

        function cabinNote(app, cabin, ids, t)
            if isKey(app.CabinNoteTime, cabin) && t - app.CabinNoteTime(cabin) < app.CabinNoteGap
                return
            end
            app.CabinNoteTime(cabin) = t;
            nCab = nnz(app.Engine.Cabin == cabin);
            app.addNotification(sprintf("Kabin %d: %d/%d invertör aynı anda beklenenin altında → ortak etki (bulut/gölge/sensör), tekil arıza değil; izleniyor.", ...
                cabin, numel(ids), nCab), "info", t);
        end

        function handleAlert(app, id, t)
            try
                r = ges.agents.diagnoseDay(app.Ctx, id, t);
                [msg, p] = ges.agents.alertText(app.Ctx, r);
                tag = "";
                if p.Severity == "alarm"
                    tag = upper(p.LabelTr);
                end
                if r.Fusion.Label == "thermal_derating"
                    p.Severity = "check";
                    tag = "ISIL KISMA";
                end
                if app.Nt.LlmCheck.Value && p.Severity ~= "info"
                    token = app.newToken();
                    app.addNotification(msg, p.Severity, t, token, tag);
                    [m, a] = ges.agents.arbiterRequest(app.Ctx, r);
                    app.startLlm("bildirim", m, a, @(reply, err) app.replaceToken(token, reply, err));
                else
                    app.addNotification(msg, p.Severity, t, "", tag);
                end
            catch err
                app.addNotification(id + " teşhis edilemedi: " + err.message, "error", t);
            end
        end

        function token = newToken(app)
            app.TokenCounter = app.TokenCounter + 1;
            token = sprintf("llm-%d", app.TokenCounter);
        end

        function replaceToken(app, token, reply, err)
            k = find([app.Notifications.token] == token, 1);
            if isempty(k)
                return
            end
            app.Notifications(k).pending = false;
            if isempty(err) && strlength(strtrim(reply.Content)) > 0
                app.Notifications(k).text = replace(ges.llm.plainText(reply.Content), newline, " ");
                app.Notifications(k).llm = true;
            end
            app.pushNotifications();
        end

        %% ------------------------------------------------------------------ seçim ve ufuk
        function select(app, id)
            if ismember(id, app.Engine.HoldoutIds)
                uialert(app.Fig, id + " test cihazı: verisi nihai değerlendirmeye kadar gizli.", "Test cihazı", Icon="info");
                return
            end
            app.Selected = id;
            app.LastDiagnosis = [];
            app.DiagTime = NaT;
            app.An.Feedback.Value = "";
            app.An.Note.Value = "";
            sendEventToHTMLSource(app.Mp.Html, "select", struct("id", char(id)));
            app.An.Inverter.Value = char(id);
            app.renderPage(true);
        end

        function A = assess(app, h)
            i = app.Engine.Index;
            if app.AssessCache.index ~= i
                app.AssessCache = struct("index", i, "day", [], "week", [], "instant", []);
            end
            if isempty(app.AssessCache.(h))
                app.AssessCache.(h) = app.Engine.assess(h);
            end
            A = app.AssessCache.(h);
        end

        function applyHorizon(app, h)
            if ~isKey(app.HorizonTr, h)
                error("Geçersiz değerlendirme ufku: %s", h);
            end
            app.Horizon = h;
            app.renderPage(true);
        end

        function lines = horizonLines(app, A, k)
            if A.Horizon == "instant"
                lines = A.Label + ": " + app.StateTr(A.State(k));
                return
            end
            lines = A.Label;
            lines(2) = "Durum: " + app.StateTr(A.State(k)) + ifelse(A.Horizon == "day", ...
                " (gün içinde en az 1 saat süren en ağır durum)", " (7 günün en az 2'sinde görülen en ağır durum)");
            if isnan(A.Ratio(k))
                lines(3) = "Üretim değerlendirilemedi (veri yok)";
            else
                lines(3) = sprintf("Üretim %s / beklenen %s → performans %%%.1f", energyText(A.Eact(k)), ...
                    energyText(A.Eexp(k)), 100 * A.Ratio(k));
                parts = ["ısıl kısma" "DC dizi/string" "şebeke/L1" "diğer (trip, dönüşüm)"];
                v = [A.LossThermal(k) A.LossDead(k) A.LossGrid(k) A.LossOther(k)];
                if v(4) < 0
                    parts(4) = "model payı (beklenenden fazla)";
                end
                thr = ifelse(A.Eexp(k) < 50, 0.02, 0.5);
                show = abs(v) >= thr;
                if any(show)
                    lines(4) = sprintf("Kayıp %s: ", energyText(A.Eexp(k) - A.Eact(k))) + ...
                        strjoin(arrayfun(@(p, x) p + " " + energyText(x), parts(show)', v(show)'), " · ");
                end
            end
            items = strings(0, 1);
            for s = ["alarm" "warning" "chronic" "grid" "thermal" "watch" "offline"]
                j = find(A.Names == s);
                if A.Hours(k, j) >= 0.25
                    t = sprintf("%s %.1f sa", app.StateLower(s), A.Hours(k, j));
                    if A.Horizon == "week" && A.Days(k, j) > 0
                        t = t + sprintf(" (%d günde ≥ 1 sa)", A.Days(k, j));
                    end
                    items(end+1) = t; %#ok<AGROW>
                end
            end
            if ~isempty(items)
                lines(end+1) = "Süreler: " + strjoin(items, " · ");
            end
        end

        function [t0, t1, day0] = horizonWindow(app)
            tNow = app.Engine.Times(app.Engine.Index);
            if app.Horizon == "instant"
                day0 = dateshift(tNow, "start", "day");
                t0 = day0;
                t1 = day0 + days(1);
            else
                A = app.assess(app.Horizon);
                day0 = dateshift(A.T0, "start", "day");
                t0 = A.T0;
                t1 = A.T1 + minutes(round(60 * app.dtHours()));
            end
        end

        function V = periodDays(app, id, dayList)
            V = [];
            todo = false(numel(dayList), 1);
            parts = cell(numel(dayList), 1);
            for k = 1:numel(dayList)
                key = char(id + "|" + string(dayList(k), "yyyyMMdd"));
                if isKey(app.PeriodCache, key)
                    parts{k} = app.PeriodCache(key);
                else
                    todo(k) = true;
                end
            end
            if any(todo)
                W = ges.agents.periodView(app.Ctx, id, dayList(todo));
                idx = find(todo);
                for j = 1:numel(idx)
                    parts{idx(j)} = W(j);
                    if app.Ctx.Now >= dayList(idx(j)) + days(1)
                        app.PeriodCache(char(id + "|" + string(dayList(idx(j)), "yyyyMMdd"))) = W(j);
                    end
                end
            end
            if app.PeriodCache.Count > 400
                remove(app.PeriodCache, keys(app.PeriodCache));
            end
            V = [parts{:}];
        end

        %% ------------------------------------------------------------------ eylemler
        function onExplain(app)
            if isempty(app.LastDiagnosis)
                app.addNotification("Açıklama için önce bir evirici seçin (Analiz sayfası).", "system");
                return
            end
            r = app.LastDiagnosis;
            app.An.Explain.Enable = "off";
            [m, a] = ges.agents.arbiterRequest(app.Ctx, r);
            app.startLlm("açıklama", m, a, @(reply, err) app.explainDone(r, reply, err));
        end

        function explainDone(app, r, reply, err)
            app.An.Explain.Enable = "on";
            if isempty(err) && strlength(strtrim(reply.Content)) > 0
                msg = replace(ges.llm.plainText(reply.Content), newline, " ");
            else
                msg = ges.agents.alertText(app.Ctx, r) + "  (LLM'e ulaşılamadı; şablon)";
            end
            app.addNotification(msg, "llm");
        end

        function onVlm(app)
            if isempty(app.LastDiagnosis)
                app.addNotification("VLM için önce bir evirici seçin (Analiz sayfası).", "system");
                return
            end
            r = app.LastDiagnosis;
            app.An.Vlm.Enable = "off";
            app.An.Vlm.Text = "⏳ VLM bakıyor…";
            try
                [m, a] = ges.agents.vlmRequest(app.Ctx, r.Image, r.DayData);
            catch err
                app.vlmReset();
                app.addNotification("VLM isteği hazırlanamadı: " + err.message, "error");
                return
            end
            app.startLlm("VLM", m, a, @(reply, e) app.vlmDone(r, reply, e));
        end

        function vlmDone(app, r, reply, err)
            app.vlmReset();
            v = ges.agents.vlmParse(app.Ctx, reply, err);
            r.Vlm = v;
            if ~isempty(app.LastDiagnosis) && app.LastDiagnosis.Id == r.Id && app.LastDiagnosis.Day == r.Day
                app.LastDiagnosis = r;
                v0 = string(app.An.Agent.Value);
                app.An.Agent.Value = [v0(1); app.describe(r)];
            end
            [~, p] = ges.agents.alertText(app.Ctx, r);
            if v.Label == ""
                app.addNotification(p.Name + ": " + v.ReasonTr, "error");
            else
                l1 = string(ifelse(v.Label == "healthy", "sağlıklı", "sağlıksız"));
                app.addNotification(sprintf("%s (%s gün, %.0f sn): %s (güven %%%.0f). %s", p.Name, r.Day, ...
                    v.Seconds, l1, 100 * v.Confidence, v.ReasonTr), "vlm");
            end
        end

        function vlmReset(app)
            app.An.Vlm.Enable = "on";
            app.An.Vlm.Text = "🔍 VLM 2. görüş";
        end

        function lines = describe(app, r)
            % Üç görüş + uzlaşı (Analiz sayfası "Teşhis" kutusu).
            n = r.Numeric;
            names = @(labs) strjoin(arrayfun(@(c) app.classTr(c), string(labs)), " + ");
            resDef = "—";
            if ~isnan(n.ResDefPct)
                resDef = sprintf("%%%.1f", max(n.ResDefPct, 0));
            end
            o1 = r.Opinions(1);
            if o1.Available
                t1 = sprintf("%s %s (güven %.2f%s)", names(o1.Labels), n.Detail, n.Confidence, ...
                    string(ifelse(o1.Hard, "; deterministik ölçüm", "")));
            else
                t1 = "karar veremedi (" + o1.Evidence + ")";
            end
            lines = sprintf("1. görüş · Sensör ve fizik kuralları [çekirdek]: %s — açıklanamayan eksik %s, devre dışı dizi %d", ...
                t1, resDef, n.DeadStrings);
            o2 = r.Opinions(2);
            if ~o2.Available
                lines(end+1) = "2. görüş · Görsel desen (CNN) [araştırma]: kapalı — çekirdek modda yüklenmez";
            elseif isfield(r, "CnnML") && ~isempty(r.CnnML)
                ml = r.CnnML;
                if isempty(ml.Labels)
                    mlTxt = "sorun görmüyor (sağlıklı)";
                else
                    [~, ix] = ismember(ml.Labels, ml.Classes);
                    mlTxt = strjoin(compose("%s (%.2f)", arrayfun(@(c) app.classTr(c), string(ml.Labels(:))), ml.Probs(ix)'), " + ");
                end
                lines(end+1) = "2. görüş · Görsel desen, çok etiketli CNN [araştırma]: " + mlTxt;
            else
                lines(end+1) = sprintf("2. görüş · Görsel desen, CNN topluluğu [araştırma]: %s (%.2f)", app.classTr(r.Cnn.Label), max(r.Cnn.Probs));
            end
            o3 = r.Opinions(3);
            isSingle = numel(app.Engine.Ids) <= 1;
            op3Title = ifelse(isSingle, "3. görüş · Elektriksel ikiz ve öz-akran", "3. görüş · Komşu karşılaştırması");
            if o3.Available
                nPeer = 0;
                if ~isempty(r.Peer.Features) && ismember("NumPeers", string(r.Peer.Features.Properties.VariableNames))
                    nPeer = r.Peer.Features.NumPeers(1);
                end
                t3 = ifelse(o3.Label == "", "belirgin sorun yok", names(o3.Labels));
                peerDesc = ifelse(isSingle, sprintf("%d öz-akran gün + DC/AC/L1 ikizi", nPeer), sprintf("%d komşu; sensör ve model kullanmaz", nPeer));
                lines(end+1) = sprintf("%s [çekirdek, %s]: %s — %s", op3Title, peerDesc, t3, o3.Evidence);
            else
                lines(end+1) = op3Title + " [çekirdek]: karar veremedi (" + string(ifelse(o3.Evidence == "", "akran/ikiz verisi yok", o3.Evidence)) + ")";
            end
            if isfield(n, "ThrottleSteps") && n.ThrottleSteps > 0
                sig = "4-kadranlı V/I zarf imzası";
                if isfield(n, "ThrottleSource") && n.ThrottleSource == "P"
                    sig = "güç+sıcaklık imzası";
                end
                lines(end+1) = sprintf("   Isıl kısma / güç sınırlama ayrıntısı (%s): bugün %.1f saat, kayıp %s, tepe sıcaklık %.1f °C", ...
                    sig, n.ThrottleSteps * app.dtHours(), energyText(n.ThrottleLossKwh), n.TcabMax);
            end
            if ~isempty(r.Cnn) && isfield(r, "CnnML") && ~isempty(r.CnnML)
                lines(end+1) = sprintf("   (bilgi) Tek etiketli CNN topluluğu: %s (%.2f) — uzlaşıya çok etiketli model katılır", ...
                    app.classTr(r.Cnn.Label), max(r.Cnn.Probs));
            end
            if isfield(r, "Fed") && ~isempty(r.Fed)
                lines(end+1) = sprintf("   (bilgi) Federe model (FedBN/AdaBN, rejim %d): %s (%.2f) — karara girmez", ...
                    r.Fed.Cabin, app.classTr(r.Fed.Label), r.Fed.Prob);
            end
            if app.Layers == "full"
                if isempty(r.Vlm)
                    lines(end+1) = "   (bilgi) VLM: çalıştırılmadı (isteğe bağlı: 🔍 VLM 2. görüş, ~20 sn; karara girmez)";
                elseif r.Vlm.Label == ""
                    lines(end+1) = "   (bilgi) VLM: " + r.Vlm.ReasonTr;
                else
                    l1 = string(ifelse(r.Vlm.Label == "healthy", "sağlıklı", "sağlıksız"));
                    lines(end+1) = sprintf("   (bilgi) VLM: %s (%.2f) — %s; karara girmez", l1, r.Vlm.Confidence, r.Vlm.ReasonTr);
                end
            end
            f = r.Fusion;
            [~, p] = ges.agents.alertText(app.Ctx, r);
            lines(end+1) = sprintf("UZLAŞI: %s — %d görüş karar verdi: %d destek, %d karşı, %d göremez", ...
                f.LevelTr, f.Available, f.SupportN, f.AgainstN, f.BlindN);
            verdict = sprintf("KARAR: %s (güven %.2f)", app.classTr(f.Label), f.Confidence);
            extra = f.Labels(f.Labels ~= f.Label);
            if ~isempty(extra)
                verdict = verdict + " · ek bulgu: " + names(extra);
            end
            if f.Check
                verdict = verdict + " — ⚠ saha kontrolü önerilir";
            end
            lines(end+1) = verdict;
            if f.Note ~= ""
                lines(end+1) = "Not: " + f.Note;
            end
            if p.Severity ~= "info" || f.Label == "uncertain"
                lines(end+1) = "Öneri: " + p.Action;
            end
            lines = lines(:);
        end

        function t = classTr(app, c)
            k = find(app.Classes == string(c), 1);
            if isempty(k)
                t = "Belirsiz";
            else
                t = app.ClassNamesTr(k);
            end
        end

        function onFeedback(app)
            if isempty(app.LastDiagnosis)
                app.addNotification("Geri bildirim için önce bir evirici seçin.", "system");
                return
            end
            if app.An.Feedback.Value == ""
                app.addNotification("Kaydetmek için önce 'Sahada ne buldunuz?' kutusundan gözlenen durumu seçin.", "system");
                return
            end
            r = app.LastDiagnosis;
            ges.learning.recordFeedback(app.Cfg, app.Selected, app.Engine.Times(app.Engine.Index), ...
                r.Fusion.Label, string(app.An.Feedback.Value), string(app.An.Note.Value));
            tr = @(c) app.classTr(c);
            app.addNotification(sprintf("%s: model '%s' demişti, sahada '%s' olarak kaydedildi (artifacts/feedback; saha doğrulaması için).", ...
                app.Selected, tr(r.Fusion.Label), tr(app.An.Feedback.Value)), "feedback");
            app.An.Note.Value = "";
            app.An.Feedback.Value = "";
        end

        %% ------------------------------------------------------------------ asistan (sayfa-kapsamlı)
        function onChat(app)
            q = strtrim(string(app.Ch.Input.Value));
            if q == "" || app.Ch.Send.Enable == "off"
                return
            end
            app.Ch.Input.Value = "";
            page = app.Page;
            if app.Layers == "core"
                app.ChatLog(end+1) = struct("role", "user", "text", q, "tools", "", "page", app.PageTitles(app.Pages == page), "go", "");
                app.ChatLog(end+1) = struct("role", "assistant", "text", "Asistan (yerel LLM) araştırma katmanındadır ve çekirdek modda kapalıdır. " + ...
                    "Sayfadaki tüm sayılar ve teşhisler LLM olmadan hesaplanır. Asistanı kullanmak için paneli tam modda açın: GES_Baslat", ...
                    "tools", "", "page", app.PageTitles(app.Pages == page), "go", "");
                app.pushChat();
                return
            end
            app.ChatLog(end+1) = struct("role", "user", "text", q, "tools", "", "page", app.PageTitles(app.Pages == page), "go", "");
            app.ChatTyping = "Asistan " + app.PageTitles(app.Pages == page) + " sayfasını okuyor";
            app.pushChat();
            app.Ch.Send.Enable = "off";
            try
                info = struct("Name", page, "Title", app.PageTitles(app.Pages == page), ...
                    "Chunks", app.pageContext(page), "Directory", app.pageDirectory(), "Memory", app.Memory);
                req = app.PageChat.ask(app.Ctx, q, info);
                app.startLlm("sohbet", req.Messages, req.Args, @(reply, err) app.chatReply(reply, err));
            catch err
                app.PageChat.fail("Soru işlenemedi: " + err.message);
                app.chatReply([], err);
            end
        end

        function d = pageDirectory(app)
            d = struct("Name", cellstr(app.Pages), "Title", cellstr(app.PageTitles), "Topics", cellstr(app.PageTopics'));
        end

        function chatReply(app, reply, err)
            go = "";
            if ~isempty(err)
                msg = "LLM'e ulaşılamadı (" + string(err.message) + "). Ollama servisinin çalıştığını kontrol edin.";
            else
                msg = app.PageChat.consume(reply);
                go = app.pageKey(app.PageChat.GoPage);
                if go == "" && app.PageChat.Redirects
                    fold = @(s) lower(replace(string(s), ["ı" "İ" "ş" "Ş" "ğ" "Ğ" "ü" "Ü" "ö" "Ö" "ç" "Ç"], ...
                        ["i" "i" "s" "s" "g" "g" "u" "u" "o" "o" "c" "c"]));
                    hit = find(contains(fold(msg), fold(app.PageTitles)) & app.Pages ~= app.Page, 1);
                    if ~isempty(hit)
                        go = app.Pages(hit);
                    end
                end
                if go == app.Page
                    go = "";
                end
            end
            src = "";
            if isempty(err) && ~isempty(app.PageChat.Sources)
                src = "kaynak: " + strjoin(app.PageChat.Sources(1:min(3, end)), " · ");
            end
            app.ChatLog(end+1) = struct("role", "assistant", "text", msg, "tools", src, ...
                "page", app.PageTitles(app.Pages == app.Page), "go", go);
            app.ChatTyping = "";
            app.pushChat();
            app.Ch.Send.Enable = "on";
        end

        function onPin(app)
            pageTitle = app.PageTitles(app.Pages == app.Page);
            c = app.pageContext(app.Page);
            text = c(1).Text;
            if numel(c) >= 2 && app.Page ~= "help"
                text = text + " " + c(2).Text;
            end
            last = find(string({app.ChatLog.role}) == "assistant" & string({app.ChatLog.page}) == pageTitle, 1, "last");
            if ~isempty(last)
                text = text + " | Asistan yanıtı: " + app.ChatLog(last).text;
            end
            title = pageTitle + " · " + string(app.Engine.Times(app.Engine.Index), "dd.MM HH:mm");
            if ismember(app.Page, ["map" "analysis"]) && ~isempty(app.Selected)
                title = title + " · " + app.Selected;
            end
            app.Memory(end+1) = struct("Time", app.Engine.Times(app.Engine.Index), "Page", pageTitle, ...
                "Title", title, "Text", extractBefore(text + " ", min(strlength(text) + 1, 1500)));
            app.refreshMemory();
            app.ChatLog(end+1) = struct("role", "assistant", "text", "📌 Hafızaya alındı: " + title + ...
                ". Başka bir sayfada 'hafızadakiyle karşılaştır' diyebilirsiniz.", "tools", "", ...
                "page", pageTitle, "go", "");
            app.pushChat();
        end

        function clearMemory(app)
            app.Memory = app.Memory([]);
            app.refreshMemory();
        end

        function refreshMemory(app)
            if isempty(app.Memory)
                app.Ch.Memory.Text = "📌 Hafıza boş — bir sayfadaki bilgiyi saklamak için 'Hafızaya al'.";
            else
                app.Ch.Memory.Text = "📌 Hafıza (" + numel(app.Memory) + "): " + strjoin(string({app.Memory.Title}), "  |  ");
            end
        end

        %% ------------------------------------------------------------------ hava / üretim tahmini
        function onWeather(app)
            if app.Fc.Weather.Enable == "off"
                return
            end
            app.Fc.Weather.Enable = "off";
            app.Fc.Weather.Text = "⏳ Tahmin alınıyor…";
            app.setBusy("hava tahmini", true);
            f = parfeval(backgroundPool, @ges.forecast.fetchOpenMeteo, 1, ...
                app.Cfg.site.latitude, app.Cfg.site.longitude);
            afterEach(f, @(fut) app.weatherFetched(fut), 0, PassFuture=true);
            app.trackFuture(f);
        end

        function weatherFetched(app, fut)
            if ~isvalid(app) || isempty(app.Fig) || ~isvalid(app.Fig)
                return
            end
            app.setBusy("hava tahmini", false);
            app.Fc.Weather.Enable = "on";
            app.Fc.Weather.Text = "🌦 Hava tahmini al (internet)";
            if ~isempty(fut.Error)
                app.Fc.Status.Text = "İnternete ulaşılamadı: " + string(fut.Error.message) + ...
                    ". Sistem çevrimdışı çalışmaya devam ediyor.";
                return
            end
            try
                wx = fetchOutputs(fut);
                ctx = app.Ctx;
                ctx.Now = app.Engine.Times(app.Engine.Index);
                dev = app.Engine.devices();
                fc = ges.forecast.weatherPowerForecast(ctx, wx, dev);
                app.Forecast = struct("wx", wx, "fc", fc, "stateTime", ctx.Now, "nFaulty", nnz([dev.DeadMask]));
                app.RenderKey.forecast = "";
                app.renderForecast(true);
            catch err
                app.Fc.Status.Text = "Hava tahmini hesaplanamadı: " + err.message;
            end
        end

        function addNotification(app, msg, kind, t, token, tag)
            arguments
                app
                msg (1,1) string
                kind (1,1) string = "system"
                t = []
                token (1,1) string = ""
                tag (1,1) string = ""
            end
            if isempty(t)
                try
                    t = app.Engine.Times(app.Engine.Index);
                catch
                    t = NaT;
                end
            end
            timeText = "";
            if ~isnat(t)
                timeText = string(t, "dd.MM.yyyy HH:mm");
            end
            item = struct("time", timeText, "kind", kind, "tag", tag, "text", msg, "token", token, ...
                "llm", false, "pending", token ~= "");
            app.Notifications = [item, app.Notifications];
            app.Notifications = app.Notifications(1:min(200, end));
            if isfield(app.Nt, "Html") && isvalid(app.Nt.Html)
                app.pushNotifications();
            end
            if isfield(app.Nt, "Badge") && isvalid(app.NavButtons.notify)
                nAlarm = nnz(ismember(string({app.Notifications.kind}), ["alarm" "check"]));
                app.NavButtons.notify.Text = "🔔 Bildirimler" + ifelse(nAlarm > 0, " (" + nAlarm + ")", "");
            end
        end
    end
end
