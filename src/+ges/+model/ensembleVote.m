function m = ensembleVote(scores, opts)
%ENSEMBLEVOTE Çok etiketli CNN (resnet18_ml) çıktılarından ensemble oylama ile karar üret.
%   m = ges.model.ensembleVote(scores) — scores: [N × numClasses] olasılık matrisi.
%   Tek model veya birden fazla modelin ortalaması (ensemble) kabul edilir.
%   SmartGridLab: 4 sınıf çıkışlı sigmoid yapısı (çok etiketli) veya softmax (tek etiket) desteklenir.
arguments
    scores (:,:) double
    opts.Classes   (1,:) string = ["grid_event" "inverter_trip" "string_fault" "thermal_derating" "soiling" "healthy"]
    opts.Threshold (1,:) double = 0.5 * ones(1,6)
    opts.Priority  (1,:) string = ["grid_event" "inverter_trip" "string_fault" "thermal_derating" "soiling" "healthy"]
end
N    = size(scores, 1);
nCls = numel(opts.Classes);
thr  = opts.Threshold;
if numel(thr) == 1; thr = repmat(thr, 1, nCls); end

m.Probs  = scores;
m.Labels = repmat("healthy", N, 1);
m.Above  = false(N, nCls);
for i = 1:N
    above = opts.Classes(scores(i,:) >= thr);
    m.Above(i,:) = scores(i,:) >= thr;
    if isempty(above)
        m.Labels(i) = "healthy";
    else
        % Öncelik sırasına göre birincil etiket
        for pr = opts.Priority
            if ismember(pr, above)
                m.Labels(i) = pr;
                break
            end
        end
    end
end
m.AllLabels = opts.Classes;
end
