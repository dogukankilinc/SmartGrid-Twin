function key = columnKey(names, opts)
%COLUMNKEY Sütun adını eşleştirme anahtarına indirger (küçük harf, yalnızca a-z0-9).
%   key = ges.io.columnKey("Total Irradiance (W/m²)")  % -> "totalirradiancewm"
%   key = ges.io.columnKey(names, StripDevice=true)    % " / <CihazAdı>" sonekini soyar
arguments
    names string
    opts.StripDevice (1,1) logical = false
end
s = lower(names);
if opts.StripDevice
    s = regexprep(s, "\s*/\s*[^/]+$", "");
end
key = regexprep(s, "[^a-z0-9]", "");
end
