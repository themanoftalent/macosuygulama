import json, re

# Load manifest
manifest_path = "/Users/darwin/Documents/GitHub/macosuygulama/dist/windows-binaries/manifest.json"
with open(manifest_path, "r", encoding="utf-8") as f:
    manifest = json.load(f)

# Definition of the cards in Turkish and English
windows_apps = [
    {
        "id": "desktopduzen",
        "category": "productivity desktop",
        "icon": "/assets/apps/desktopduzen.png",
        "title_tr": "DesktopDüzen for Windows",
        "title_en": "DesktopDüzen for Windows",
        "version": "v1.0.0",
        "tagline_tr": "Windows Masaüstü Bölge ve Klasör Düzenleyici.",
        "tagline_en": "Windows Desktop Fences and Smart Folder Organizer.",
        "desc_tr": "Windows masaüstünüzde duvar kâğıdınıza sabitlenmiş özelleştirilebilir dosya, klasör ve uygulama bölgeleri oluşturan Fences tarzı modern masaüstü düzenleyici. Tek tıkla masaüstündeki dağınık dosyaları kategorilerine ayırır.",
        "desc_en": "Modern Fences-style desktop organizer for Windows that creates customizable file, folder, and app zones pinned to your desktop. Auto-categorizes messy desktop files with one click.",
        "tech_tags": ["Rust 2024", "Windows x64", "Win32 GUI", "Local-First", "Sıfır Telemetri", "asInvoker"],
        "exe_url": "https://github.com/themanoftalent/macosuygulama/releases/download/windows-v1.0.0/DesktopDuzen-1.0.0-windows-x64.exe",
        "exe_name": "DesktopDuzen-1.0.0-windows-x64.exe",
        "exe_size": manifest["desktopduzen"]["size_kb"],
        "zip_url": "https://github.com/themanoftalent/macosuygulama/releases/download/windows-v1.0.0/DesktopDuzen-1.0.0-windows-x64.zip",
        "hash": manifest["desktopduzen"]["exe_hash"],
        "repo": "https://github.com/themanoftalent/macosuygulama/tree/main/apps/windows-apps/desktopduzen",
        "release_url": "https://github.com/themanoftalent/macosuygulama/releases/tag/windows-v1.0.0",
    },
    {
        "id": "temizale",
        "category": "system",
        "icon": "/assets/apps/temizale.png",
        "title_tr": "Temizale for Windows",
        "title_en": "Temizale for Windows",
        "version": "v1.0.0",
        "tagline_tr": "Windows Sistem ve Geçici Dosya Temizleyici.",
        "tagline_en": "Windows System and Temporary Files Cache Cleaner.",
        "desc_tr": "Windows geçici klasörleri (%TEMP%), uygulama önbellekleri, döküm (dump) kalıntıları ve sistem çöplerini güvenle tarayıp temizleyen yerel Windows sürümü. Standart kullanıcı yetkisiyle güvenle çalışır, kilitli sistem dosyalarını atlar.",
        "desc_en": "Native Windows system cleaner that safely scans and cleans %TEMP%, application caches, crash dumps, and Recycle Bin. Runs safely with standard user privileges without elevation.",
        "tech_tags": ["Rust 2024", "Windows x64", "Win32 GUI", "Disk Optimizer", "Sıfır Telemetri", "asInvoker"],
        "exe_url": "https://github.com/themanoftalent/macosuygulama/releases/download/windows-v1.0.0/Temizale-1.0.0-windows-x64.exe",
        "exe_name": "Temizale-1.0.0-windows-x64.exe",
        "exe_size": manifest["temizale"]["size_kb"],
        "zip_url": "https://github.com/themanoftalent/macosuygulama/releases/download/windows-v1.0.0/Temizale-1.0.0-windows-x64.zip",
        "hash": manifest["temizale"]["exe_hash"],
        "repo": "https://github.com/themanoftalent/Temizale",
        "release_url": "https://github.com/themanoftalent/macosuygulama/releases/tag/windows-v1.0.0",
    },
    {
        "id": "miknatizale",
        "category": "productivity",
        "icon": "/assets/apps/miknatizale.png",
        "title_tr": "Miknatizale for Windows",
        "title_en": "Miknatizale for Windows",
        "version": "v1.0.0",
        "tagline_tr": "Hafif ve Hızlı Windows Pencere Hizalama & Ekran Bölme.",
        "tagline_en": "Ultra-lightweight Window Snapping & Tiling Manager for Windows.",
        "desc_tr": "Windows pencerelerinizi klavye kısayollarıyla (Win+Alt+Sol/Sağ/Yukarı/C) anında sol, sağ, merkez veya çeyrek ekranlara hizalayan ultra hafif, sıfır gecikmeli pencere yöneticisi.",
        "desc_en": "Ultra-lightweight, zero-latency window snapping manager for Windows. Snap active windows to halves, center, or quarters instantly with customizable hotkeys (Win+Alt+Arrows).",
        "tech_tags": ["Rust 2024", "Windows x64", "Pencere Yönetimi", "Sıfır Gecikme", "asInvoker"],
        "exe_url": "https://github.com/themanoftalent/macosuygulama/releases/download/windows-v1.0.0/Miknatizale-1.0.0-windows-x64.exe",
        "exe_name": "Miknatizale-1.0.0-windows-x64.exe",
        "exe_size": manifest["miknatizale"]["size_kb"],
        "zip_url": "https://github.com/themanoftalent/macosuygulama/releases/download/windows-v1.0.0/Miknatizale-1.0.0-windows-x64.zip",
        "hash": manifest["miknatizale"]["exe_hash"],
        "repo": "https://github.com/themanoftalent/Miknatizale",
        "release_url": "https://github.com/themanoftalent/macosuygulama/releases/tag/windows-v1.0.0",
    },
    {
        "id": "yenidosyale",
        "category": "finder productivity",
        "icon": "/assets/apps/saklamac.png",
        "title_tr": "YeniDosyale for Windows",
        "title_en": "YeniDosyale for Windows",
        "version": "v1.0.0",
        "tagline_tr": "Hızlı Yeni Dosya & Şablon Oluşturucu.",
        "tagline_en": "Instant New File & Template Generator for Windows.",
        "desc_tr": "Masaüstünde veya çalışma klasörünüzde tek kısayolla (Win+Shift+N) anında Metin, Markdown, Python, JSON, HTML veya CSV şablonları oluşturan pratik Windows üretkenlik aracı.",
        "desc_en": "Instantly create new Text, Markdown, Python, JSON, HTML, or CSV documents with custom naming and initial templates using a single shortcut (Win+Shift+N).",
        "tech_tags": ["Rust 2024", "Windows x64", "Şablon Yöneticisi", "Hızlı Üretim", "asInvoker"],
        "exe_url": "https://github.com/themanoftalent/macosuygulama/releases/download/windows-v1.0.0/YeniDosyale-1.0.0-windows-x64.exe",
        "exe_name": "YeniDosyale-1.0.0-windows-x64.exe",
        "exe_size": manifest["yenidosyale"]["size_kb"],
        "zip_url": "https://github.com/themanoftalent/macosuygulama/releases/download/windows-v1.0.0/YeniDosyale-1.0.0-windows-x64.zip",
        "hash": manifest["yenidosyale"]["exe_hash"],
        "repo": "https://github.com/themanoftalent/macosuygulama/tree/main/apps/windows-apps/yenidosyale",
        "release_url": "https://github.com/themanoftalent/macosuygulama/releases/tag/windows-v1.0.0",
    },
    {
        "id": "foldale",
        "category": "finder productivity",
        "icon": "/assets/apps/foldale.png",
        "title_tr": "Foldale for Windows",
        "title_en": "Foldale for Windows",
        "version": "v1.0.0",
        "tagline_tr": "Yüzen Geçici Dosya Tutucu & Taşıma Rafı.",
        "tagline_en": "Floating Temporary Drop Shelf and Staging Workspace.",
        "desc_tr": "Farklı klasörler, tarayıcılar ve uygulamalar arasında dosya taşırken öğeleri geçici olarak tutan, sürükle-bırak destekli şık yüzen Windows çalışma rafı.",
        "desc_en": "A sleek floating drop target window that temporarily holds dragged files and folders while navigating between different Explorer directories, apps, or browsers.",
        "tech_tags": ["Rust 2024", "Windows x64", "Drag & Drop", "Yüzen Raf", "asInvoker"],
        "exe_url": "https://github.com/themanoftalent/macosuygulama/releases/download/windows-v1.0.0/Foldale-1.0.0-windows-x64.exe",
        "exe_name": "Foldale-1.0.0-windows-x64.exe",
        "exe_size": manifest["foldale"]["size_kb"],
        "zip_url": "https://github.com/themanoftalent/macosuygulama/releases/download/windows-v1.0.0/Foldale-1.0.0-windows-x64.zip",
        "hash": manifest["foldale"]["exe_hash"],
        "repo": "https://github.com/themanoftalent/foldale",
        "release_url": "https://github.com/themanoftalent/macosuygulama/releases/tag/windows-v1.0.0",
    },
    {
        "id": "aleclip",
        "category": "menubar productivity",
        "icon": "/assets/apps/aleclip.png",
        "title_tr": "AleClip for Windows",
        "title_en": "AleClip for Windows",
        "version": "v1.0.0",
        "tagline_tr": "Modern & Hafif Windows Pano Yöneticisi.",
        "tagline_en": "Modern & Lightweight Native Clipboard Manager for Windows.",
        "desc_tr": "C# ve .NET 8 WPF ile Windows 10 & 11 için geliştirilmiş, odak çalmayan (WS_EX_NOACTIVATE) yüzen pano geçmişi. Alt+V ile anında açılır, doğrudan yapıştırma ve Türkçe büyük/küçük I/ı/İ/i uyumlu arama sunar.",
        "desc_en": "Built with C# and .NET 8 WPF for Windows 10 & 11. Non-activating floating panel (Alt+V) slides smoothly without stealing focus. Instant search with Turkish case-folding and direct paste.",
        "tech_tags": ["C# .NET 8", "WPF Native", "Pano Yöneticisi", "Local-First", "Tek Dosya EXE"],
        "exe_url": "https://github.com/themanoftalent/aleclip-windows/releases/download/v1.0.0/AleClip.exe",
        "exe_name": "AleClip.exe",
        "exe_size": "68.7 MB",
        "zip_url": "https://github.com/themanoftalent/aleclip-windows/releases/download/v1.0.0/AleClip-Windows-x64.zip",
        "hash": "405287386ed095c5b1d71effeb686aa2ed4fda3546bca4bd70405cf3ea102728",
        "repo": "https://github.com/themanoftalent/aleclip-windows",
        "release_url": "https://github.com/themanoftalent/aleclip-windows/releases/tag/v1.0.0",
    },
    {
        "id": "ekranale",
        "category": "media productivity",
        "icon": "/assets/apps/recordale.png",
        "title_tr": "Ekranale for Windows",
        "title_en": "Ekranale for Windows",
        "version": "v1.0.0",
        "tagline_tr": "Ekran Alıntısı, Çizim & Büyüteçli Renk Seçici.",
        "tagline_en": "Screen Capture, Snipping & Magnifying Color Picker.",
        "desc_tr": "Win+Shift+S veya PrintScreen ile anında tam ekran veya bölge yakalama. Görüntüyü doğrudan panoya kopyalar ve Resimler klasörüne kaydeder. İmleç altındaki pikselin HEX/RGB kodunu tek tıkla kopyalar.",
        "desc_en": "Instant screen capture and color picker via Win+Shift+S or PrintScreen. Copies bitmap directly to clipboard and saves to Pictures. Copies HEX/RGB color under cursor in one click.",
        "tech_tags": ["Rust 2024", "Windows x64", "Ekran Yakalama", "Renk Seçici", "asInvoker"],
        "exe_url": "https://github.com/themanoftalent/macosuygulama/releases/download/windows-v1.0.0/Ekranale-1.0.0-windows-x64.exe",
        "exe_name": "Ekranale-1.0.0-windows-x64.exe",
        "exe_size": manifest["ekranale"]["size_kb"],
        "zip_url": "https://github.com/themanoftalent/macosuygulama/releases/download/windows-v1.0.0/Ekranale-1.0.0-windows-x64.zip",
        "hash": manifest["ekranale"]["exe_hash"],
        "repo": "https://github.com/themanoftalent/macosuygulama/tree/main/apps/windows-apps/ekranale",
        "release_url": "https://github.com/themanoftalent/macosuygulama/releases/tag/windows-v1.0.0",
    },
    {
        "id": "alecal",
        "category": "menubar productivity",
        "icon": "/assets/apps/alecal.png",
        "title_tr": "AleCal for Windows",
        "title_en": "AleCal for Windows",
        "version": "v1.0.0",
        "tagline_tr": "Görev Çubuğu Hızlı Takvim & Canlı Saat.",
        "tagline_en": "Taskbar & System Tray Quick Calendar and Live Clock.",
        "desc_tr": "Windows görev çubuğunda bildirim alanında çalışan, tek tıkla açılan minimalist takvim aracı. Canlı saat, ay/yıl navigasyonu ve hafta numaraları sunar.",
        "desc_en": "Minimalist calendar tool docked above the Windows taskbar. Offers live time with seconds, full interactive month/year calendar grid, and weekend highlights.",
        "tech_tags": ["Rust 2024", "Windows x64", "Görev Çubuğu", "Hızlı Takvim", "asInvoker"],
        "exe_url": "https://github.com/themanoftalent/macosuygulama/releases/download/windows-v1.0.0/AleCal-1.0.0-windows-x64.exe",
        "exe_name": "AleCal-1.0.0-windows-x64.exe",
        "exe_size": manifest["alecal"]["size_kb"],
        "zip_url": "https://github.com/themanoftalent/macosuygulama/releases/download/windows-v1.0.0/AleCal-1.0.0-windows-x64.zip",
        "hash": manifest["alecal"]["exe_hash"],
        "repo": "https://github.com/themanoftalent/alecal",
        "release_url": "https://github.com/themanoftalent/macosuygulama/releases/tag/windows-v1.0.0",
    },
    {
        "id": "alebar",
        "category": "menubar system",
        "icon": "/assets/apps/alebar.png",
        "title_tr": "AleBar for Windows",
        "title_en": "AleBar for Windows",
        "version": "v1.0.0",
        "tagline_tr": "Görev Çubuğu Canlı Donanım & Performans Monitörü.",
        "tagline_en": "Taskbar Live Hardware & Performance Monitor.",
        "desc_tr": "Windows bildirim alanında gerçek zamanlı CPU, RAM ve bellek kullanımını canlı gösteren hafif sistem monitörü. Tıklandığında performans paneli ve Görev Yöneticisi kısayolu açar.",
        "desc_en": "Lightweight system monitor that displays real-time CPU and RAM percentage in the Windows notification area. Opens quick hardware gauge panel and Task Manager in one click.",
        "tech_tags": ["Rust 2024", "Windows x64", "Donanım Monitörü", "Canlı Gösterge", "asInvoker"],
        "exe_url": "https://github.com/themanoftalent/macosuygulama/releases/download/windows-v1.0.0/AleBar-1.0.0-windows-x64.exe",
        "exe_name": "AleBar-1.0.0-windows-x64.exe",
        "exe_size": manifest["alebar"]["size_kb"],
        "zip_url": "https://github.com/themanoftalent/macosuygulama/releases/download/windows-v1.0.0/AleBar-1.0.0-windows-x64.zip",
        "hash": manifest["alebar"]["exe_hash"],
        "repo": "https://github.com/themanoftalent/AleBar",
        "release_url": "https://github.com/themanoftalent/macosuygulama/releases/tag/windows-v1.0.0",
    },
    {
        "id": "aledesk",
        "category": "productivity system",
        "icon": "/assets/apps/aledesk.png",
        "title_tr": "AleDesk for Windows",
        "title_en": "AleDesk for Windows",
        "version": "v1.4.9",
        "tagline_tr": "Ultra Düşük Gecikmeli Uzak Masaüstü İstemcisi.",
        "tagline_en": "Ultra Low-Latency Remote Desktop Client for Windows.",
        "desc_tr": "Rust ve C++ temelinde yüksek kare hızlı, güvenli uçtan uca şifreli uzak masaüstü ve kontrol istemcisi. Windows 10 & 11 için bağımsız EXE ve MSI kurulum paketleriyle dağıtılmaktadır.",
        "desc_en": "High frame-rate, end-to-end encrypted remote desktop and control client built on Rust and C++. Distributed with standalone EXE and official MSI installer for Windows 10 & 11.",
        "tech_tags": ["Rust", "C++", "Windows x64", "Uzak Masaüstü", "MSI & EXE"],
        "exe_url": "https://github.com/themanoftalent/aledesk/releases/download/nightly/aledesk-1.4.9-x86_64.exe",
        "exe_name": "aledesk-1.4.9-x86_64.exe",
        "exe_size": "23.2 MB",
        "zip_url": "https://github.com/themanoftalent/aledesk/releases/download/nightly/aledesk-1.4.9-x86_64.msi",
        "hash": "390056823d1785edcf1e20234a50d619d3a307bdf2040ab2c61ee7b53e7d6828",
        "repo": "https://github.com/themanoftalent/aledesk",
        "release_url": "https://github.com/themanoftalent/aledesk/releases/tag/nightly",
    },
]

def render_cards(lang="tr"):
    html_cards = []
    for app in windows_apps:
        title = app["title_tr"] if lang == "tr" else app["title_en"]
        tagline = app["tagline_tr"] if lang == "tr" else app["tagline_en"]
        desc = app["desc_tr"] if lang == "tr" else app["desc_en"]
        tags_html = "".join([f'<span class="tech-tag">{t}</span>\n              ' for t in app["tech_tags"]])
        
        btn_dl = f"⬇ {app['exe_name']} ({app['exe_size']})" if lang == "en" else f"⬇ {app['exe_name']} İndir ({app['exe_size']})"
        btn_zip = "📦 Portable ZIP" if lang == "en" else "📦 Taşınabilir ZIP (Portable)"
        btn_rel = "Release Notes ↗" if lang == "en" else "Sürüm Notları ↗"
        pkg_title = "📦 Windows Distribution Packages" if lang == "en" else "📦 Windows Dağıtım Paketleri"
        compat = "Windows 10 / 11 Compatible" if lang == "en" else "Windows 10 / 11 Uyumlu"
        hash_lbl = f"{app['exe_name']} SHA-256 Digest:" if lang == "en" else f"{app['exe_name']} SHA-256 Özeti:"
        btn_copy = "Copy" if lang == "en" else "Kopyala"
        copied_txt = "Copied!" if lang == "en" else "Kopyalandı!"
        btn_sec = "Security & Verification Guide ↓" if lang == "en" else "Güvenlik & Kurulum Kılavuzu ↓"
        btn_repo = "Source Code ↗" if lang == "en" else "Kaynak Deposu ↗"
        status_txt = "● Live & Downloadable" if lang == "en" else "● Canlı & İndirilebilir"

        card = f"""          <!-- {title} -->
          <article class="app-card" data-category="{app['category']}">
            <div class="app-top">
              <img class="app-icon" src="{app['icon']}" alt="{title} Icon">
              <div class="app-title-group">
                <div style="display:flex;align-items:center;gap:6px;margin-bottom:4px;flex-wrap:wrap;">
                  <span class="os-badge windows">Windows</span>
                  <span class="status-badge live">{status_txt}</span>
                  <span class="version-pill">{app['version']}</span>
                </div>
                <h3>{title}</h3>
              </div>
            </div>
            <p class="app-tagline">{tagline}</p>
            <p class="app-desc">{desc}</p>
            
            <div class="tech-tags">
              {tags_html}
            </div>

            <!-- Direct Windows Downloads -->
            <div class="windows-downloads-group">
              <div class="windows-download-title">
                <span>{pkg_title}</span>
                <span style="font-size:11px;font-weight:600;color:#285640;">{compat}</span>
              </div>
              <div class="windows-download-buttons">
                <a class="btn-primary" href="{app['exe_url']}" download>
                  {btn_dl}
                </a>
                <a class="btn-secondary" href="{app['zip_url']}" download>
                  {btn_zip}
                </a>
                <a class="btn-secondary" href="{app['release_url']}" target="_blank" rel="noopener">
                  {btn_rel}
                </a>
              </div>

              <!-- SHA-256 Checksum Container -->
              <div class="hash-container">
                <div>
                  <span class="hash-label">{hash_lbl}</span>
                  <span class="hash-val">{app['hash']}</span>
                </div>
                <button class="copy-hash-btn" data-hash="{app['hash']}" data-copied-text="{copied_txt}">{btn_copy}</button>
              </div>
            </div>

            <div class="app-card-actions">
              <a class="btn-secondary" href="#windows-security">{btn_sec}</a>
              <a class="btn-secondary" href="{app['repo']}" target="_blank" rel="noopener">{btn_repo}</a>
            </div>
          </article>"""
        html_cards.append(card)
    return "\n\n".join(html_cards)

# Update file helper
