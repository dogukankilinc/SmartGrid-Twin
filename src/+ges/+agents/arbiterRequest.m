function [messages, llmArgs] = arbiterRequest(ctx, r)
%ARBITERREQUEST LLM hakem bildirimi isteğini hazırlar (HTTP çağrısı YAPMAZ).
%   [messages, llmArgs] = ges.agents.arbiterRequest(ctx, r) — r: ges.agents.diagnoseDay çıktısı
%   LLM'e karar verisi değil, kural tabanlı TASLAK (ges.agents.alertText) verilir; görevi
%   yalnızca dili akıcılaştırmaktır. Böylece invertör adı, karar ve sayılar korunur, model
%   kullanılmayan ajandan söz edemez (önceki sürümde "<invertör>" yer tutucusunu kelimesi
%   kelimesine yazıyor ve VLM'in güvenilmez kök neden etiketini teşhis gibi aktarıyordu).
arguments
    ctx (1,1) struct
    r (1,1) struct
end

[draft, p] = ges.agents.alertText(ctx, r);
rules = [
    "Bir güneş santrali bakım ekibine gidecek alarm bildirimini düzenliyorsun."
    "TASLAK: " + draft
    "Taslağı 2-3 cümlelik akıcı, doğal Türkçe bir bildirime dönüştür."
    "Kurallar: invertör adını ('" + p.Name + "'), kararı, yüzdeleri, PV numaralarını ve öneriyi AYNEN koru."
    "Taslakta olmayan hiçbir bilgi, sayı, neden veya ajan EKLEME. Yalnızca bildirim metnini yaz; başlık, markdown, tırnak kullanma."];
if p.Severity == "check"
    rules(end+1) = "Metin tam olarak şu cümleyle bitmeli: 'Kararsız kaldık, lütfen " + p.Name + " invertörünü manuel kontrol ediniz.'";
else
    rules(end+1) = "'manuel kontrol' ifadesini kullanma.";
end
messages = {struct("role", "user", "content", join(rules, newline))};
llmArgs = {"Model", ctx.Model, "Temperature", 0.2, "Timeout", 120};   % num_ctx varsayılan (8192): model yeniden yüklenmez
end
