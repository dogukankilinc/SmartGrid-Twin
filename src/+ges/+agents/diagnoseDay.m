function r = diagnoseDay(ctx, id, day, opts)
%DIAGNOSEDAY Bir evirici-günü (BTÜ SmartGridLab WR13TL22-8231) için üç bağımsız görüş + uzlaşı (LLM aracı: diagnose_day).
%   r = ges.agents.diagnoseDay(ctx, id, day)
%   Çekirdek katman (her zaman):
%     r.Numeric : 1. görüş — sensör ve fizik kuralları (dedektörler + etiketleme fonksiyonları): Label, Detail,
%                 Confidence, Votes, ResDefPct (açıklanamayan eksik), DeadStrings, GridSteps, kısma bilgisi
%     r.Peer    : 3. görüş — komşu karşılaştırması (ges.opinions.peerFeatures/peerOpinion; ctx.Fleet gerekir):
%                 Features (günlük oranlar), Opinion. Meteoroloji sensörü ve beklenen güç modeli kullanılmaz.
%   Araştırma katmanı (ctx'de modeller yüklüyse; çekirdek modda boş):
%     r.CnnML   : 2. görüş — çok etiketli görsel CNN (Labels, Probs)
%     r.Cnn     : tek etiketli CNN topluluğu (yalnızca bilgi; çok etiketli yoksa 2. görüş budur)
%     r.Fed     : federe model (bilgi amaçlı)    r.Vlm: görsel-dil modeli (UseVlm=true ise; karara girmez)
%   r.Opinions : üç görüşün ortak biçimi (ges.opinions.emptyOpinion)
%   r.Fusion   : ges.opinions.consensus çıktısı — Label, Level/LevelTr (uzlaşı düzeyi), Confidence, Check
%                (saha kontrolü önerilir), Note, Summary; geriye uyum için Conflict ve Rule
%   r.Electrical: elektriksel ikiz özeti (o günün ctx.Now'a kadar kısmı): Vl1Min/Vl1CondMed, FgridMin, RelaySteps
%                (k/18 röle adımı sayısı), GridOutageTimes (V_L1=0 ve f=0 gündüz adımları), RisoMin/RisoMorningMin,
%                EtaMedian, VdcMax, IdcMax, ResetTimes (qRebootEvent), TcellMax, WindMean
%   r.Image    : fizik-RGB skalogram (arayüz için), r.DayData: güç/beklenti/ışınım serileri
%   Yalnızca ctx.Now'a kadar olan veri kullanılır.
arguments
    ctx (1,1) struct
    id (1,1) string
    day (1,1) datetime
    opts.UseVlm (1,1) logical = false
    opts.VlmOptions (1,1) struct = struct()
end

day = dateshift(day, "start", "day");
d = ges.agents.deviceData(ctx, id);
r.Id = id;
r.Day = string(day, "yyyy-MM-dd");

% --- Sayısal ajan: son 30 günlük pencerede günlük öznitelikler + etiketleme fonksiyonları
win = d.TT.Time >= day - days(30) & d.TT.Time < day + days(1);
TT = d.TT(win, :);
St = d.Steps(ismember(d.Steps.Time, TT.Time), :);
ev = ctx.Catalog(ctx.Catalog.Id == id, :);
F = ges.label.dayFeatures(TT, St, d.D, d.info, ev);
F = ges.label.applyLabelingFunctions(F);
row = F(F.Day == day, :);
if isempty(row)
    error("ges:agents:noDay", "%s için %s günü verisi yok.", id, r.Day);
end
lab = string(row.Label);
if ismember(lab, ["uncertain" "unusable"])
    lab = "uncertain";
end
% O gün süren (şimdiye kadar başlamış) string olayları: bildirimde somut PV numarası için
active = ev(ev.Start <= ctx.Now & ev.End >= day, :);
deadPv = unique(active.PV(active.Type == "string_dead" & active.PV > 0))';
weakPv = setdiff(unique(active.PV(active.Type == "string_weak" & active.PV > 0))', deadPv);
r.Numeric = struct("Label", lab, "Detail", row.Detail, "Confidence", row.Confidence, ...
    "Votes", row.Votes, "ResDefPct", round(100 * row.ResDef, 1), "TotDefPct", round(100 * row.TotDef, 1), ...
    "DeadStrings", row.MaxDeadStrings, "DeadPV", deadPv, "WeakPV", weakPv, "GridSteps", row.GridSteps, ...
    "Sky", string(row.Sky), "M1Flag", row.M1Flag, ...
    "ThrottleSteps", getOr(row, "ThrottleSteps", 0), "ThrottleLossKwh", round(getOr(row, "ThrottleLossKwh", 0), 1), ...
    "TcabMax", round(getOr(row, "TcabMax", NaN), 1), ...
    "HasThrottleSignature", isfile(fullfile(ctx.Cfg.paths.throttle, id + ".mat")), ...   % PV gerilimi yoksa false
    "ThrottleSource", d.ThrottleSource);                % "VI" | "P" (güç+sıcaklık, B02) | ""

% --- Elektriksel ikiz özeti (SMA kolonları: U_L1, U_L1_cond, f_grid, RelayDuty, R_iso, V_dc, I_dc, Eff ...)
r.Electrical = electricalSummary(d.TT, day, ctx.Now);

% --- Görsel frekans ajanı: o günün skalogramı + 5 CNN yumuşak oylama
until = NaT(TimeZone=day.TimeZone);
if ctx.Now < day + days(1)
    until = ctx.Now;                                   % gün içi teşhis: gelecek saatler maskelenir
end
[sig, ok] = ges.scalogram.dailySignals(d.TT, d.Steps, d.info.Capacity, day, Until=until);
rgb = ges.scalogram.makeImages(ctx.Norm.fb, sig, ctx.Norm.scale);
r.Image = rgb;
r.Cnn = [];
E = ctx.Cnn.Ensemble;
if ~isempty(E)                                         % araştırma katmanı kapalıysa (çekirdek mod) atlanır
    scores = cell(1, numel(ctx.Cnn.Nets));
    perModel = struct("Model", {}, "Label", {}, "Prob", {});
    for m = 1:numel(ctx.Cnn.Nets)
        sz = ctx.Cnn.InputSize{m};
        x = dlarray(single(imresize(rgb, sz(1:2))), "SSCB");
        p = double(extractdata(predict(ctx.Cnn.Nets{m}, x)))';
        scores{m} = p(:)';
        [pm, im] = max(p);
        perModel(end+1) = struct("Model", E.Models(m), "Label", E.Classes(im), "Prob", round(pm, 2)); %#ok<AGROW>
    end
    [dec, ~, conf] = ges.model.ensembleVote(scores, E.Method, E.Weights, MinAgree=E.MinAgree, ...
        MinSupport=E.MinSupport, MinMargin=E.MinMargin);
    pE = zeros(1, numel(E.Classes));
    w = E.Weights;
    if isempty(w)
        w = ones(numel(scores), 1);
    end
    for m = 1:numel(scores)
        pE = pE + w(m) * scores{m};
    end
    pE = pE / sum(pE);
    % Topluluğun sınıfları (v2: tozlanma yok) füzyonun sınıf düzenine eşlenir; eğitilmeyen sınıf olasılığı 0
    probs = zeros(1, numel(ctx.Classes));
    [tf, loc] = ismember(E.Classes, ctx.Classes);
    probs(loc(tf)) = pE(tf);
    r.Cnn = struct("Label", E.Classes(dec), "Probs", round(probs, 3), "Conflict", conf, ...
        "PerModel", perModel, "SignalOk", ok);
end

% --- Çok etiketli görsel ajan (v2-L06): her sorun için ayrı olasılık ve dev'de seçilmiş eşik
r.CnnML = [];
if isfield(ctx, "CnnML") && ~isempty(ctx.CnnML)
    M = ctx.CnnML;
    x = dlarray(single(imresize(rgb, M.inputSize(1:2))), "SSCB");
    p = double(extractdata(predict(M.net, x)))';
    on = p >= M.thr;
    r.CnnML = struct("Labels", M.classesOut(on), "Probs", round(p, 2), "Classes", M.classesOut);
end

% --- Federe model görüşü (FedBN; kabinin kişisel modeli). Füzyona girmez, bilgi amaçlıdır.
r.Fed = [];
if isfield(ctx, "Fed") && ~isempty(ctx.Fed)
    cab = double(extractBetween(id, "K", "-"));
    k = find(ctx.Fed.sites == cab, 1);
    if ~isempty(k)
        x = single(imresize(rgb, [64 64])) / 255;
        pF = ges.federated.predictScores(ctx.Fed.pers{k}, x, UseGPU=false);
        [pm, im] = max(pF);
        r.Fed = struct("Label", ctx.Fed.classes(im), "Prob", round(pm, 2), "Cabin", cab);
    end
end

% --- VLM (isteğe bağlı; CPU'da yavaş)
dayRows = d.TT.Time >= day & d.TT.Time < day + days(1) & d.TT.Elevation > -2;
r.DayData = struct("Time", d.TT.Time(dayRows), "Pdc", d.TT.P_dc(dayRows), ...
    "Pexp", d.Steps.Pdc_exp(ismember(d.Steps.Time, d.TT.Time(dayRows))), "G", d.TT.G_ref(dayRows), ...
    "Pac", colOr(d.TT, "P_ac", dayRows), "Vdc", colOr(d.TT, "V_dc", dayRows), "Idc", colOr(d.TT, "I_dc", dayRows), ...
    "Riso", colOr(d.TT, "R_iso", dayRows), "Vgrid", colOr(d.TT, "U_L1", dayRows), "Fgrid", colOr(d.TT, "f_grid", dayRows));
r.Vlm = [];
if opts.UseVlm
    r.Vlm = ges.agents.vlmInterpret(ctx, rgb, r.DayData, Options=opts.VlmOptions);
end

% --- 3. görüş: Self-Peer (tek evirici: kendi geçmiş benzer günleri; çok eviricili filoda mekansal komşular)
r.Peer = struct("Features", [], "Opinion", ges.opinions.emptyOpinion("peer", "Komşu karşılaştırması"));
if isfield(ctx, "Fleet") && ~isempty(ctx.Fleet)
    k = find(ctx.Fleet.Ids == id, 1);
    if ~isempty(k)
        pf = ges.opinions.peerFeatures(ctx.Fleet, k, day, Until=min(ctx.Now, day + days(1) - minutes(15)));
        r.Peer = struct("Features", pf, "Opinion", ges.opinions.peerOpinion(pf));
    end
end

% --- Uzlaşı: üç görüş (sensör kuralları · görsel desen · Self-Peer / komşu karşılaştırması)
r.Opinions = [ges.opinions.sensorOpinion(r.Numeric), ges.opinions.visualOpinion(r.CnnML, r.Cnn), r.Peer.Opinion];
r.Fusion = ges.opinions.consensus(r.Opinions);
end

function v = getOr(row, name, default)
if ismember(name, row.Properties.VariableNames)
    v = row.(name);
else
    v = default;
end
end

function v = colOr(TT, name, rows)
% Kolon yoksa NaN vektörü döndürür (eski/başka tedarikçi şemalarıyla uyum)
if ismember(name, TT.Properties.VariableNames)
    v = double(TT.(name)(rows));
else
    v = nan(nnz(rows), 1);
end
end

function E = electricalSummary(TT, day, now)
% o günün (now'a kadar) L1 şebeke, k/18 röle, R_iso, verim ve yeniden başlatma özeti
vn = TT.Properties.VariableNames;
rows = TT.Time >= day & TT.Time < day + days(1) & TT.Time <= now;
T = TT(rows, :);
E = struct("Steps", height(T), "Vl1Min", NaN, "Vl1CondMed", NaN, "FgridMin", NaN, "RelaySteps", 0, ...
    "GridOutageTimes", NaT(0, 1, TimeZone=day.TimeZone), "RisoMin", NaN, "RisoMorningMin", NaN, "EtaMedian", NaN, ...
    "VdcMax", NaN, "IdcMax", NaN, "ResetTimes", NaT(0, 1, TimeZone=day.TimeZone), "TcellMax", NaN, "WindMean", NaN);
if isempty(T)
    return
end
has = @(n) ismember(n, vn);
g = NaN(height(T), 1);
if has("G_poa")
    g = double(T.G_poa);
elseif has("G_ref")
    g = double(T.G_ref);
end
if has("U_L1")
    u = double(T.U_L1);
    E.Vl1Min = min(u, [], "omitmissing");
end
if has("U_L1_cond")
    E.Vl1CondMed = median(double(T.U_L1_cond(T.U_L1_cond > 100)), "omitmissing");
end
if has("f_grid")
    f = double(T.f_grid);
    E.FgridMin = min(f, [], "omitmissing");
    relay = f > 5 & f < 48 & g < 250;                       % k/18 röle alt-örnekleme adımı (şebeke çökmesi değil)
    E.RelaySteps = nnz(relay);
    if has("U_L1")
        out = f <= 0.5 & u <= 1 & g > 200;                  % gerçek gündüz kesintisi: V_L1 = 0, f = 0
        E.GridOutageTimes = T.Time(out);
    end
end
if has("R_iso")
    r = double(T.R_iso);
    E.RisoMin = min(r, [], "omitmissing");
    am = T.Time < day + hours(10);
    if any(am)
        E.RisoMorningMin = min(r(am), [], "omitmissing");
    end
end
if has("Eff")
    e = double(T.Eff);
    E.EtaMedian = median(e(e > 50 & e < 100), "omitmissing");
end
if has("V_dc"), E.VdcMax = max(double(T.V_dc), [], "omitmissing"); end
if has("I_dc"), E.IdcMax = max(double(T.I_dc), [], "omitmissing"); end
if has("qRebootEvent")
    E.ResetTimes = T.Time(logical(T.qRebootEvent));
end
if has("T_cell_dyn"), E.TcellMax = max(double(T.T_cell_dyn), [], "omitmissing"); end
if has("WindSpeed"), E.WindMean = mean(double(T.WindSpeed), "omitmissing"); end
end
