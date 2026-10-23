function [idx, score] = retrieveChunks(chunks, query, k)
%RETRIEVECHUNKS Sayfa içeriği parçalarından soruya en ilgili k tanesi (BM25, çevrimdışı).
%   [idx, score] = ges.agents.retrieveChunks(chunks, query, k) — chunks: struct dizisi (Title, Text).
%   Türkçe için: harfler ASCII'ye katlanır (ı→i, ş→s …), sözcükler ilk 5 harfine indirgenir
%   (ekler: "invertörün" ~ "invertör"), invertör kimlikleri (k03-inv46) bütün kalır. Gömme (embedding)
%   modeli gerektirmez; sayfa bağlamı küçük olduğundan sözcük eşleşmesi yeterli ve açıklanabilir.
%   idx skora göre azalan sırada; skoru 0 olanlar sona kalır.
arguments
    chunks struct
    query (1,1) string
    k (1,1) double = 6
end
n = numel(chunks);
if n == 0
    idx = zeros(0, 1);
    score = zeros(0, 1);
    return
end
docs = cell(n, 1);
for i = 1:n
    docs{i} = ges.agents.textTokens(chunks(i).Title + " " + chunks(i).Title + " " + chunks(i).Text);
end
q = unique(ges.agents.textTokens(query));
len = cellfun(@numel, docs);
avg = max(mean(len), 1);
k1 = 1.2;
b = 0.75;
score = zeros(n, 1);
for t = q'
    tf = cellfun(@(d) nnz(d == t), docs);
    df = nnz(tf);
    if df == 0
        continue
    end
    idf = log(1 + (n - df + 0.5) / (df + 0.5));
    score = score + idf * tf * (k1 + 1) ./ (tf + k1 * (1 - b + b * len / avg));
end
[score, idx] = sort(score, "descend");
idx = idx(1:min(k, n));
score = score(1:min(k, n));
end
