function tests = tAssistant
%TASSISTANT Sayfa asistanının LLM'den BAĞIMSIZ, deterministik kısımları (araştırma katmanı).
%   Arama (BM25 + Türkçe katlama), yönlendirme ipucu, yanıt ayrıştırma ([[git:..]] düğmesi). LLM'in
%   kendisi test edilmez (stokastik); testler, LLM'e doğru bağlamın gittiğini ve yanıtın doğru
%   işlendiğini garanti eder.
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename("fullpath"))));
setupGes();
end

function testTurkishFoldingAndStemming(tc)
t = ges.agents.textTokens("Isıl kısma İNVERTÖRÜN performansı K03-INV46");
tc.verifyTrue(all(ismember(["isil" "kisma" "inver" "perfo" "k03-inv46" "k03" "inv46"], t)));
tc.verifyEqual(ges.agents.textTokens("invertörün"), ges.agents.textTokens("invertör"));
end

function testRetrievePicksRelevantChunk(tc)
chunks = pageChunks();
idx = ges.agents.retrieveChunks(chunks, "en düşük performanslı invertör hangisi?", 3);
tc.verifyEqual(chunks(idx(1)).Title, "En düşük performans");
idx = ges.agents.retrieveChunks(chunks, "K03-INV46 neden kısıyor", 3);
tc.verifyEqual(chunks(idx(1)).Title, "Isıl kısma");
end

function testHintRedirectsToOwningPage(tc)
s = ges.agents.PageChat();
page = struct("Name", "overview", "Title", "Genel Bakış", "Chunks", pageChunks(), "Directory", directory(), "Memory", []);
s.ask(struct("Now", datetime(2025, 5, 20, 12, 0, 0), "Model", "test"), "yarın ısıl kısma tahmini ne?", page);
tc.verifyEqual(s.Hint, "forecast");
s.ask(struct("Now", datetime(2025, 5, 20, 12, 0, 0), "Model", "test"), "en düşük performanslı invertör", page);
tc.verifyEqual(s.Hint, "", "Sayfanın kendi konusu için yönlendirme yapılmamalı");
end

function testConsumeAcceptsGoTagOnlyWithRedirectWords(tc)
s = ges.agents.PageChat();
page = struct("Name", "overview", "Title", "Genel Bakış", "Chunks", pageChunks(), "Directory", directory(), "Memory", []);
s.ask(struct("Now", datetime(2025, 5, 20, 12, 0, 0), "Model", "test"), "yarın kısma olur mu", page);
a = s.consume(struct("Content", "Bu bilgi Tahmin sayfasında. [[git:Tahmin]]"));
tc.verifyEqual(s.GoPage, "Tahmin");
tc.verifyFalse(contains(a, "[[git"), "Etiket yanıt metninden temizlenmeli");
s.ask(struct("Now", datetime(2025, 5, 20, 12, 0, 0), "Model", "test"), "bugünkü üretim", page);
s.consume(struct("Content", "Bugün 12,4 MWh üretildi. [[git:Tahmin]]"));
tc.verifyEqual(s.GoPage, "", "Yanıt bu sayfadan verildiyse gereksiz yönlendirme düğmesi çıkmamalı");
end

function c = pageChunks()
c = struct("Title", {"Özet", "En düşük performans", "Isıl kısma", "Enerji"}, ...
    "Text", {"Tesis anlık güç 12 MW, performans %96.", ...
    "En düşük performanslı invertörler: K12-INV05 %81, K15-INV11 %84.", ...
    "K03-INV46 ısıl kısmada, iç sıcaklık 63 °C, kayıp 12 kWh.", ...
    "Bugün üretilen enerji 12,4 MWh; aylık 310 MWh."});
end

function d = directory()
d = struct("Name", {"overview", "forecast", "reports"}, "Title", {"Genel Bakış", "Tahmin & Erken Uyarı", "Raporlar"}, ...
    "Topics", {"tesis toplam anlık güç, bugünkü üretim enerjisi, performans yüzdesi, en düşük performanslı invertörler", ...
    "gelecek tahmini, hava tahmini, yarın ısıl kısma tahmini, arıza riski, erken uyarı", ...
    "kayıp dağılımı, tozlanma oranı, degradasyon, bakım temizlik aralığı"});
end
