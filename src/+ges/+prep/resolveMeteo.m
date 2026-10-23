function [g, source] = resolveMeteo(candidates, names)
%RESOLVEMETEO Zaman damgası bazında öncelik sırasına göre geçerli ilk ışınım kaynağını seçer.
%   [g, source] = ges.prep.resolveMeteo(candidates, names)
%   candidates : N×K ışınım matrisi (aynı referans düzleme taşınmış), sütun
%                sırası öncelik sırasıdır; geçersiz değerler NaN olmalı
%   names      : 1×K kaynak adları (string)
%   g          : N×1 seçilen ışınım
%   source     : N×1 categorical — seçilen kaynağın adı veya "none"

arguments
    candidates (:,:) double
    names (1,:) string
end

[n, k] = size(candidates);
g = nan(n, 1);
idx = zeros(n, 1);
for j = 1:k
    take = idx == 0 & ~isnan(candidates(:, j));
    g(take) = candidates(take, j);
    idx(take) = j;
end
labels = [names "none"];
idx(idx == 0) = k + 1;
source = categorical(labels(idx)', labels);
end
