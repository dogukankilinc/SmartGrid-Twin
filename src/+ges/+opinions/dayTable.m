function T = dayTable(cfg, fleet, t0, t1, opts)
%DAYTABLE Üç görüşü ve uzlaşıyı çok sayıda invertör-günü için toplu hesaplar (değerlendirme ve testler).
%   T = ges.opinions.dayTable(cfg, fleet, t0, t1) — [t0, t1) aralığındaki tüm günler, fleet'teki tüm
%   invertörler (opts.Ids ile daraltılabilir). Panelin teşhisiyle (ges.agents.diagnoseDay) AYNI fonksiyonlar
%   kullanılır: 1. görüş etiketleme fonksiyonları (ges.label), 2. görüş çok etiketli CNN (opts.Cnn verilirse
%   veya CWT spektral yedekleme), 3. görüş ges.opinions.peerFeatures/peerOpinion.
arguments
    cfg (1,1) struct
    fleet (1,1) struct
    t0 (1,1) datetime
    t1 (1,1) datetime
    opts.Ids (:,1) string = fleet.Ids
    opts.Cnn = []
    opts.Split (1,1) string = "train"
    opts.Verbose (1,1) logical = true
end

catFile = fullfile(cfg.paths.anomaly, "events_catalog.mat");
if isfile(catFile)
    catalog = load(catFile).catalog;
else
    catalog = table();
end
parts = cell(numel(opts.Ids), 1);
imgs = cell(numel(opts.Ids), 1);
tic
for i = 1:numel(opts.Ids)
    id = opts.Ids(i);
    k = find(fleet.Ids == id, 1);
    f = fullfile(cfg.paths.processed, opts.Split, "inverter", id + ".mat");
    if isempty(k) || ~isfile(f)
        continue
    end
    S = load(f, "TT", "D", "info");
    TT = ges.prep.mergeThrottle(S.TT, cfg, id);
    A = load(fullfile(cfg.paths.anomaly, id + ".mat"), "Steps").Steps;
    if ~isempty(catalog) && ismember("Id", catalog.Properties.VariableNames)
        ev = catalog(catalog.Id == id, :);
    else
        ev = table();
    end
    % 1. görüş: etiketleme fonksiyonları (geriye dönük medyan için 30 gün önceden başlanır)
    win = TT.Time >= t0 - days(30) & TT.Time < t1;
    F = ges.label.applyLabelingFunctions(ges.label.dayFeatures(TT(win, :), A(ismember(A.Time, TT.Time(win)), :), S.D, S.info, ev));
    F = F(F.Day >= t0 & F.Day < t1, :);
    if isempty(F)
        continue
    end
    n = height(F);
    R = table(F.Id, F.Day, VariableNames=["Id" "Day"]);
    R.O1Detail = string(F.Detail);
    R.MaxDeadStrings = F.MaxDeadStrings;
    R.DeadPV = strings(n, 1);
    if ~isempty(ev) && ismember("Type", ev.Properties.VariableNames)
        sd = ev(ev.Type == "string_dead" & ev.PV > 0, :);
        for r = 1:n
            e = sd(sd.Start < F.Day(r) + days(1) & sd.End >= F.Day(r), :);
            if ~isempty(e)
                R.DeadPV(r) = strjoin("PV" + string(unique(e.PV)'), "+");
            end
        end
    end
    o1 = cell(n, 1);
    for r = 1:n
        num = struct("Label", string(F.Label(r)), "Detail", F.Detail(r), "Confidence", F.Confidence(r), "Votes", F.Votes(r));
        o1{r} = ges.opinions.sensorOpinion(num);
    end
    R.O1 = [o1{:}]';
    % 3. görüş: komşu / elektriksel ikiz ve öz-akran karşılaştırması
    P = ges.opinions.peerFeatures(fleet, k, F.Day);
    o3 = cell(n, 1);
    for r = 1:n
        o3{r} = ges.opinions.peerOpinion(P(r, :));
    end
    R.O3 = [o3{:}]';
    R.PeerF = P(:, 3:end);
    % 2. görüş için skalogramlar
    R.ImgOk = false(n, 1);
    if ~isempty(opts.Cnn)
        fb = [];
        sc = 0.25;
        if isstruct(opts.Cnn) && isfield(opts.Cnn, "Norm") && ~isempty(opts.Cnn.Norm)
            fb = opts.Cnn.Norm.fb;
            sc = opts.Cnn.Norm.scale;
        end
        X = zeros(64, 64, 3, n, "uint8");
        for r = 1:n
            [sig, okk] = ges.scalogram.dailySignals(TT, A, S.info.Capacity, F.Day(r));
            if okk
                X(:, :, :, r) = ges.scalogram.makeImages(fb, sig, sc);
                R.ImgOk(r) = true;
            end
        end
        imgs{i} = X(:, :, :, R.ImgOk);
    end
    parts{i} = R;
    if opts.Verbose && mod(i, 10) == 0
        fprintf("  %d/%d invertör (%.0f s)\n", i, numel(opts.Ids), toc);
    end
end
T = vertcat(parts{:});
if isempty(T)
    return
end

% 2. görüş: çok etiketli CNN (toplu tahmin) veya CWT spektral yedekleme
none = ges.opinions.visualOpinion([], []);
T.O2 = repmat(none, height(T), 1);
if ~isempty(opts.Cnn)
    X = cat(4, imgs{:});
    rows = find(T.ImgOk);
    if isstruct(opts.Cnn) && isfield(opts.Cnn, "net") && ~isempty(opts.Cnn.net)
        M = opts.Cnn;
        Pr = minibatchpredict(M.net, imresize(X, M.inputSize(1:2)));
        for j = 1:numel(rows)
            p = double(Pr(j, :));
            ml = struct("Labels", M.classesOut(p >= M.thr), "Probs", round(p, 2), "Classes", M.classesOut);
            T.O2(rows(j)) = ges.opinions.visualOpinion(ml, []);
        end
    else
        for j = 1:numel(rows)
            T.O2(rows(j)) = ges.opinions.visualOpinion([], [], X(:, :, :, j));
        end
    end
end

% Uzlaşı
c = cell(height(T), 1);
for r = 1:height(T)
    c{r} = ges.opinions.consensus([T.O1(r), T.O2(r), T.O3(r)]);
end
T.C = [c{:}]';
end
