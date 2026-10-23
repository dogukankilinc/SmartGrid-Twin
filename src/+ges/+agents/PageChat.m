classdef PageChat < handle
    %PAGECHAT Sayfa-kapsamlı asistan: YALNIZCA açık sayfanın içeriğiyle (RAG) ve hafızayla yanıt verir.
    %   s = ges.agents.PageChat();
    %   req = s.ask(ctx, "Bu invertör bugün neden kısıyor?", page);   % page: Name, Title, Chunks, Directory, Memory
    %   reply = ges.llm.ollamaChat(req.Messages, req.Args{:});         % ya da ollamaChatAsync
    %   answer = s.consume(reply);                                    % s.Answer, s.GoPage, s.Sources
    %   page.Chunks    : struct (Title, Text) — sayfanın o an gösterdiği bilgiler (sayılar, tablolar, metin)
    %   page.Directory : struct (Name, Title, Topics) — diğer sayfalar ve içerikleri (yönlendirme için)
    %   page.Memory    : struct (Title, Page, Text) — kullanıcının "📌 hafızaya al" ile sakladıkları
    %   Sorunun en ilgili parçaları ges.agents.retrieveChunks (BM25) ile seçilir; LLM'e yalnızca onlar,
    %   sayfa dizini ve hafıza verilir. Araç çağrısı yoktur (veri sayfadan gelir). Sayfada olmayan bilgi
    %   istenirse model ilgili sayfayı söyler ve "[[git:<Ad>]]" etiketi ekler; panel bunu düğmeye çevirir.

    properties (SetAccess = private)
        History cell = {}          % son turlar (sayfa değişince sıfırlanır)
        PageName string = ""
        Answer string = ""
        GoPage string = ""         % yanıtta önerilen sayfa (yoksa "")
        Sources string = strings(0, 1)   % yanıtta kullanılan parça başlıkları
        Hint string = ""           % deterministik yönlendirme ipucu (sorunun ait olduğu sayfa)
        Redirects (1,1) logical = false   % yanıt başka bir sayfaya yönlendiriyor mu
    end

    properties
        KeepTurns (1,1) double = 2
        TopK (1,1) double = 6
    end

    methods
        function req = ask(obj, ctx, question, page)
            question = strtrim(string(question));
            if obj.PageName ~= page.Name
                obj.History = {};
                obj.PageName = page.Name;
            end
            [idx, sc] = ges.agents.retrieveChunks(page.Chunks, question, obj.TopK);
            keep = idx(sc > 0);
            if isempty(keep)
                keep = (1:min(2, numel(page.Chunks)))';     % eşleşme yoksa sayfa özeti
            end
            if ~any(keep == 1) && ~isempty(page.Chunks)
                keep = [1; keep(1:min(end, obj.TopK - 1))];  % ilk parça her zaman: sayfanın özeti
            end
            obj.Sources = string({page.Chunks(keep).Title})';
            % Deterministik yönlendirme ipucu: soru başka bir sayfanın konularıyla daha çok eşleşiyorsa
            obj.Hint = "";
            if ~isempty(page.Directory)
                dirChunks = struct("Title", {page.Directory.Title}, "Text", {page.Directory.Topics});
                [di, ds] = ges.agents.retrieveChunks(dirChunks, question, 1);
                own = max([sc; 0]);
                if ~isempty(di) && ds(1) > 0 && page.Directory(di).Name ~= page.Name && ds(1) > 1.2 * own
                    obj.Hint = page.Directory(di).Name;
                end
            end
            ctxText = strings(0, 1);
            for i = keep'
                ctxText(end+1) = "[" + page.Chunks(i).Title + "] " + page.Chunks(i).Text; %#ok<AGROW>
            end
            memText = "(boş)";
            if ~isempty(page.Memory)
                memText = strjoin(compose("[%s — %s sayfası] %s", string({page.Memory.Title})', ...
                    string({page.Memory.Page})', string({page.Memory.Text})'), newline);
            end
            dirText = strjoin(compose("%s: %s", string({page.Directory.Title})', string({page.Directory.Topics})'), newline);
            user = "SORU: " + question + newline + newline + ...
                "SAYFA İÇERİĞİ (" + page.Title + "):" + newline + strjoin(ctxText, newline) + newline + newline + ...
                "HAFIZA (kullanıcının sakladığı bilgiler):" + newline + memText;
            if obj.Hint ~= ""
                user = user + newline + newline + "(Sistem notu: bu soru büyük olasılıkla '" + obj.Hint + ...
                    "' sayfasının konusu. Bu sayfanın içeriği yetmiyorsa oraya yönlendir.)";
            end
            sys = join([
                "Sen bir güneş enerjisi santralinin izleme panelindeki bakım asistanısın. Şu anki zaman: " + ...
                    string(ctx.Now, "yyyy-MM-dd HH:mm") + ". Kullanıcı şu an '" + page.Title + "' sayfasında."
                "Kurallar:"
                "1) YALNIZCA 'SAYFA İÇERİĞİ' ve 'HAFIZA' bölümlerindeki bilgilerle yanıt ver. Orada olmayan sayı, tarih veya"
                "   invertör bilgisini ASLA uydurma ya da tahmin etme."
                "2) Sorunun yanıtı bu sayfada yoksa, aşağıdaki SAYFA DİZİNİ'nden bilginin hangi sayfada olduğunu söyle ve"
                "   yanıtın sonuna tam olarak [[git:<sayfa adı>]] etiketini ekle (ör. [[git:Tahmin]])."
                "3) Kullanıcı karşılaştırma isterse HAFIZA'daki kaydı sayfa içeriğiyle karşılaştır; hafıza boşsa karşılaştırılacak"
                "   bilgiyi diğer sayfada '📌 Hafızaya al' ile saklamasını söyle."
                "4) Kısa, net, Türkçe yaz (en fazla 5 cümle). Markdown kullanma; gerekirse '• ' ile madde yaz. İngilizce kod yazma"
                "   (thermal = ısıl kısma, ok = sağlıklı, watch = izle, warning = uyarı)."
                "SAYFA DİZİNİ:"
                dirText], newline);
            obj.History = trimTurns(obj.History, obj.KeepTurns);
            msgs = [{struct("role", "system", "content", sys)}, obj.History, {struct("role", "user", "content", user)}];
            obj.History{end+1} = struct("role", "user", "content", question);   % geçmişte yalnız soru (bağlam şişmesin)
            obj.Answer = "";
            obj.GoPage = "";
            obj.Redirects = false;
            req = struct("Messages", {msgs}, "Args", {{"Model", ctx.Model, "Timeout", 120}});
        end

        function answer = consume(obj, reply)
            text = ges.llm.plainText(string(reply.Content));
            tok = regexp(text, "\[\[git:\s*([^\]]+)\]\]", "tokens", "once");
            text = strtrim(regexprep(text, "\[\[git:[^\]]*\]\]", ""));
            % Yönlendirme yalnızca yanıt gerçekten başka sayfayı işaret ediyorsa (küçük model yanıtı bu
            % sayfadan verdiği halde de etiket ekleyebiliyor → gereksiz "git" düğmesi)
            redirects = contains(lower(text), ["sayfasında" "sayfasına" "sayfasını" "sayfaya" "sayfasından" "sayfasına geç"]);
            obj.Redirects = redirects;
            if ~isempty(tok) && redirects
                obj.GoPage = strtrim(string(tok{1}));
            elseif obj.Hint ~= "" && redirects
                obj.GoPage = obj.Hint;
            end
            obj.Answer = text;
            obj.History{end+1} = struct("role", "assistant", "content", text);
            answer = text;
        end

        function fail(obj, message)
            obj.Answer = string(message);
            obj.GoPage = "";
        end
    end
end

function h = trimTurns(h, keep)
u = find(cellfun(@(m) string(m.role) == "user", h));
if numel(u) > keep
    h = h(u(end - keep + 1):end);
end
end
