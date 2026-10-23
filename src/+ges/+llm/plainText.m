function s = plainText(s)
%PLAINTEXT LLM çıktısındaki markdown işaretlerini düz metne çevirir (metin kutuları için).
%   s = ges.llm.plainText(s) — **kalın**, `kod`, # başlık, "* madde" -> "• madde",
%   fazla boş satırlar temizlenir. Satır sonları korunur.
s = string(s);
s = regexprep(s, "\*\*(.+?)\*\*", "$1");
s = regexprep(s, "__(.+?)__", "$1");
s = regexprep(s, "`([^`]*)`", "$1");
s = regexprep(s, "(?m)^\s*#{1,6}\s*", "");
s = regexprep(s, "(?m)^(\s*)[\*\-]\s+", "$1• ");
s = regexprep(s, "\n{3,}", "\n\n");
s = strtrim(s);
end
