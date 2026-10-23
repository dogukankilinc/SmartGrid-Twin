function buildNotifyPage(app, parent)
%BUILDNOTIFYPAGE Bildirimler: otonom bildirim kartları (en yeni üstte) + LLM ile yazdırma seçeneği.
g = uigridlayout(parent, [2 1], RowHeight={"fit", "1x"}, Padding=[2 2 2 2], RowSpacing=4);
tb = uigridlayout(g, [1 2], ColumnWidth={"fit", "1x"}, Padding=[4 0 4 0]);
app.Nt.LlmCheck = uicheckbox(tb, Text="Bildirimleri LLM yazsın", Value=false, ...
    Tooltip="Açıkken alarm bildirimleri önce kural tabanlı şablonla ANINDA düşer, ardından yerel LLM aynı içeriği akıcı Türkçeyle yeniden yazar (arka planda). Bilgi eklemez.");
uilabel(tb, Text="Kırmızı: arıza teşhisi · Turuncu: kontrol önerisi (ısıl kısma, ajan uyuşmazlığı) · Mavi: bilgi. " + ...
    "Bildirim; evirici alarma geçtiğinde veya uyarı 2 saati bulduğunda üretilir.", FontColor=[0.35 0.4 0.45]);
webDir = fullfile(fileparts(fileparts(mfilename("fullpath"))), "web");
app.Nt.Html = uihtml(g, HTMLSource=fullfile(webDir, "notify.html"), ...
    HTMLEventReceivedFcn=@(~, ev) app.onPanelReady(ev, "notify"));
app.Nt.Badge = true;
end
