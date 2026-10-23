function peers = pickPeers(ampm, i, minPeers)
%PICKPEERS Aynı kabinde yönelimi (AM/PM oranı) en benzer invertörler; tek eviricide kendisini döndürür.

if isscalar(ampm)
    peers = 1;
    return
end
d = abs(ampm - ampm(i));
d(i) = Inf;
for tol = [0.03 0.06 0.10 Inf]
    peers = find(d <= tol & isfinite(d));
    if numel(peers) >= min(minPeers, numel(ampm) - 1)
        return
    end
end
peers = setdiff(1:numel(ampm), i)';
if isempty(peers)
    peers = i;
end
end
