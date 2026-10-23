function o = sensorOpinion(numeric, opts)
%SENSOROPINION 1. görüş — sensör ve fizik kuralları (çekirdek katman, deterministik).
%   o = ges.opinions.sensorOpinion(numeric) — numeric: diagnoseDay'in r.Numeric yapısı (etiketleme
%   fonksiyonları: durum kodları, DC V/I zarfı, beklenen güç modeli M1, ısıl kısma imzası, L1 şebeke ve R_iso).
%   Bu görüş her sınıfı görebilir: oy verdiği sınıfları destekler (+1), diğerlerini çürütür (−1).
%   Belirsiz / kullanılamaz günde çekimser kalır (tüm duruşlar 0).
%   Hard = true: karar deterministik bir ölçüme dayanıyor (güven ≥ HardConfidence: durum kodu,
%   string akımı 0 A / gerilim çökmesi, L1 şebeke kesintisi, V/I kısma imzası).
arguments
    numeric (1,1) struct
    opts.HardConfidence (1,1) double = 0.9
end

cls = ges.opinions.classes();
o = ges.opinions.emptyOpinion("sensor", "Sensör ve fizik kuralları");
lab = string(numeric.Label);
if ismember(lab, ["uncertain" "unusable" ""])
    o.Evidence = "veri yetersiz veya kurallar karar veremedi";
    o.Detail = o.Evidence;
    return
end
votes = split(string(numeric.Votes), "|");
map = dictionary(["grid" "trip" "dead" "weak" "derate" "soiling" "healthy"], ...
    ["grid_event" "inverter_trip" "string_fault" "string_fault" "thermal_derating" "soiling" "healthy"]);
votes = votes(isKey(map, votes));
labels = unique(map(votes), "stable");
labels = labels(:)';
if ~ismember(lab, labels)
    labels = [lab labels];
end
if any(labels ~= "healthy")
    labels = labels(labels ~= "healthy");
end
o.Available = true;
o.Label = lab;
o.Labels = cls(ismember(cls, labels));
o.Confidence = numeric.Confidence;

% Deterministik kanıt: şebeke kesintisi, durum kodlu / DC'siz trip, 0 A string veya bypass gerilim çökmesi, ısıl kısma imzası.
hard = strings(1, 0);
if any(votes == "grid"), hard(end+1) = "grid_event"; end
if any(votes == "trip") && (lab ~= "inverter_trip" || numeric.Confidence >= opts.HardConfidence)
    hard(end+1) = "inverter_trip";
end
if any(votes == "dead"), hard(end+1) = "string_fault"; end
if any(votes == "derate"), hard(end+1) = "thermal_derating"; end
o.HardLabels = cls(ismember(cls, hard));
o.Hard = ismember(lab, o.HardLabels);
o.Stance = -ones(1, numel(cls));
o.Stance(ismember(cls, labels)) = 1;
if contains(string(numeric.Votes), "dead")
    o.StringKind = "dead";
elseif contains(string(numeric.Votes), "weak")
    o.StringKind = "weak";
end
o.Evidence = string(numeric.Detail);
o.Primary = o.Label;
o.Active = o.Labels;
scores = zeros(1, numel(cls));
scores(ismember(cls, o.Labels)) = max(o.Confidence, 0.5);
o.Scores = scores;
o.Detail = o.Evidence;
end
