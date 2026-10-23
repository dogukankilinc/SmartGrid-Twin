function runAllTests(opts)
%RUNALLTESTS SmartGridLab GES proje test paketini çalıştır.
%   runAllTests() — tüm test dosyalarını sırayla koşar ve sonuçları raporlar.
%   runAllTests(Verbose=false) — yalnızca başarısız testleri göster.
arguments
    opts.Verbose   (1,1) logical = true
    opts.StopFirst (1,1) logical = false   % ilk hata sonunda dur
end

addpath(fileparts(fileparts(mfilename("fullpath"))));
setupGes();

tests = {
    "tGesIo"         "SMA CSV okuma, ızgara dışı satırlar, R_iso binlik ayraç, coalesce"
    "tAssistant"     "LLM asistan, glossary, alertText, nedensel RAG"
    "tOpinions"      "3-Görüş uzlaşısı, elektriksel ikiz, öz-akran k-NN"
    "tCoreRegression" "M1 beklenen güç, istatistiksel regresyon (altın değerler)"
    "tDashboardSmoke" "Dashboard duman testi (ges.startup + arayüz oluşturma)"
};

nPass = 0; nFail = 0; nSkip = 0;
for k = 1:size(tests, 1)
    tName = tests{k,1};
    tDesc = tests{k,2};
    if opts.Verbose
        fprintf("\n[%d/%d] %s — %s\n", k, size(tests,1), tName, tDesc);
    end
    try
        suite  = testsuite(tName);
        result = run(suite);
        nOk = nnz([result.Passed]);
        nBad= nnz([result.Failed]);
        nPass = nPass + nOk;
        nFail = nFail + nBad;
        if opts.Verbose
            for r = result
                icon = "✓";
                if r.Failed; icon = "✗"; end
                fprintf("  %s  %s (%.2f s)\n", icon, r.Name, r.Duration);
            end
        end
        if nBad > 0 && opts.StopFirst
            break
        end
    catch ME
        nSkip = nSkip + 1;
        if opts.Verbose
            fprintf("  ⚠ ATLA (test dosyası bulunamadı veya hata): %s\n", ME.message);
        end
    end
end
fprintf("\n=== Test Özeti: %d geçti / %d başarısız / %d atlandı ===\n", nPass, nFail, nSkip);
if nFail == 0 && nSkip == 0
    fprintf("✅ Tüm testler başarıyla tamamlandı.\n");
elseif nFail > 0
    fprintf("❌ %d test başarısız!\n", nFail);
end
end
