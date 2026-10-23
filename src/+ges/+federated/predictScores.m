function [scores, labels] = predictScores(net, X, opts)
%PREDICTSCORES Scalogram CNN'den sınıf olasılıkları ve etiketler üret.
%   [scores, labels] = ges.federated.predictScores(net, X) — net: dlnetwork (resnet18_ml)
%   X: uint8 [H W C N] scalogram yığını. Derin Öğrenme Araç Kutusu yoksa basit CWT enerji
%   tabanlı istatistiksel sınıflandırıcıya geri döner (fallback).
%   Dönüş: scores [N × numClasses], labels [N × 1] string.
arguments
    net
    X               % uint8 veya single [H W C N]
    opts.Classes    (1,:) string  = ["grid_event" "inverter_trip" "string_fault" "thermal_derating" "soiling" "healthy"]
    opts.Threshold  (1,:) double  = 0.5 * ones(1,6)
    opts.InputSize  (1,2) double  = [64 64]
    opts.Mode       (1,1) string  = "rgb_power"   % "rgb_power" | "rgb_elec"
end

nCls = numel(opts.Classes);
N    = size(X, 4);
scores = zeros(N, nCls);
labels = repmat("healthy", N, 1);

if isempty(net) || isempty(X) || N == 0
    return
end

useDeep = ~isempty(net) && isobject(net);
if useDeep
    try
        Xr = imresize(X, opts.InputSize);
        Xd = dlarray(single(Xr) / 255, "SSCB");
        raw = extractdata(predict(net, Xd));
        if size(raw,1) == nCls; raw = raw'; end
        scores = double(raw(:, 1:min(end, nCls)));
    catch ME
        warning("ges:federated:predictFail","Derin tahmin başarısız, fallback: %s", ME.message);
        useDeep = false;
    end
end

if ~useDeep
    % Fallback: kanal enerji oranlarından kural tabanlı skor
    for i = 1:N
        img = double(X(:,:,:,i)) / 255;
        chE = squeeze(mean(img.^2, [1 2]));   % [C × 1]
        if numel(chE) >= 3
            rCh = chE(1); gCh = chE(2); bCh = chE(3);
        else
            rCh = mean(chE); gCh = rCh; bCh = rCh;
        end
        sc = zeros(1, nCls);
        sc(opts.Classes == "thermal_derating") = min(rCh * 1.5, 1);
        sc(opts.Classes == "soiling")          = min(bCh * 2.0, 1);
        sc(opts.Classes == "healthy")          = max(0, 1 - rCh - bCh);
        sc = sc / max(sum(sc), 1e-6);
        scores(i,:) = sc;
    end
end

for i = 1:N
    thr = opts.Threshold;
    above = opts.Classes(scores(i,:) >= thr);
    if isempty(above)
        labels(i) = "healthy";
    else
        [~, mi] = max(scores(i,:));
        labels(i) = opts.Classes(mi);
    end
end
end
