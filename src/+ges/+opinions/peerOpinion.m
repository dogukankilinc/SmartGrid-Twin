function o = peerOpinion(f, opts)
%PEEROPINION 3. görüş — Komşu / Elektriksel İkiz ve Öz-Akran karşılaştırması (M1 KULLANMAZ).
%   o = ges.opinions.peerOpinion(f) — f: ges.opinions.peerFeatures çıktısının TEK satırı (bir gün).
%   Çok eviricili filoda aynı kabindeki komşularla, tek eviricili SmartGridLab (WR13TL22-8231)
%   sisteminde ise Katman 3A (Elektriksel DC-AC-L1 Şebeke İkizi) + Katman 3B (Nedensel Tarihsel
%   Öz-Akran k-NN) ile bağımsız fiziksel teyit/çürütme üretir.
arguments
    f (1,:) table
    opts.MinPeakPeer (1,1) double = 0.25
    opts.MinValidSteps (1,1) double = 8
    opts.StringFactor (1,1) double = 0.6
    opts.FullFactor (1,1) double = 0.25
    opts.ThermalDrop (1,1) double = 0.10
    opts.MinSteps (1,1) double = 4
end

cls = ges.opinions.classes();
o = ges.opinions.emptyOpinion("peer", "Komşu karşılaştırması");
if height(f) ~= 1
    o.Evidence = "bu gün için komşu/öz-akran verisi yok";
    o.Detail = o.Evidence;
    return
end
if ismember("Id", f.Properties.VariableNames) && contains(string(f.Id), "WR13TL22")
    o.Name = "Elektriksel ikiz ve öz-akran";
end
st = zeros(1, numel(cls));
labels = strings(1, 0);
ev = strings(1, 0);
share = f.StringShare;
info = f.NumPeers >= 3 && f.ValidSteps >= opts.MinValidSteps && f.PeakPeer >= opts.MinPeakPeer;

% Kesintiler: şebeke/kabin olayı veya tekil trip
if f.CollectiveSteps >= opts.MinSteps
    labels(end+1) = "grid_event";
    ev(end+1) = sprintf("%.1f saat şebeke/ortak kesinti doğrulandı", f.CollectiveSteps / 4);
end
if f.OutageSteps >= opts.MinSteps
    labels(end+1) = "inverter_trip";
    ev(end+1) = sprintf("referans üretirken %.1f saat üretim yok", f.OutageSteps / 4);
end
if info
    if f.CollectiveSteps == 0
        st(cls == "grid_event") = -1;
    end
    if f.OutageSteps == 0
        st(cls == "inverter_trip") = -1;
    end
    morning = f.RatioMorning;
    if isnan(morning)
        morning = f.Ratio;
    end
    if f.Ratio <= 1 - opts.StringFactor * share && morning <= 1 - opts.StringFactor * share
        labels(end+1) = "string_fault";
        ev(end+1) = sprintf("referansa göre üretim %%%.0f (≈ %.1f alt-dizi/string eksik)", 100 * f.Ratio, (1 - f.Ratio) / share);
    elseif f.Ratio >= 1 - opts.FullFactor * share && morning >= 1 - opts.FullFactor * share
        st(cls == "string_fault") = -1;                 % tam string kaybını çürütür (kısmi kaybı değil)
    end
    if ~isnan(f.RatioPeak) && morning - f.RatioPeak >= opts.ThermalDrop && f.PeakLowSteps >= opts.MinSteps
        labels(end+1) = "thermal_derating";
        ev(end+1) = sprintf("tepe saatlerde referansa göre üretim %%%.0f, sabah %%%.0f (kısma imzası)", 100 * f.RatioPeak, 100 * morning);
    end
end
if isempty(labels)
    if ~info
        o.Evidence = "az bilgi (kapalı gün, az referans veya az ölçüm)";
        o.Detail = o.Evidence;
        o.Stance = st;
        o.Available = any(st ~= 0);
        return
    end
    if abs(1 - f.Ratio) <= 0.5 * share
        labels = "healthy";
        ev = sprintf("referansla uyumlu (üretim oranı %%%.0f)", 100 * f.Ratio);
    else
        o.Available = true;
        o.Stance = st;
        o.Evidence = sprintf("referansa göre üretim %%%.0f — belirgin bir sorun imzası yok", 100 * f.Ratio);
        o.Detail = o.Evidence;
        return
    end
end
o.Available = true;
o.Labels = cls(ismember(cls, labels));
o.Label = o.Labels(1);
st(ismember(cls, labels)) = 1;
if o.Label == "healthy"
    st(cls == "healthy") = 1;
else
    st(cls == "healthy") = -1;
end
o.Stance = st;
o.Confidence = confidenceOf(o.Label, f, share);
o.Evidence = strjoin(ev, "; ");
o.Primary = o.Label;
o.Active = o.Labels;
scores = zeros(1, numel(cls));
scores(st > 0) = o.Confidence;
o.Scores = scores;
o.Detail = o.Evidence;
end

function c = confidenceOf(label, f, share)
switch label
    case {"grid_event", "inverter_trip"}
        c = 0.9;
    case "string_fault"
        c = min(max((1 - f.Ratio) / share, 0.5), 0.95);
    case "thermal_derating"
        c = 0.6;
    otherwise
        c = 0.8 - 0.2 * (abs(1 - f.Ratio) > 0.25 * share);
end
end
