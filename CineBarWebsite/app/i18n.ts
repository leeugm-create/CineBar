export type Locale = "zh-Hans" | "zh-Hant" | "en" | "ja" | "ko";

export const locales: { code: Locale; path: string; label: string }[] = [
  { code: "zh-Hans", path: "/", label: "简体中文" },
  { code: "zh-Hant", path: "/zh-Hant", label: "繁體中文" },
  { code: "en", path: "/en", label: "English" },
  { code: "ja", path: "/ja", label: "日本語" },
  { code: "ko", path: "/ko", label: "한국어" },
];

export type RatingSource = { id: string; label: string };

export type Messages = {
  metaTitle: string;
  heroVersion: string;
  heroTitle1: string;
  heroTitle2: string;
  heroLede: string;
  download: string;
  install: string;
  installTitle: string;
  compat: string;
  demoHint: string;
  search: string;
  searchOpen: string;
  searchHint: string;
  searchLoading: string;
  searchEmpty: string;
  searchMovie: string;
  searchTV: string;
  searchHistory: string;
  searchClear: string;
  searchNoHistory: string;
  today: string;
  trending: string;
  watchlist: string;
  dailyRec: string;
  dailyBy: string;
  ratingsTitle: string;
  ratingsLead: string;
  ratingSources: readonly RatingSource[];
  navFeatures: string;
  navInstall: string;
  navSupport: string;
  featuresTitle: string;
  features: readonly [string, string][];
  steps: readonly string[];
  supportTitle: string;
  supportLead: string;
  supportAction: string;
  supportNote: string;
  releases: string;
  contactTitle: string;
  contactLinks: readonly [string, string, string][];

  langLabel: string;
  appearance: string;
  supportPageTitle: string;
  supportPageNote: string;
  supportMethod: string;
  tip: { note: string };
  paypal: string;
  paypalDesc: string;
  payNow: string;
  wechat: string;
  wechatDoc: string;
  alipay: string;
  alipayDoc: string;
  backHome: string;
};

export const messages: Record<Locale, Messages> = {
  "zh-Hans": {
    metaTitle: "CineBar — 找到下一部好片",
    heroVersion: "CineBar for macOS · 0.8.3-test.16（Build 60）测试版",
    heroTitle1: "找到",
    heroTitle2: "下一部好片",
    heroLede: "一个找电影、电视剧的 app。",
    download: "下载 macOS 测试版",
    install: "查看安装说明 →",
    installTitle: "三步开始使用",
    compat: "支持 Apple 芯片与 Intel Mac · 免费 · 无广告 · 无订阅",
    demoHint: "悬停菜单栏，看它在 Mac 上的样子",
    search: "找片名、剧名…",
    searchOpen: "搜索",
    searchHint: "输入至少两个字开始搜索",
    searchLoading: "搜索中…",
    searchEmpty: "没有找到相关影片",
    searchMovie: "电影",
    searchTV: "剧集",
    searchHistory: "搜索历史",
    searchClear: "清除",
    searchNoHistory: "暂无搜索历史",
    today: "每日推荐",
    trending: "本周热门",
    watchlist: "我的片单",
    dailyRec: "每日推荐",
    dailyBy: "根据你的类型与地区偏好",
    ratingsTitle: "电影电视剧，点了就能看",
    ratingsLead:
      "详情页直接播放正片：电影即点即播，剧集按季选集；弹幕开关、倍速、浮窗与全屏随叫随到。评分也一次看全——豆瓣、TMDB、IMDb、烂番茄、Metacritic、CineBar 社区评分，全部聚在一处，不用一个个网站去翻。",
    ratingSources: [
      { id: "douban", label: "豆瓣" },
      { id: "tmdb", label: "TMDB" },
      { id: "imdb", label: "IMDb" },
      { id: "rottentomatoes", label: "烂番茄" },
      { id: "metacritic", label: "Metacritic" },
      { id: "cinebar", label: "CineBar 社区" },
    ],
    navFeatures: "功能",
    navInstall: "安装",
    navSupport: "支持",
    featuresTitle: "找片需要的信息，一处看清",
    features: [
      ["发现", "本周热门、每日推荐、即将上映与今日播出。"],
      ["多重评分", "TMDB、IMDb、烂番茄、Metacritic、CineBar 社区与豆瓣评分。"],
      ["完整资料", "演员、剧照、预告片、分级、上映日期与播出时间。"],
      ["片单与提醒", "收藏电影和电视剧，并设置定档、下一集与下一季提醒。"],
      ["本地片库", "分类与状态可组合筛选；确认匹配后打开完整资料，其他文件仅显示本地详情。"],
      ["正版入口", "查看不同地区的合法观看平台。"],
      ["多语言", "支持简体中文、繁体中文、英语、日语与韩语。"],
    ],
    steps: [
      "从上方 Build 60 固定地址下载测试包并解压，把 CineBar.app 移入“应用程序”文件夹。",
      "双击或右键打开 CineBar（首次打开时若系统询问，选择“打开”）。",
      "若弹出“Apple 无法验证开发者”，请打开“系统设置”→“隐私与安全”→“安全性”，找到被阻止的 CineBar，点击“仍要打开”，输入密码或验证 Touch ID，然后重新打开 CineBar 即可。",
    ],
    supportTitle: "免费、无广告、无订阅",
    supportLead: "如果 CineBar 为你节省了找片时间，可以请作者喝一杯咖啡。",
    supportAction: "支持 CineBar →",
    supportNote: "一次性自愿支持，不会解锁任何功能，也不是订阅。",
    releases: "GitHub 发行",
    contactTitle: "联系我",
    contactLinks: [
      [
        "Email",
        "leeugm@vip.qq.com",
        "mailto:leeugm@vip.qq.com",
      ],
      [
        "GitHub",
        "leeugm-create/CineBar",
        "https://github.com/leeugm-create/CineBar",
      ],
    ],
    langLabel: "语言",
    appearance: "改变外观",
    supportPageTitle: "支持 CineBar",
    supportPageNote: "感谢关注。选择你习惯的方式即可，所有支持都是一次性的、自愿的。",
    supportMethod: "选择支付方式",
    tip: { note: "扫码支持 CineBar" },
    paypal: "PayPal",
    paypalDesc: "用 PayPal 账号或银行卡支付",
    payNow: "前往 PayPal →",
    wechat: "微信支付",
    wechatDoc: "扫一扫，金额随心意",
    alipay: "支付宝",
    alipayDoc: "扫一扫，金额随心意",
    backHome: "返回首页",
  },
  "zh-Hant": {
    metaTitle: "CineBar — 找到下一部好片",
    heroVersion: "CineBar for macOS · 0.8.3-test.16（Build 60）測試版",
    heroTitle1: "找到",
    heroTitle2: "下一部好片",
    heroLede: "一個找電影、電視劇的 app。",
    download: "下載 macOS 測試版",
    install: "查看安裝說明 →",
    installTitle: "三步開始使用",
    compat: "支援 Apple 晶片與 Intel Mac · 免費 · 無廣告 · 無訂閱",
    demoHint: "將游標移到選單欄，看看它在 Mac 上的樣子",
    search: "搜尋片名、劇名…",
    searchOpen: "搜尋",
    searchHint: "輸入至少兩個字開始搜尋",
    searchLoading: "搜尋中…",
    searchEmpty: "沒有找到相關影片",
    searchMovie: "電影",
    searchTV: "劇集",
    searchHistory: "搜尋紀錄",
    searchClear: "清除",
    searchNoHistory: "暫無搜尋紀錄",
    today: "每日推薦",
    trending: "本週熱門",
    watchlist: "我的片單",
    dailyRec: "每日推薦",
    dailyBy: "根據你的類型與地區偏好",
    ratingsTitle: "電影電視劇，點了就能看",
    ratingsLead:
      "詳情頁直接播放正片：電影即點即播，劇集按季選集；彈幕開關、倍速、浮窗與全螢幕隨叫隨到。評分也一次看全——豆瓣、TMDB、IMDb、爛番茄、Metacritic、CineBar 社群評分，全部集中在一處，不用一個一個網站去翻。",
    ratingSources: [
      { id: "douban", label: "豆瓣" },
      { id: "tmdb", label: "TMDB" },
      { id: "imdb", label: "IMDb" },
      { id: "rottentomatoes", label: "爛番茄" },
      { id: "metacritic", label: "Metacritic" },
      { id: "cinebar", label: "CineBar 社群" },
    ],
    navFeatures: "功能",
    navInstall: "安裝",
    navSupport: "支持",
    featuresTitle: "找片需要的資訊，一處看清",
    features: [
      ["發現", "本週熱門、每日參考、即將上映與今日播出。"],
      ["多重評分", "TMDB、IMDb、爛番茄、Metacritic、CineBar 社群與豆瓣評分。"],
      ["完整資料", "演員、劇照、預告片、分級、上映日期與播出時間。"],
      ["片單與提醒", "收藏電影和劇集，並設定上映日期、下一集與下一季提醒。"],
      ["本機片庫", "分類與狀態可組合篩選；確認配對後開啟完整資料，其他檔案只顯示本地詳情。"],
      ["正版入口", "查看不同地區的合法觀看平台。"],
      ["多語言", "支援簡體中文、繁體中文、英語、日語與韓語。"],
    ],
    steps: [
      "從上方 Build 60 固定連結下載測試包並解壓，把 CineBar.app 移入「應用程式」資料夾。",
      "雙擊或右鍵開啟 CineBar（首次開啟時若系統詢問，選擇「開啟」）。",
      "若出現「Apple 無法驗證開發者」，請開啟「系統設定」→「隱私權與安全性」→「安全性」，找到被阻擋的 CineBar，點擊「仍要開啟」，輸入密碼或驗證 Touch ID，然後重新開啟 CineBar 即可。",
    ],
    supportTitle: "免費、無廣告、無訂閱",
    supportLead: "如果 CineBar 為你省下了找片的時間，可以請作者喝一杯咖啡。",
    supportAction: "支持 CineBar →",
    supportNote: "一次性自願支持，不會解鎖任何功能，也不是訂閱。",
    releases: "GitHub 發行",
    contactTitle: "聯絡我",
    contactLinks: [
      [
        "Email",
        "leeugm@vip.qq.com",
        "mailto:leeugm@vip.qq.com",
      ],
      [
        "GitHub",
        "leeugm-create/CineBar",
        "https://github.com/leeugm-create/CineBar",
      ],
    ],
    langLabel: "語言",
    appearance: "變更外觀",
    supportPageTitle: "支持 CineBar",
    supportPageNote: "感謝關注。選擇你習慣的方式即可，所有支持都是一次性的、自願的。",
    supportMethod: "選擇支付方式",
    tip: { note: "掃碼支持 CineBar" },
    paypal: "PayPal",
    paypalDesc: "使用 PayPal 帳號或信用卡支付",
    payNow: "前往 PayPal →",
    wechat: "微信支付",
    wechatDoc: "掃一掃，金額隨心意",
    alipay: "支付宝",
    alipayDoc: "掃一掃，金額隨心意",
    backHome: "返回首頁",
  },
  en: {
    metaTitle: "CineBar — Find your next great film",
    heroVersion: "CineBar for macOS · 0.8.3-test.16 (Build 60) Beta",
    heroTitle1: "Find your",
    heroTitle2: "next great film",
    heroLede: "An app for finding movies & TV shows.",
    download: "Download the macOS beta",
    install: "See the install guide →",
    installTitle: "Three steps to get started",
    compat: "Apple Silicon & Intel Mac · Free · No ads · No subscription",
    demoHint: "Hover over the menu bar to see it on a Mac",
    search: "Search movies, shows…",
    searchOpen: "Search",
    searchHint: "Type at least two characters",
    searchLoading: "Searching…",
    searchEmpty: "No matching titles",
    searchMovie: "Movie",
    searchTV: "TV Show",
    searchHistory: "Search History",
    searchClear: "Clear",
    searchNoHistory: "No search history",
    today: "Daily Picks",
    trending: "Trending this week",
    watchlist: "My watchlist",
    dailyRec: "Daily Picks",
    dailyBy: "Based on your taste & region",
    ratingsTitle: "Movies & shows, play on tap",
    ratingsLead: "Play right from the detail page: movies start instantly, TV shows pick a season and episode. Danmaku toggle, playback speed, floating window and fullscreen are all at hand. And every score — TMDB, IMDb, Rotten Tomatoes, Metacritic, CineBar community and Douban — in one place, no web surfing.",
    ratingSources: [
      { id: "tmdb", label: "TMDB" },
      { id: "imdb", label: "IMDb" },
      { id: "rottentomatoes", label: "Rotten Tomatoes" },
      { id: "metacritic", label: "Metacritic" },
      { id: "cinebar", label: "CineBar Community" },
      { id: "douban", label: "Douban" },
    ],
    navFeatures: "Features",
    navInstall: "Install",
    navSupport: "Support",
    featuresTitle: "Everything you need to pick a film, in one screen",
    features: [
      ["Discover", "Trending this week, daily picks, opening soon and airing today."],
      ["All ratings", "TMDB, IMDb, Rotten Tomatoes, Metacritic, CineBar community and Douban."],
      ["Full details", "Cast, stills, trailers, age rating, release dates and air times."],
      ["Watchlist & alerts", "Save movies and shows; set reminders for opening day, next episode, next season."],
      ["Local library", "Combine category with status filters; matches open full details, others stay local only."],
      ["Where to watch", "See legal streaming options for your region."],
      ["Multilingual", "Supports Simplified & Traditional Chinese, English, Japanese and Korean."],
    ],
    steps: [
      "Download and unzip the beta from the fixed Build 60 link above, then move CineBar.app into your Applications folder.",
      "Double-click CineBar — or right-click and choose Open on first launch if asked.",
      "If macOS says it can't verify the developer, open System Settings → Privacy & Security → Security, find the blocked CineBar, click Open Anyway (or “Still Open”), confirm with your password or Touch ID, then open CineBar again.",
    ],
    supportTitle: "Free forever — no ads, no subscription",
    supportLead: "If CineBar saved you time finding films, feel free to buy the author a coffee.",
    supportAction: "Support CineBar →",
    supportNote: "One-time, completely voluntary. It unlocks nothing and is not a subscription.",
    releases: "GitHub Releases",
    contactTitle: "Contact",
    contactLinks: [
      [
        "Email",
        "leeugm@vip.qq.com",
        "mailto:leeugm@vip.qq.com",
      ],
      [
        "GitHub",
        "leeugm-create/CineBar",
        "https://github.com/leeugm-create/CineBar",
      ],
    ],
    langLabel: "Language",
    appearance: "Toggle appearance",
    supportPageTitle: "Support CineBar",
    supportPageNote: "Thanks for stopping by. Pick whatever feels right — all support is one-time and voluntary.",
    supportMethod: "Choose a payment method",
    tip: { note: "Scan to support CineBar" },
    paypal: "PayPal",
    paypalDesc: "Pay with your PayPal account or card",
    payNow: "Go to PayPal →",
    wechat: "WeChat Pay",
    wechatDoc: "Scan to pay, any amount you like",
    alipay: "Alipay",
    alipayDoc: "Scan to pay, any amount you like",
    backHome: "Back to home",
  },
  ja: {
    metaTitle: "CineBar — 次の名作を見つけよう",
    heroVersion: "CineBar for macOS · 0.8.3-test.16（Build 60）テスト版",
    heroTitle1: "次の名作を",
    heroTitle2: "見つけよう",
    heroLede: "映画・ドラマを探せるアプリ。",
    download: "macOS テスト版をダウンロード",
    install: "インストール手順を見る →",
    installTitle: "3ステップで使い始める",
    compat: "Apple シリコンと Intel Mac に対応 · 無料 · 広告なし · サブスクなし",
    demoHint: "メニューバーにカーソルを当てると、Mac で見ているように表示",
    search: "映画、ドラマを検索…",
    searchOpen: "検索",
    searchHint: "2文字以上入力してください",
    searchLoading: "検索中…",
    searchEmpty: "該当する作品がありません",
    searchMovie: "映画",
    searchTV: "ドラマ",
    searchHistory: "検索履歴",
    searchClear: "クリア",
    searchNoHistory: "検索履歴はありません",
    today: "今日のおすすめ",
    trending: "今週のトレンド",
    watchlist: "マイリスト",
    dailyRec: "今日のおすすめ",
    dailyBy: "あなたの好みと地域に基づく",
    ratingsTitle: "映画もドラマも、タップで再生",
    ratingsLead: "詳細ページから本編を直接再生：映画は即再生、ドラマはシーズン・話数ごとに選択。弾幕のON/OFF、再生速度、フローティング、フルスクリーンもすぐに使えます。評価もまとめて確認——TMDB、IMDb、Rotten Tomatoes、Metacritic、CineBar コミュニティ、Douban まで、サイトを回らずに一画面で。",
    ratingSources: [
      { id: "tmdb", label: "TMDB" },
      { id: "imdb", label: "IMDb" },
      { id: "rottentomatoes", label: "Rotten Tomatoes" },
      { id: "metacritic", label: "Metacritic" },
      { id: "cinebar", label: "CineBar コミュニティ" },
      { id: "douban", label: "Douban" },
    ],
    navFeatures: "機能",
    navInstall: "インストール",
    navSupport: "サポート",
    featuresTitle: "映画を選ぶのに必要な情報を、ひとつの画面で",
    features: [
      ["発見", "今週のトレンド、今日のおすすめ、まもなく公開、今日の放送分。"],
      ["多彩な評価", "TMDB、IMDb、Rotten Tomatoes、Metacritic、CineBar コミュニティと豆瓣。"],
      ["詳しい情報", "キャスト、静止画、予告編、レーティング、公開日と放送時間。"],
      ["ウォッチリストと通知", "映画・ドラマを保存し、公開日・次話・次シーズンの通知を設定。"],
      ["ローカルライブラリ", "カテゴリーと状態で絞り込み。一致したものだけ完全な情報に。"],
      ["視聴先", "地域に応じた正規の視聴先を確認。"],
      ["多言語対応", "簡体字・繁体字中国語、英語、日本語、韓国語に対応。"],
    ],
    steps: [
      "上記の固定リンク（Build 60）からテスト版をダウンロードして解凍し、CineBar.app を Applications フォルダに移します。",
      "CineBar をダブルクリック、または右クリックで「開く」を選んで起動します（初回は確認が出る場合があります）。",
      "「Apple が開発元を検証できません」と表示されたら、「システム設定」→「プライバシーとセキュリティ」→「セキュリティ」でブロックされた CineBar の「このまま開く」をクリックし、パスワードまたは Touch ID で確認して、再度 CineBar を開きます。",
    ],
    supportTitle: "無料のままで、広告なし、サブスクなし",
    supportLead: "CineBar が映画探しの時間を節約してくれたなら、作者にコーヒー一本をごちそうできます。",
    supportAction: "CineBar を支援 →",
    supportNote: "ワンタイムの任意の支援です。機能が解放されるわけでも、サブスクでもありません。",
    releases: "GitHub リリース",
    contactTitle: "お問い合わせ",
    contactLinks: [
      [
        "Email",
        "leeugm@vip.qq.com",
        "mailto:leeugm@vip.qq.com",
      ],
      [
        "GitHub",
        "leeugm-create/CineBar",
        "https://github.com/leeugm-create/CineBar",
      ],
    ],
    langLabel: "言語",
    appearance: "外観を切り替え",
    supportPageTitle: "CineBar をサポート",
    supportPageNote: "ご覧いただきありがとうございます。お好みの方法でどうぞ — すべて一回限り・任意です。",
    supportMethod: "お支払い方法を選択",
    tip: { note: "スキャンして CineBar を支援" },
    paypal: "PayPal",
    paypalDesc: "PayPal アカウントかカードで",
    payNow: "PayPal へ →",
    wechat: "WeChat Pay",
    wechatDoc: "スキャンして、好きな額で",
    alipay: "Alipay",
    alipayDoc: "スキャンして、好きな額で",
    backHome: "ホームに戻る",
  },
  ko: {
    metaTitle: "CineBar — 다음 영화를 찾아보세요",
    heroVersion: "CineBar for macOS · 0.8.3-test.16 (Build 60) 베타",
    heroTitle1: "다음 볼",
    heroTitle2: "영화를 찾아보세요",
    heroLede: "영화·드라마를 찾아주는 앱.",
    download: "macOS 베타 다운로드",
    install: "설치 방법 보기 →",
    installTitle: "3단계로 시작",
    compat: "Apple 실리콘과 Intel Mac · 무료 · 광고 없음 · 구독 없음",
    demoHint: "메뉴 바에 커서를 올리면 Mac 화면처럼 보입니다",
    search: "영화·드라마 검색…",
    searchOpen: "검색",
    searchHint: "두 글자 이상 입력하세요",
    searchLoading: "검색 중…",
    searchEmpty: "해당 작품이 없습니다",
    searchMovie: "영화",
    searchTV: "드라마",
    searchHistory: "검색 기록",
    searchClear: "지우기",
    searchNoHistory: "검색 기록이 없습니다",
    today: "오늘의 추천",
    trending: "이번 주 인기",
    watchlist: "내 목록",
    dailyRec: "오늘의 추천",
    dailyBy: "취향과 지역에 기반한 추천",
    ratingsTitle: "영화와 드라마, 탭하면 재생",
    ratingsLead: "상세 페이지에서 본편을 바로 재생: 영화는 즉시, 드라마는 시즌·회차별 선택. 탄막 켜기/끄기, 재생 속도, 플로팅, 전체 화면도 바로 사용 가능합니다. 평점도 한곳에서 — TMDB, IMDb, Rotten Tomatoes, Metacritic, CineBar 커뮤니티, Douban 평점까지, 사이트를 돌지 않고 확인하세요.",
    ratingSources: [
      { id: "tmdb", label: "TMDB" },
      { id: "imdb", label: "IMDb" },
      { id: "rottentomatoes", label: "Rotten Tomatoes" },
      { id: "metacritic", label: "Metacritic" },
      { id: "cinebar", label: "CineBar 커뮤니티" },
      { id: "douban", label: "Douban" },
    ],
    navFeatures: "기능",
    navInstall: "설치",
    navSupport: "지원",
    featuresTitle: "영화를 고를 때 필요한 모든 것, 한 화면에서",
    features: [
      ["발견", "이번 주 인기, 오늘의 추천, 개봉 예정, 오늘 방영."],
      ["모든 평점", "TMDB, IMDb, Rotten Tomatoes, Metacritic, CineBar 커뮤니티, Douban."],
      ["상세 정보", "출연진, 스틸컷, 예고편, 연령 등급, 개봉일, 방송 시간."],
      ["목록과 알림", "영화와 시리즈 저장, 개봉일·다음 회·다음 시즌 알림 설정."],
      ["로컬 라이브러리", "분류와 상태 조합 필터. 일치한 것만 자세히, 나머지는 로컬에서만."],
      ["시청처 확인", "지역별 정식 스트리밍 옵션을 확인하세요."],
      ["다국어 지원", "중국어(간체·번체), 영어, 일본어, 한국어 지원."],
    ],
    steps: [
      "위의 고정 링크(Build 60)에서 테스트 버전을 다운로드해 압축을 풀고, CineBar.app을 응용 프로그램 폴더로 옮깁니다.",
      "CineBar를 더블 클릭하거나 마우스 오른쪽 버튼 클릭 후 '열기'를 선택해 실행합니다(첫 실행 시 시스템이 묻는 경우).",
      "'Apple이 개발자를 확인할 수 없다'는 메시지가 나오면 '시스템 설정'→'개인정보 및 보안'→'보안'에서 차단된 CineBar를 찾아 '그래도 열기'를 클릭하고 암호 또는 Touch ID로 확인한 뒤 CineBar를 다시 실행합니다.",
    ],
    supportTitle: "무료 유지, 광고 없음, 구독 없음",
    supportLead: "CineBar가 영화 찾는 시간을 아꼈다면, 저자에게 커피 한 잔을 사주세요.",
    supportAction: "CineBar 지원 →",
    supportNote: "일회성, 자발적 후원입니다. 어떤 기능도 잠금 해제되지 않으며 구독이 아닙니다.",
    releases: "GitHub 릴리스",
    contactTitle: "문의하기",
    contactLinks: [
      [
        "Email",
        "leeugm@vip.qq.com",
        "mailto:leeugm@vip.qq.com",
      ],
      [
        "GitHub",
        "leeugm-create/CineBar",
        "https://github.com/leeugm-create/CineBar",
      ],
    ],
    langLabel: "언어",
    appearance: "화면 모드 전환",
    supportPageTitle: "CineBar 지원하기",
    supportPageNote: "찾아 주셔서 감사합니다. 편한 방법을 골라 주세요. 아래 후원은 일회성·자발적입니다.",
    supportMethod: "결제 방법 선택",
    tip: { note: "스캔해서 CineBar 후원" },
    paypal: "PayPal",
    paypalDesc: "PayPal 계정 또는 카드로",
    payNow: "PayPal로 이동 →",
    wechat: "WeChat Pay",
    wechatDoc: "스캔하여 원하는 금액 지원",
    alipay: "알리페이",
    alipayDoc: "스캔하여 원하는 금액 지원",
    backHome: "홈으로 돌아가기",
  },
};

export const defaultLocale: Locale = "zh-Hans";