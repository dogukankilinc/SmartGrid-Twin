function [rgb, jetImg, mag, elecRgb] = makeImages(fb, sig, scale, opts)
%MAKEIMAGES Fizik-RGB, klasik jet ve Elektriksel-İkiz skalogram görüntüleri (uint8, Size×Size×3).
%   [rgb, jetImg, mag, elecRgb] = ges.scalogram.makeImages(fb, sig, scale)
%   fb    : cwtfilterbank (SignalLength = size(sig,1), analitik Morlet). Boşsa otomatik kurulur.
%   sig   : N×3 veya N×6 sinyal (ges.scalogram.dailySignals)
%   scale : TÜM kanallar ve TÜM görüntüler için ORTAK sabit normalizasyon (eğitim verisinden).
%   Fizik-RGB: R = |CWT(güç)|, G = |CWT(ışınım)|, B = |CWT(eksik üretim)|
arguments
    fb
    sig double
    scale (1,1) double = 0.25
    opts.Size (1,1) double = 64
end

if isempty(scale) || isnan(scale) || scale <= 0
    scale = 0.25;
end
n = opts.Size;
nSig = size(sig, 1);
if isempty(fb)
    try
        fb = cwtfilterbank(SignalLength=nSig, Wavelet="amor");
    catch
        fb = [];
    end
end

mag = computeMag(fb, sig(:, 1:min(3, size(sig, 2))), scale, n);
rgb = im2uint8(mag);
cmap = jet(256);
jetImg = im2uint8(ind2rgb(im2uint8(mag(:, :, 1)), cmap));

if nargout >= 4
    if size(sig, 2) >= 6
        magElec = computeMag(fb, sig(:, 4:6), scale, n);
        elecRgb = im2uint8(magElec);
    else
        elecRgb = rgb;
    end
end
end

function mag = computeMag(fb, sig3, scale, n)
mag = zeros(n, n, 3);
for c = 1:size(sig3, 2)
    x = double(fillmissing(sig3(:, c), "constant", 0));
    if ~isempty(fb)
        w = abs(wt(fb, x));
    else
        w = fallbackMorletCwt(x, n);
    end
    w = imresize(w, [n n], "bilinear");
    mag(:, :, c) = min(sqrt(max(w, 0) / scale), 1);
end
end

function W = fallbackMorletCwt(x, nScales)
% Wavelet Toolbox bulunmadığında analitik Morlet dalgacığı ile doğrudan CWT yedeklemesi
N = numel(x);
t = (1:N)';
scales = logspace(log10(1.5), log10(N / 3), nScales);
W = zeros(nScales, N);
w0 = 6;
for sIdx = 1:nScales
    a = scales(sIdx);
    tau = (-ceil(3*a):ceil(3*a))';
    psi = (pi^(-0.25)) * exp(1i * w0 * (tau / a)) .* exp(-0.5 * (tau / a).^2) / sqrt(a);
    c = conv(x - mean(x), conj(flipud(psi)), "same");
    W(sIdx, :) = abs(c(:)');
end
end
