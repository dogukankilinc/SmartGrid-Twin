function v = vlmParse(ctx, reply, err)
%VLMPARSE VLM yanıtını (ges.agents.vlmRequest isteğine) teşhis yapısına çevirir.
%   v = ges.agents.vlmParse(ctx, reply)        — reply: ges.llm.ollamaChat çıktısı
%   v = ges.agents.vlmParse(ctx, [], err)      — çağrı hatası (MException)
%   v: Label (sınıf; geçersiz yanıtta ""), Confidence, ReasonTr, Seconds, Raw.
%   Label "" ise füzyon VLM'i yok sayar.
arguments
    ctx (1,1) struct
    reply = []
    err = []
end

v = struct("Label", "", "Confidence", NaN, "ReasonTr", "", "Seconds", NaN, "Raw", "");
if ~isempty(err)
    v.ReasonTr = "VLM yanıtı alınamadı: " + string(err.message);
    return
end
try
    v.Seconds = reply.Seconds;
    v.Raw = reply.Content;
    out = jsondecode(reply.Content);
    lab = lower(string(out.label));
    if ismember(lab, ctx.Classes)
        v.Label = lab;
    end
    v.Confidence = double(out.confidence);
    v.ReasonTr = string(out.reason_tr);
catch parseErr
    v.ReasonTr = "VLM yanıtı çözülemedi: " + string(parseErr.message);
end
end
