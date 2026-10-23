function f = consensus(ops)
%CONSENSUS Üç bağımsız görüşü ortak bir karara bağlar (şeffaf, denetlenebilir kural; LLM karar vermez).
%   f = ges.opinions.consensus(ops) — ops: görüş yapıları dizisi (ges.opinions.sensorOpinion,
%   visualOpinion, peerOpinion; kullanılamayanlar Available=false). Her görüş her sınıf için
%   +1 (destekler), −1 (çürütür) veya 0 (göremez / çekimser) der. Bir sınıf için S = destek, R = karşı.
%
%   Kanıt hiyerarşisi: fiziksel ölçüm (sensör kuralları, komşu karşılaştırması) > öğrenilmiş desen (CNN).
%   Sorun sınıfları öncelik sırasıyla (şebeke > trip > string > ısıl kısma > tozlanma) değerlendirilir:
%     1) Sensör kuralının deterministik kanıtı varsa (0 A string, durum kodu, kabin geneli kesinti, kısma
%        imzası) sorun kabul edilir. Düzey: S≥2 ve R=0 → uzlaşı/çoğunluk; diğerleri göremiyorsa "tek kanıt".
%        Komşu karşılaştırması (bağımsız ölçüm) bu sorunu ÇÜRÜTÜYORSA → "çelişki": karar korunur ama saha
%        kontrolü istenir (ör. 0 A görünen string varken invertör komşuları kadar üretiyor → ölçüm hatası?).
%        Yalnızca CNN katılmıyorsa karar ve düzey korunur, not düşülür.
%     2) Kesin kanıt yoksa: S ≥ 2 ve S > R → kabul (çoğunluk/uzlaşı).
%        S = 1, R = 0 ve sınıfı yalnızca bu görüş görebiliyorsa → kabul ("tek görüş"; ör. tozlanma).
%        S = 1 ve R ≥ 1: destekleyen sensörse (ör. zayıf string, CNN görmüyor) → "çelişki" adayı (saha kontrolü);
%        sensör karşıysa reddedilir — sensörün "yok" dediğini tek görüş değiştiremez, iki görüş birlikte gerekir;
%        sensör görüş bildirmiyorsa S = 1, R = 1 → çelişki, R ≥ 2 → reddedilir.
%   Birincil karar: kabul edilen ilk sorun. Yoksa çelişki adayı (saha kontrolü). O da yoksa sağlıklı
%   (en az bir görüş sağlıklı diyorsa) ya da "uncertain": "belirsiz" (görüş var ama karar yok → saha kontrolü)
%   veya "veri_yok" (hiçbir görüş karar veremedi; haritada zaten "veri yok" görünür → saha kontrolü sayılmaz).
%   Çıktı: Label, Labels (kabul edilen tüm sorunlar), Level ("uzlasi" | "cogunluk" | "tek_kanit" |
%   "tek_gorus" | "celiski" | "belirsiz" | "veri_yok"), LevelTr, Support/Against/Blind (birincil sınıf için),
%   Available (karar verebilen görüş sayısı), Confidence, Check (saha kontrolü önerilir), Note, Summary.
%   Geriye uyum: Conflict (= Check), ConflictReason, Rule, Probs (sınıf başına destek payı).
arguments
    ops struct
end

cls = ges.opinions.classes();
faults = cls(cls ~= "healthy");
ops = ops([ops.Available]);
nAv = numel(ops);
keys = string({ops.Key});
St = zeros(nAv, numel(cls));
for i = 1:nAv
    St(i, :) = ops(i).Stance;
end
sensor = ops(keys == "sensor");
% Komşu karşılaştırması yalnızca TAM string kaybını çürütebilir (kısmi/zayıf string onun ölçüm gürültüsü içinde)
if ~isempty(sensor) && sensor.StringKind == "weak"
    St(keys(:) == "peer" & St(:, cls == "string_fault") < 0, cls == "string_fault") = 0;
end
S = sum(St > 0, 1);
R = sum(St < 0, 1);

f.Classes = cls;
f.Support = S;
f.Against = R;
f.Available = nAv;
f.Note = "";
accepted = strings(1, 0);
level = dictionary(string.empty, string.empty);
candidates = strings(1, 0);
notes = strings(1, 0);
for c = faults
    j = cls == c;
    if S(j) == 0
        continue
    end
    hard = ~isempty(sensor) && ismember(c, sensor.HardLabels);
    peerAgainst = any(keys == "peer" & St(:, j)' < 0);
    if hard
        accepted(end+1) = c; %#ok<AGROW>
        if peerAgainst
            level(c) = "celiski";
            notes(end+1) = sprintf("sensör %s görüyor ama komşu karşılaştırması bu kaybı görmüyor", trName(c)); %#ok<AGROW>
        elseif S(j) >= 2
            level(c) = ifelse(R(j) == 0, ifelse(S(j) == nAv, "uzlasi", "cogunluk"), "cogunluk");
        else
            level(c) = "tek_kanit";
        end
        if R(j) > 0 && ~peerAgainst
            notes(end+1) = sprintf("görsel model %s görmüyor; sensör kanıtı öncelikli", trName(c)); %#ok<AGROW>
        end
    elseif S(j) >= 2 && S(j) > R(j)
        accepted(end+1) = c; %#ok<AGROW>
        level(c) = ifelse(R(j) == 0 && S(j) == nAv, "uzlasi", "cogunluk");
        if c == "string_fault" && any(keys == "sensor" & St(:, j)' < 0)
            notes(end+1) = "sensör string akımlarında ölü/zayıf string görmüyor: kayıp birden fazla stringe yayılmış olabilir (kirlenme, gölge, modül arızası)"; %#ok<AGROW>
        elseif R(j) > 0
            notes(end+1) = sprintf("%s %s görmüyor", strjoin(string({ops(St(:, j)' < 0).Name}), ", "), trName(c)); %#ok<AGROW>
        end
    elseif S(j) == 1 && R(j) == 0
        accepted(end+1) = c; %#ok<AGROW>
        level(c) = "tek_gorus";
    else
        % Tek destek, en az bir karşı görüş. Sensör kuralları kapsamlı ölçüm görüşüdür: onun "yok" dediği bir
        % sorunu tek bir görüş (CNN ya da komşular) kabul ettiremez — iki görüş birlikte gerekir (v3-M01:
        % aksi halde çekirdek modda günlerin %5.8'i, tam modda %13.5'i saha kontrolüne düşüyordu).
        pro = strjoin(string({ops(St(:, j)' > 0).Name}), ", ");
        sensorAgainst = any(keys == "sensor" & St(:, j)' < 0);
        if R(j) == 1 && ~sensorAgainst
            candidates(end+1) = c; %#ok<AGROW>
        elseif sensorAgainst
            notes(end+1) = sprintf("yalnız %s %s görüyor; sensör kuralları görmüyor (karar değişmedi, izleniyor)", pro, trName(c)); %#ok<AGROW>
        else
            notes(end+1) = sprintf("%s %s görüyor, diğer görüşler görmüyor (reddedildi)", pro, trName(c)); %#ok<AGROW>
        end
    end
end

h = cls == "healthy";
if ~isempty(accepted)
    lab = accepted(1);
    lev = level(lab);
elseif ~isempty(candidates)
    lab = candidates(1);
    lev = "celiski";
    j = cls == lab;
    pro = strjoin(string({ops(St(:, j)' > 0).Name}), ", ");
    con = strjoin(string({ops(St(:, j)' < 0).Name}), ", ");
    notes(end+1) = sprintf("%s %s görüyor, %s görmüyor", pro, trName(lab), con);
elseif S(h) >= 1
    lab = "healthy";
    if S(h) >= 2
        lev = ifelse(S(h) == nAv && R(h) == 0, "uzlasi", "cogunluk");
    else
        lev = "tek_gorus";
    end
elseif nAv == 0
    lab = "uncertain";
    lev = "veri_yok";                                % hiçbir görüş karar veremedi (veri yok / yetersiz)
else
    lab = "uncertain";
    lev = "belirsiz";
end

f.Label = lab;
f.Labels = accepted;
if isempty(f.Labels) && lab ~= "uncertain"
    f.Labels = lab;
end
f.Level = lev;
f.LevelTr = levelText(lev);
j = cls == lab;
if any(j)
    f.SupportN = S(j);
    f.AgainstN = R(j);
    sup = St(:, j)' > 0;
    conf = [ops(sup).Confidence];
    conf = conf(~isnan(conf));
    if isempty(conf), conf = 0.5; end
    f.Confidence = round(mean(conf) * S(j) / max(S(j) + R(j), 1), 2);
    f.SupportedBy = string({ops(sup).Name});
    f.AgainstBy = string({ops(St(:, j)' < 0).Name});
else
    f.SupportN = 0;
    f.AgainstN = 0;
    f.Confidence = 0;
    f.SupportedBy = strings(1, 0);
    f.AgainstBy = strings(1, 0);
end
f.BlindN = nAv - f.SupportN - f.AgainstN;
f.Check = ismember(lev, ["celiski" "belirsiz"]);  % veri yokluğu haritada "veri yok" olarak zaten görünür
f.Note = strjoin(notes, "; ");
f.Summary = sprintf("%s · %d görüş: %d destek, %d karşı, %d göremez", f.LevelTr, nAv, f.SupportN, f.AgainstN, f.BlindN);
% Geriye uyum (eski füzyon alanları)
f.Conflict = f.Check;
f.ConflictReason = ifelse(lev == "celiski", "disagree", ifelse(lev == "belirsiz", "low_support", ""));
f.Rule = "üç görüş uzlaşısı: " + f.LevelTr;
f.Probs = S ./ max(nAv, 1);
end

function t = levelText(lev)
switch lev
    case "uzlasi",    t = "Tam uzlaşı";
    case "cogunluk",  t = "Çoğunluk";
    case "tek_kanit", t = "Tek kanıt (sensör ölçümü)";
    case "tek_gorus", t = "Tek görüş (diğerleri karar vermedi ya da göremez)";
    case "celiski",   t = "Çelişki — saha kontrolü";
    case "veri_yok",  t = "Veri yetersiz — karar yok";
    otherwise,        t = "Belirsiz";
end
t = string(t);
end

function t = trName(c)
names = dictionary(["grid_event" "inverter_trip" "string_fault" "thermal_derating" "soiling" "healthy"], ...
    ["şebeke/kabin olayı" "trip" "string arızası" "ısıl kısma" "tozlanma" "sağlıklı"]);
t = names(c);
end

function v = ifelse(c, a, b)
if c
    v = a;
else
    v = b;
end
end
