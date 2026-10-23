function v = vlmInterpret(ctx, rgb, dayData, opts)
%VLMINTERPRET Görsel-dil modeliyle skalogram + güç grafiğini sıfır-atış (zero-shot) yorumlar.
%   v = ges.agents.vlmInterpret(ctx, rgb, dayData)  — SENKRON (betikler/değerlendirme için)
%   rgb     : 64×64×3 fizik-RGB skalogram (ges.scalogram.makeImages)
%   dayData : struct — Time, Pdc (gerçek), Pexp (M1 beklenen), G (ışınım) — o günün serileri
%   v       : Label (sınıf), Confidence (0..1), ReasonTr (Türkçe gerekçe), Seconds, Raw
%   VLM'e sayısal ajanın kararı VERİLMEZ (bağımsız ikinci görüş). Yanıt JSON formatına
%   zorlanır; geçersiz yanıtta Label = "" döner ve füzyon VLM'i yok sayar.
%   Arayüzde bloklamamak için: ges.agents.vlmRequest + ges.llm.ollamaChatAsync + ges.agents.vlmParse.
arguments
    ctx (1,1) struct
    rgb (:,:,3) uint8
    dayData (1,1) struct
    opts.Options (1,1) struct = struct()
    opts.Think (1,1) logical = true
end

[messages, llmArgs] = ges.agents.vlmRequest(ctx, rgb, dayData, Options=opts.Options, Think=opts.Think);
try
    reply = ges.llm.ollamaChat(messages, llmArgs{:});
    v = ges.agents.vlmParse(ctx, reply);
catch err
    v = ges.agents.vlmParse(ctx, [], err);
end
end
