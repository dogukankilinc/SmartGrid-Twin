function o = visualOpinion(cnnML, cnn, rgbImg)
%VISUALOPINION 2. görüş — görsel desen tanıma (araştırma katmanı: çok etiketli CNN veya CWT spektral analiz).
%   o = ges.opinions.visualOpinion(cnnML, cnn, rgbImg)
%   cnnML  : diagnoseDay r.CnnML (çok etiketli ResNet-18: Labels, Probs, Classes) — varsa tercih edilir
%   cnn    : diagnoseDay r.Cnn (tek etiketli topluluk: Label, Probs) — yalnızca çok etiketli yoksa
%   rgbImg : (isteğe bağlı) 64×64×3 uint8 Fizik-RGB skalogram görüntüsü; model dosyaları yüklü değilse
%            CWT frekans-zaman enerji bantlarından görsel görüş üretir.
%   cnnML ve cnn boşsa ve rgbImg verilmemişse (çekirdek mod) görüş kullanılamaz (Available=false).
if nargin < 3
    rgbImg = [];
end
cls = ges.opinions.classes();
o = ges.opinions.emptyOpinion("visual", "Görsel desen (CNN)");
outage = ["inverter_trip" "grid_event"];
if ~isempty(cnnML)
    on = string(cnnML.Labels(:))';
    p = dictionary(string(cnnML.Classes(:)), double(cnnML.Probs(:)));
    seen = ["string_fault" "thermal_derating" outage "healthy"];
    o.Name = "Görsel desen (çok etiketli CNN)";
    if isempty(on)
        o.Label = "healthy";
        o.Confidence = 1 - max(p.values);
    else
        pr = p(on);
        [o.Confidence, i] = max(pr);
        o.Label = on(i);
    end
    o.Labels = cls(ismember(cls, on));
elseif ~isempty(cnn)
    o.Name = "Görsel desen (CNN topluluğu)";
    o.Label = string(cnn.Label);
    o.Labels = o.Label;
    o.Confidence = max(cnn.Probs);
    seen = ["string_fault" "thermal_derating" outage "healthy"];
elseif ~isempty(rgbImg)
    % Model ağırlıkları yüklü olmadığında CWT Fizik-RGB frekans-zaman enerjisinden görsel karar
    o = spectralVisualOpinion(rgbImg, cls, outage);
    return
else
    o.Evidence = "görsel katman kapalı (çekirdek mod)";
    o.Detail = o.Evidence;
    return
end
o.Available = true;
if any(ismember(o.Labels, outage))
    o.Labels = unique([o.Labels outage], "stable");
    o.Labels = cls(ismember(cls, o.Labels));
end
if isempty(o.Labels)
    o.Labels = "healthy";
end
o.Stance = zeros(1, numel(cls));
o.Stance(ismember(cls, seen)) = -1;
o.Stance(ismember(cls, o.Labels)) = 1;
if o.Label ~= "healthy"
    o.Stance(cls == "healthy") = -1;
end
o.Evidence = "skalogram deseni";
o.Primary = o.Label;
o.Active = o.Labels;
scores = zeros(1, numel(cls));
scores(o.Stance > 0) = o.Confidence;
o.Scores = scores;
o.Detail = o.Evidence;
end

function o = spectralVisualOpinion(rgbImg, cls, outage)
o = ges.opinions.emptyOpinion("visual", "Görsel desen (CWT spektral)");
I = double(rgbImg);
if max(I(:)) > 1.5
    I = I / 255;
end
R = I(:, :, 1);                                    % CWT(P_dc)
G = I(:, :, 2);                                    % CWT(G_poa)
B = I(:, :, 3);                                    % CWT(Eksik üretim)

gEnergy = mean(G(:));
if gEnergy < 0.02
    o.Evidence = "skalogramda yeterli ışınım enerjisi yok";
    o.Detail = o.Evidence;
    return
end

n = size(I, 1);
hiFreq = 1:max(1, round(0.35 * n));                % İnce ölçekler (yüksek frekans: testere dişi / ani kesim)
loFreq = max(1, round(0.45 * n)):n;                % Geniş ölçekler (günlük çan eğrisi)
midTime = max(1, round(0.25 * n)):min(n, round(0.75 * n));

bLo = mean(B(loFreq, midTime), "all");
bHi = mean(B(hiFreq, midTime), "all");
rHi = mean(R(hiFreq, midTime), "all");
rLo = mean(R(loFreq, midTime), "all");
gLo = max(mean(G(loFreq, midTime), "all"), 0.05);

shortfallRatio = bLo / gLo;
sawtoothRatio = (rHi + bHi) / max(rLo + gLo, 0.05);

labels = strings(1, 0);
conf = 0.75;
if shortfallRatio > 0.65 && rLo < 0.25 * gLo
    labels = outage;
    conf = 0.88;
elseif sawtoothRatio > 0.42 && bHi > 0.12
    labels(end+1) = "thermal_derating";
    conf = 0.85;
    if shortfallRatio > 0.35
        labels(end+1) = "string_fault";
    end
elseif shortfallRatio > 0.28
    labels(end+1) = "string_fault";
    conf = 0.72;
else
    labels = "healthy";
    conf = 0.85;
end

seen = ["string_fault" "thermal_derating" outage "healthy"];
o.Available = true;
o.Labels = cls(ismember(cls, labels));
o.Label = o.Labels(1);
o.Confidence = conf;
o.Stance = zeros(1, numel(cls));
o.Stance(ismember(cls, seen)) = -1;
o.Stance(ismember(cls, o.Labels)) = 1;
if o.Label ~= "healthy"
    o.Stance(cls == "healthy") = -1;
end
o.Evidence = "CWT frekans-zaman enerji deseni";
o.Primary = o.Label;
o.Active = o.Labels;
scores = zeros(1, numel(cls));
scores(o.Stance > 0) = o.Confidence;
o.Scores = scores;
o.Detail = o.Evidence;
end
