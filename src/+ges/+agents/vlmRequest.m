function [messages, llmArgs] = vlmRequest(ctx, rgb, dayData, opts)
%VLMREQUEST VLM isteğini hazırlar (grafik çizimi + istem); HTTP çağrısı YAPMAZ.
%   [messages, llmArgs] = ges.agents.vlmRequest(ctx, rgb, dayData)
%   Senkron kullanım: reply = ges.llm.ollamaChat(messages, llmArgs{:})
%   Asenkron kullanım: ges.llm.ollamaChatAsync(messages, onDone, llmArgs{:})
%   Yanıt ges.agents.vlmParse ile çözülür. Grafik ana iş parçacığında çizilir (~0,3 s);
%   uzun süren model çağrısı arka plana alınabilir.
arguments
    ctx (1,1) struct
    rgb (:,:,3) uint8
    dayData (1,1) struct
    opts.Options (1,1) struct = struct()
    opts.Think (1,1) logical = true          % akıl yürütme modu: VLM doğruluğunu belirgin artırır
end

plotFile = string(tempname) + ".png";
fileCleaner = onCleanup(@() deleteIfExists(plotFile));
% Küçük VLM'ler sıkışık grafiği okuyamıyor (640×360 / 90 dpi'de sıfır güç çizgisini "beklenene
% yakın" diye halüsinasyon gördü). Büyük, kalın çizgili, iki serili ve açık lejantlı grafik
% kullanılır; ışınım serisi bilinçli olarak çizilmez.
% Figür gizli ve HandleVisibility="off": başka kodun gcf/gca'sı olamaz; hata olsa da kapanır
% (aksi halde sızan figürlere tarih eksenli çizim "time zone" hatası veriyordu).
fig = figure(Visible="off", Position=[100 100 900 500], Color="w", HandleVisibility="off");
figCleaner = onCleanup(@() delete(fig));
ax = axes(fig, FontSize=13);
plot(ax, dayData.Time, dayData.Pdc, "-", LineWidth=3, Color=[0 0.2 0.8]);
hold(ax, "on");
plot(ax, dayData.Time, dayData.Pexp, "--", LineWidth=3, Color=[0.95 0.4 0]);
hold(ax, "off");
legend(ax, ["ACTUAL power" "EXPECTED power"], FontSize=14, Location="northwest");
ylabel(ax, "DC power (kW)", FontSize=14);
grid(ax, "on");
exportgraphics(fig, plotFile, Resolution=150);
chart64 = ges.llm.imageToBase64(plotFile);

classes = ctx.Classes;
prompt = join([
    "Image 1 is a physics-RGB wavelet scalogram of ONE solar inverter for ONE day."
    "x-axis: time of day 05:00 (left) to 21:00 (right). y-axis: wavelet scale, short periods (fast changes) at the TOP, long periods (slow daily shape) at the BOTTOM."
    "Red channel = inverter DC power, Green channel = solar irradiance, Blue channel = power SHORTFALL versus the expected power model."
    "Reading guide: yellow (red+green) = power follows the sun normally; cyan (green+blue, no red) = sun present but no power (outage);"
    "blue/magenta tones = power shortfall; bright red patches at short periods around midday = power oscillating or capped (thermal derating);"
    "faint, smooth, uniform blue = small uniform loss (soiling); shortfall starting at a certain time = a string disconnected."
    "Image 2 is a line chart of the same day: ACTUAL DC power (solid blue) and EXPECTED power from a physical model (dashed orange)."
    "First compare the two lines carefully (peak values, when and by how much the blue line falls below the orange line), then classify."
    "Classify the most likely condition as exactly one of: " + strjoin(classes, ", ") + "."
    "Clouds alone (power tracks the dashed line) mean healthy. A whole-cabin outage cannot be distinguished from an inverter trip in one image; prefer inverter_trip for outages."
    "Respond ONLY with JSON: {""label"": ""<class>"", ""confidence"": <0..1>, ""reason_tr"": ""<one or two sentences in Turkish>""}"], " ");

messages = {struct("role", "user", "content", prompt, ...
    "images", {{ges.llm.imageToBase64(rgb, Size=448), chart64}})};
llmArgs = {"Model", ctx.Model, "Format", "json", "Temperature", 0.1, "NumCtx", 8192, ...
    "Options", opts.Options, "Think", opts.Think};
end

function deleteIfExists(f)
if isfile(f)
    delete(f);
end
end
