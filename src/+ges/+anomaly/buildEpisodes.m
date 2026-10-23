function ep = buildEpisodes(t, active, lossKw, opts)
%BUILDEPISODES Adım düzeyindeki etkin bayrakları olaylara (episode) dönüştürür.
%   ep = ges.anomaly.buildEpisodes(t, active, lossKw) — t zaman damgaları,
%   active mantıksal bayrak, lossKw her adımdaki kayıp güç (kW, NaN = 0).
%
%   İki etkin adım arasındaki boşluk iki ölçütle değerlendirilir:
%     * Gözlem boşluğu: aradaki "gözlemlenmiş ama etkin olmayan" adım sayısı
%       (Observed & ~active). Gece ve veri kesintisi gözlem sayılmadığından
%       bir olayı bölmez; olay ancak sorunun gerçekten ortadan kalktığı
%       GÖRÜLÜRSE (MaxObservedGap'ten fazla temiz adım) kapanır.
%     * Takvim boşluğu: MaxGap'ten uzun aralık her durumda yeni olay başlatır.
%   Varsayılanlar (Observed verilmezse) yalnızca 20 saatlik takvim kuralıdır.
%
%   SmartGridLab uyarlaması:
%     - qRebootEvent bayrağı (reset satırı) zaten ilgili adımda episode'u kapatır.
%     - 10-15 Ağustos eksik haftası (qExportGap) MaxGap ile yeni olay başlatmaz.
%   ep: Start, End, Steps, DurationDays, LossKwh, Chronic, Detail.
arguments
    t        (:,1) datetime
    active   (:,1) logical
    lossKw   (:,1) double
    opts.Observed       (:,1) logical = true(0,1)
    opts.MaxObservedGap (1,1) double  = Inf
    opts.MaxGap         (1,1) duration = hours(20)
    opts.MinSteps       (1,1) double   = 1
    opts.Step           (1,1) duration = minutes(15)
    opts.ChronicDays    (1,1) double   = 7
    opts.Detail         (:,1) string   = strings(0,1)  % isteğe bağlı alt-tip etiketleri
end

idx = find(active);
vars = ["Start" "End" "Steps" "DurationDays" "LossKwh" "Chronic" "Detail"];
empDetail = strings(0,1);
if isempty(idx)
    ep = table(t([]), t([]), zeros(0,1), zeros(0,1), zeros(0,1), false(0,1), empDetail, ...
        VariableNames=vars);
    return
end

newEp = [true; diff(t(idx)) > opts.MaxGap];
if ~isempty(opts.Observed)
    cleanSeen = cumsum(opts.Observed & ~active);
    newEp = newEp | [true; diff(cleanSeen(idx)) > opts.MaxObservedGap];
end
gid    = cumsum(newEp);
first  = idx(newEp);
last   = idx([newEp(2:end); true]);
nEp    = max(gid);

lossKw(isnan(lossKw)) = 0;
lossKwh = arrayfun(@(g) sum(lossKw(idx(gid==g))) * hours(opts.Step), 1:nEp);
stepCnt = arrayfun(@(g) nnz(gid==g), 1:nEp);
durDays = days(t(last) - t(first)) + hours(opts.Step)/24;
chronic = durDays >= opts.ChronicDays;

% Alt-tip etiketi (varsa her episode için mod değerini al)
detail = repmat("", nEp, 1);
if ~isempty(opts.Detail) && numel(opts.Detail) == numel(active)
    for g = 1:nEp
        sub = opts.Detail(idx(gid==g));
        sub = sub(sub ~= "");
        if ~isempty(sub)
            [cnt, uq] = hist(sub, unique(sub)); %#ok<HIST>
            [~, mi] = max(cnt);
            detail(g) = uq(mi);
        end
    end
end

ep = table(t(first), t(last), stepCnt(:), durDays(:), lossKwh(:), chronic(:), detail, ...
    VariableNames=vars);
ep = ep(ep.Steps >= opts.MinSteps, :);
end
