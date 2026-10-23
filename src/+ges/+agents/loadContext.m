function ctx = loadContext(cfg, now, opts)
%LOADCONTEXT Ajanların ve LLM araçlarının ortak çalışma bağlamını yükler.
%   ctx = ges.agents.loadContext(cfg, now) — now: simülasyon / gerçek "şimdiki zaman".
%   Modeller (M1, skalogram normalizasyonu; araştırma katmanı açıksa çok etiketli CNN) ve raporlar (olay kataloğu,
%   tozlanma, PdM) bir kez belleğe alınır; araçlar yalnızca now ve öncesini görür
%   (gelecek bilgisi sızmaz). Cihaz zaman serileri ilk erişimde önbelleğe alınır.
arguments
    cfg (1,1) struct
    now (1,1) datetime
    opts.Split (1,1) string = "train"         % işlenmiş veri havuzu (train | holdout)
    opts.LoadCnn (1,1) logical = true
    opts.Layers (1,1) string {mustBeMember(opts.Layers, ["auto" "full" "core"])} = "auto"   % core: araştırma katmanı yüklenmez
    opts.Model (1,1) string = "gemma4:e4b"
    opts.Horizon (1,1) datetime = now        % replay bitişi; araçlar yine de her çağrıda ctx.Now ile süzer
end

ctx.Cfg = cfg;
ctx.Now = now;
ctx.Layers = opts.Layers;
if ctx.Layers == "auto"
    ctx.Layers = "full";
    if isfield(cfg, "layers") && ~cfg.layers.research
        ctx.Layers = "core";
    end
end
opts.LoadCnn = opts.LoadCnn && ctx.Layers == "full";
ctx.Fleet = [];                     % komşu karşılaştırması (3. görüş) için güç matrisi: ges.opinions.fleetFromEngine
ctx.Horizon = min(opts.Horizon, cfg.split.testStart - minutes(15));   % önbelleğin üst sınırı (test dilimi asla)
if isfield(cfg, "workspace")
    ctx.Horizon = opts.Horizon;                 % yüklenen veri seti (ges.ingest): kendi dönemi oynatılır
end
ctx.Split = opts.Split;
ctx.Model = opts.Model;
proc = fullfile(cfg.paths.processed, "train");
ctx.Catalog = load(fullfile(cfg.paths.anomaly, "events_catalog.mat")).catalog;   % v2 olay kataloğu
v2soil = fullfile(cfg.paths.root, "artifacts", "v2", "d02_dryspells.mat");
if isfile(v2soil) && ~isfield(cfg, "workspace")
    ctx.SoilingV2 = load(v2soil, "SR", "days0", "ids", "coplanar");               % v2 doğrulanmış tozlanma
end
ctx.Bundle = load(fullfile(cfg.paths.models, cfg.files.m1)).bundle;            % M1-v2 (kısma-farkında)
ctx.Norm = load(fullfile(cfg.paths.models, "scalogram_norm.mat"));
ctx.Classes = ["healthy" "string_fault" "inverter_trip" "thermal_derating" "soiling" "grid_event"];
ctx.ClassTr = dictionary(ctx.Classes, ["sağlıklı" "string arızası" "invertör arızası/trip" ...
    "ısıl kısma" "tozlanma" "şebeke/kabin olayı"]);

reg = load(fullfile(cfg.paths.interim, "train", "registry.mat")).registry;
ctx.Inverters = sort(reg.Id(reg.Kind == "inverter"));

% Tek etiketli CNN topluluğu (isteğe bağlı, bilgi amaçlı): yalnızca model dosyaları duruyorsa yüklenir.
% 2026-10-12'den beri 2. görüş çok etiketli CNN'dir; topluluk dosyaları sadeleştirmede kaldırıldı.
ctx.Cnn = struct("Nets", {{}}, "InputSize", {{}}, "Ensemble", [], "Dir", "");
if opts.LoadCnn && isfield(cfg.files, "cnnDir") && cfg.files.cnnDir ~= ""
    eFile = fullfile(cfg.paths.models, cfg.files.cnnDir, "ensemble.mat");
    if isfile(eFile)
        E = load(eFile).ensemble;
        nets = fullfile(cfg.paths.models, cfg.files.cnnDir, E.Models + ".mat");
        if all(arrayfun(@isfile, nets))
            ctx.Cnn.Ensemble = E;
            ctx.Cnn.Dir = cfg.files.cnnDir;
            for f = nets
                S = load(f, "net", "inputSize");
                ctx.Cnn.Nets{end+1} = S.net;
                ctx.Cnn.InputSize{end+1} = S.inputSize;
            end
        end
    end
end
% Çok etiketli görsel ajan (v2-L06): aynı günde birden fazla sorun (ör. string arızası + ısıl kısma)
ctx.CnnML = [];
mlFile = fullfile(cfg.paths.models, "cnn_ml", "resnet18_ml.mat");
if opts.LoadCnn && isfile(mlFile)
    ctx.CnnML = load(mlFile, "net", "thr", "classesOut", "inputSize");
end
% Federe görsel model (v2-L04, FedBN): her kabinin kişisel modeli; ham veri paylaşılmadan eğitildi (bilgi amaçlı)
ctx.Fed = [];
fedFile = fullfile(cfg.paths.models, "federated_v2", "fedbn_seed1.mat");
if opts.LoadCnn && isfile(fedFile)
    ctx.Fed = load(fedFile, "pers", "sites", "classes");
end
ctx.Cache = containers.Map();        % Id -> struct(TT, Steps, info), ilk erişimde doldurulur
end
