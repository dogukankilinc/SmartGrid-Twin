function app = GES_Baslat(mode)
%GES_BASLAT SmartGrid-Twin GES dijital ikiz panelini tek komutla açar.
%   MATLAB'da proje klasörüne geçip yazın:   GES_Baslat            (tam: çekirdek + araştırma katmanı)
%                                            GES_Baslat("cekirdek") (yalnız çekirdek: CNN ve LLM yüklenmez)
%   1) Proje yollarını ekler
%   2) Yerel LLM servisini (Ollama) kontrol eder, kapalıysa başlatır
%   3) Paneli açar (SmartGridLab 2026 dönemi; ▶ Oynat ile otonom akış başlar)
%   Panel nesnesi "gesApp" adıyla çalışma alanına da konur.

arguments
    mode (1,1) string {mustBeMember(mode, ["tam" "cekirdek"])} = "tam"
end
layers = "full";
if mode == "cekirdek"
    layers = "core";
end
root = fileparts(mfilename("fullpath"));
addpath(root, fullfile(root, "app"));
setupGes();

if layers == "full" && ~ollamaRunning()
    exe = fullfile(getenv("LOCALAPPDATA"), "Programs", "Ollama", "ollama.exe");
    if isfile(exe)
        fprintf("Yerel LLM servisi başlatılıyor...\n");
        system(sprintf('start "" /B "%s" serve', exe));
        for i = 1:20
            pause(1);
            if ollamaRunning()
                break
            end
        end
    end
    if ~ollamaRunning()
        warning("Ollama çalışmıyor: sohbet ve LLM açıklamaları devre dışı; panelin geri kalanı çalışır.");
    end
end

if layers == "full"
    fprintf("SmartGrid-Twin GES Paneli açılıyor (tam mod: CNN modelleri ve yerel LLM yüklenir)...\n");
else
    fprintf("SmartGrid-Twin GES Paneli açılıyor (çekirdek mod: CNN ve LLM yüklenmez)...\n");
end
app = GesDashboard(Layers=layers);
assignin("base", "gesApp", app);
fprintf("Hazır. ▶ Oynat ile otonom akışı başlatın; WR13TL22-8231 (K01-INV01) kutucuğuna tıklayarak teşhisini görün.\n");
end

function tf = ollamaRunning()
try
    webread("http://localhost:11434/api/version", weboptions(Timeout=2));
    tf = true;
catch
    tf = false;
end
end
