function b64 = imageToBase64(img, opts)
%IMAGETOBASE64 Görüntüyü (dosya yolu veya RGB dizisi) VLM için base64 PNG metnine çevirir.
%   b64 = ges.llm.imageToBase64("scalogram_v2/train/K02-INV03/2024-07-10_rgb.png")
%   b64 = ges.llm.imageToBase64(rgbArray, Size=448)  % 64×64 skalogram büyütülerek gönderilir
arguments
    img
    opts.Size double = []                     % boş: orijinal boyut
end

if isstring(img) || ischar(img)
    img = imread(img);
end
if ~isempty(opts.Size)
    img = imresize(img, [opts.Size opts.Size], "nearest");
end
tmp = string(tempname) + ".png";
cleaner = onCleanup(@() delete(tmp));
imwrite(img, tmp);
fid = fopen(tmp, "r");
bytes = fread(fid, Inf, "*uint8");
fclose(fid);
b64 = string(matlab.net.base64encode(bytes));
end
