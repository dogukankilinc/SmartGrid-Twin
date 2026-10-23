function tok = textTokens(s)
%TEXTTOKENS Türkçe metni arama sözcüklerine böler (ges.agents.retrieveChunks için).
%   tok = ges.agents.textTokens(s) — küçük harf, ASCII'ye katlanmış, ilk 5 harfe indirgenmiş
%   sözcükler (string sütunu). İnvertör kimlikleri ("K03-INV46") bütün kalır ve ayrıca kabin
%   ("k03") ve invertör ("inv46") parçaları da eklenir; 2 harften kısa sözcükler atılır.
arguments
    s (1,1) string
end
s = lower(s);
s = replace(s, ["ı" "İ" "i̇" "ş" "ğ" "ü" "ö" "ç" "â" "î" "û"], ["i" "i" "i" "s" "g" "u" "o" "c" "a" "i" "u"]);
ids = regexp(s, "k\d{2}-inv\d{2}", "match");
s = regexprep(s, "[^a-z0-9%\- ]", " ");
w = split(strtrim(regexprep(s, "\s+", " ")), " ");
w = w(strlength(w) >= 2 & ~ismember(w, ["ve" "ile" "bu" "da" "de" "mi" "ne" "bir" "icin" "gibi" "olan"]));
w = extractBefore(w + "     ", 6);                  % ilk 5 harf (kısa sözcükler kendisi)
w = strip(w);
tok = [w(:); string(ids(:))];
for i = 1:numel(ids)
    p = split(ids(i), "-");
    tok = [tok; p(:)]; %#ok<AGROW>
end
end
