"""Writes the website's guide, privacy, blog and 404 pages from one shared template.

The home page (website/index.html) is written by hand. Edit the content below, then run
`make site` to regenerate the other pages, so their header, footer and SEO tags stay in step.
"""
import json
import os
import html

SITE = "https://dipeshrajoria007.github.io/SightShift/"
REPO = "https://github.com/DipeshRajoria007/SightShift"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "website")
DATE = "2026-09-30"
DATE_LONG = "30 September 2026"

GITHUB_ICON = '<svg viewBox="0 0 16 16" aria-hidden="true"><path fill="currentColor" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/></svg>'


def page(path, title, description, body, *, depth, current="", ld=None, og_type="website"):
    root = "../" * depth
    url = SITE + path
    blocks = ld or []
    ld_html = ""
    if blocks:
        ld_html = '<script type="application/ld+json">\n' + json.dumps({"@context": "https://schema.org", "@graph": blocks}, indent=2, ensure_ascii=False) + "\n</script>\n"

    def nav_link(href, label, key):
        attr = ' aria-current="page"' if key == current else ""
        return f'<a href="{root}{href}"{attr}>{label}</a>'

    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<meta name="description" content="{html.escape(description)}">
<link rel="canonical" href="{url}">
<meta name="theme-color" content="#07080b">
<meta name="color-scheme" content="dark">
<meta property="og:type" content="{og_type}">
<meta property="og:site_name" content="SightShift">
<meta property="og:title" content="{html.escape(title)}">
<meta property="og:description" content="{html.escape(description)}">
<meta property="og:url" content="{url}">
<meta property="og:image" content="{SITE}assets/img/og-image.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="{html.escape(title)}">
<meta name="twitter:description" content="{html.escape(description)}">
<meta name="twitter:image" content="{SITE}assets/img/og-image.png">
<link rel="icon" type="image/png" sizes="32x32" href="{root}assets/img/favicon-32.png">
<link rel="icon" type="image/png" sizes="64x64" href="{root}assets/img/favicon-64.png">
<link rel="apple-touch-icon" href="{root}assets/img/apple-touch-icon.png">
<link rel="manifest" href="{root}site.webmanifest">
<link rel="preload" href="{root}assets/fonts/instrument-serif.woff2" as="font" type="font/woff2" crossorigin>
<link rel="preload" href="{root}assets/fonts/hanken-grotesk.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="{root}assets/css/site.css">
<script>document.documentElement.classList.add("js")</script>
{ld_html}</head>
<body>
<a class="skip-link" href="#main">Skip to content</a>

<header class="site-header" data-header>
  <div class="container">
    <a class="brand" href="{root}" aria-label="SightShift home"><img src="{root}assets/img/icon-64.png" alt="" width="30" height="30">SightShift</a>
    <button class="nav-toggle" type="button" aria-expanded="false" aria-controls="site-nav" data-nav-toggle><span></span><span class="visually-hidden">Menu</span></button>
    <nav class="nav" id="site-nav" aria-label="Main">
      {nav_link("#how", "How it works", "how")}
      {nav_link("#demo", "Demo", "demo")}
      {nav_link("guide/", "Guide", "guide")}
      {nav_link("blog/", "Blog", "blog")}
      {nav_link("privacy/", "Privacy", "privacy")}
      <a class="btn btn--ghost btn--small" href="{REPO}">
        {GITHUB_ICON}
        GitHub
      </a>
    </nav>
  </div>
</header>

<main id="main">
{body}
</main>

<footer class="site-footer">
  <div class="container">
    <div class="footer-brand">
      <a class="brand" href="{root}"><img src="{root}assets/img/icon-64.png" alt="" width="30" height="30">SightShift</a>
      <p>Keyboard focus that follows your gaze. Built on a Mac, for Macs.</p>
    </div>
    <div>
      <h2>Product</h2>
      <ul>
        <li><a href="{root}#how">How it works</a></li>
        <li><a href="{root}#features">Features</a></li>
        <li><a href="{root}#demo">Live demo</a></li>
        <li><a href="{root}#install">Install</a></li>
      </ul>
    </div>
    <div>
      <h2>Resources</h2>
      <ul>
        <li><a href="{root}guide/">Setup guide</a></li>
        <li><a href="{root}blog/">Blog</a></li>
        <li><a href="{root}privacy/">Privacy policy</a></li>
      </ul>
    </div>
    <div>
      <h2>Project</h2>
      <ul>
        <li><a href="{REPO}">Source code</a></li>
        <li><a href="{REPO}/issues">Issues</a></li>
        <li><a href="{REPO}/blob/main/LICENSE">MIT license</a></li>
      </ul>
    </div>
    <div class="footer-legal">
      <span>© 2026 SightShift contributors · MIT License</span>
      <span>Not affiliated with Apple. Mac and macOS are trademarks of Apple Inc.</span>
    </div>
  </div>
</footer>

<script src="{root}assets/js/site.js" defer></script>
</body>
</html>
"""


def breadcrumbs(items):
    return {
        "@type": "BreadcrumbList",
        "itemListElement": [
            {"@type": "ListItem", "position": i + 1, "name": name, "item": SITE + path}
            for i, (name, path) in enumerate(items)
        ],
    }


def write(path, content):
    target = os.path.join(OUT, path, "index.html") if not path.endswith(".html") else os.path.join(OUT, path)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, "w") as f:
        f.write(content)
    print("wrote", os.path.relpath(target, OUT))


def article(slug, title, headline_html, description, lede, toc, body_html, related):
    path = f"blog/{slug}/"
    toc_html = "\n".join(f'<li><a href="#{anchor}">{html.escape(label)}</a></li>' for anchor, label in toc)
    related_html = "\n".join(
        f'<li><a href="../{s}/">{html.escape(t)}</a></li>' for s, t in related
    )
    body = f"""
<article>
  <div class="container page-hero">
    <nav class="breadcrumbs" aria-label="Breadcrumb"><a href="../../">SightShift</a> / <a href="../">Blog</a></nav>
    <h1>{headline_html}</h1>
    <p>{lede}</p>
    <p class="article-meta">Published {DATE_LONG} · SightShift</p>
  </div>
  <div class="container doc">
    <aside class="toc" aria-label="On this page">
      <span class="label">On this page</span>
      <ol>
{toc_html}
      </ol>
    </aside>
    <div class="prose">
{body_html}
      <div class="related">
        <h2 style="margin-top:0;font-size:1.8rem">Keep reading</h2>
        <ul>
{related_html}
          <li><a href="../../#demo">Try the interactive demo</a></li>
        </ul>
      </div>
    </div>
  </div>
</article>
"""
    ld = [
        {
            "@type": "BlogPosting",
            "headline": title,
            "description": description,
            "datePublished": DATE,
            "dateModified": DATE,
            "mainEntityOfPage": SITE + path,
            "image": SITE + "assets/img/og-image.png",
            "author": {"@type": "Organization", "name": "SightShift", "url": SITE},
            "publisher": {"@type": "Organization", "name": "SightShift", "logo": {"@type": "ImageObject", "url": SITE + "assets/img/icon-512.png"}},
        },
        breadcrumbs([("SightShift", ""), ("Blog", "blog/"), (title, path)]),
    ]
    write(path, page(path, f"{title} | SightShift", description, body, depth=2, current="blog", ld=ld, og_type="article"))


# ---------------------------------------------------------------- Guide

guide_toc = [
    ("requirements", "Requirements"),
    ("install", "Install"),
    ("first-run", "First run"),
    ("calibration", "Calibration"),
    ("everyday", "Everyday use"),
    ("settings", "Settings"),
    ("typing", "Typing and the mouse"),
    ("panes", "Split panes"),
    ("troubleshooting", "Troubleshooting"),
    ("uninstall", "Uninstall"),
]

guide_body = f"""
<section>
  <div class="container page-hero">
    <nav class="breadcrumbs" aria-label="Breadcrumb"><a href="../">SightShift</a> / Guide</nav>
    <h1>Set up <em>SightShift</em></h1>
    <p>Install it, give it the two permissions it needs, calibrate, and you're done in about two minutes. This guide also covers settings, split panes and what to do when something feels off.</p>
  </div>
  <div class="container doc">
    <aside class="toc" aria-label="On this page">
      <span class="label">On this page</span>
      <ol>
{"".join(f'        <li><a href="#{a}">{l}</a></li>' + chr(10) for a, l in guide_toc)}      </ol>
    </aside>
    <div class="prose">
      <h2 id="requirements">Requirements</h2>
      <ul>
        <li><strong>macOS 14 Sonoma or later</strong>, on an Apple silicon or Intel Mac.</li>
        <li><strong>Xcode 16 or later</strong> to build it. Xcode is free from the Mac App Store.</li>
        <li><strong>A camera that faces you.</strong> The built-in camera works best when the laptop sits in front of you. External webcams and Continuity Camera work too.</li>
      </ul>

      <h2 id="install">Install</h2>
      <p>SightShift builds from source with one command:</p>
<pre><code>git clone {REPO}.git
cd SightShift
make install</code></pre>
      <p><code>make install</code> builds the app, signs it, copies it to <code>/Applications</code> and opens it. To install without touching <code>/Applications</code>, run <code>INSTALL_DIR=~/Applications make install</code>. Other useful targets: <code>make run</code> builds and launches from the build folder, and <code>make test</code> runs the unit tests.</p>
      <p class="callout"><strong>Why a local certificate?</strong> macOS remembers camera and Accessibility permissions by code signature. The build script creates a self-signed certificate in its own keychain the first time you build, so your permissions survive every rebuild. Your login keychain isn't touched.</p>

      <h2 id="first-run">First run</h2>
      <p>SightShift lives in the menu bar (look for the eye). The first time it opens, a setup window walks you through three steps:</p>
      <ol>
        <li><strong>Allow the camera.</strong> SightShift uses it to see which way your head is turned. Frames are analysed in memory and thrown away.</li>
        <li><strong>Allow Accessibility.</strong> Click <em>Open Accessibility Settings</em> and switch on SightShift in the list. It needs this to move keyboard focus between windows and to notice when you're typing or using the mouse.</li>
        <li><strong>Calibrate</strong>, described next.</li>
      </ol>

      <h2 id="calibration">Calibration</h2>
      <p>A dot visits nine positions on each screen in turn, and SightShift records how your face looks while you follow it. It takes about 20 seconds per screen.</p>
      <ul>
        <li><strong>Sit the way you normally do</strong> and face each screen as you naturally would. Don't hold your head artificially still; SightShift needs to learn how you really turn.</li>
        <li><strong>Light your face</strong> from the front if you can. A bright window behind you makes it harder.</li>
        <li><strong>Press Esc</strong> to cancel at any time. If the camera loses your face, the dot waits for you.</li>
      </ul>
      <p>The summary at the end shows how well SightShift tells your screens apart, and warns you if two screens look too similar from the camera. Recalibrate after moving a monitor, the camera or your chair a lot. Small changes are absorbed automatically as you click.</p>

      <h2 id="everyday">Everyday use</h2>
      <ul>
        <li><strong>Just look and type.</strong> Rest your gaze on another screen for 300 ms and the window you last used there gets focus, with the pointer brought along.</li>
        <li><strong>Pause and resume</strong> with <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>G</kbd>, or from the menu bar. You can change the shortcut in Settings. SightShift also pauses by itself, camera off, while your Mac is locked or asleep.</li>
        <li><strong>Calibrate One Screen</strong> from the menu when you add or move a display. SightShift notifies you when a connected screen isn't calibrated yet, or when you switch cameras.</li>
        <li><strong>Show Gaze Dot</strong> displays where SightShift thinks you're looking. Handy while you get used to it.</li>
        <li><strong>Diagnostics</strong> shows what the camera sees, which screen SightShift is choosing and why it might be holding focus.</li>
      </ul>

      <h2 id="settings">Settings</h2>
      <div class="table-scroll">
      <table>
        <thead><tr><th>Setting</th><th>Default</th><th>What it does</th></tr></thead>
        <tbody>
          <tr><td>Delay before switching</td><td>300 ms</td><td>How long you must face another screen before it takes focus.</td></tr>
          <tr><td>Head turn needed</td><td>50%</td><td>How far toward another screen you turn before it wins. Higher means more deliberate.</td></tr>
          <tr><td>Bring the pointer along</td><td>On</td><td>Moves the pointer to the newly focused window when you switch screens.</td></tr>
          <tr><td>Focus the window or split pane I look at</td><td>On</td><td>Same-screen focus for windows and panes.</td></tr>
          <tr><td>Delay (same screen)</td><td>350 ms</td><td>Dwell time before a window or pane on the same screen takes focus.</td></tr>
          <tr><td>Click a terminal pane that won't take focus directly</td><td>On</td><td>Fallback for terminals that ignore accessibility focus requests.</td></tr>
          <tr><td>Split panes in VS Code, Cursor and other Electron editors</td><td>Off</td><td>See <a href="#panes">Split panes</a>.</td></tr>
          <tr><td>Wait while I'm typing</td><td>On</td><td>Holds focus until typing has paused.</td></tr>
          <tr><td>Typing pause</td><td>2 s</td><td>How long typing must pause before focus may move.</td></tr>
          <tr><td>Mouse rest</td><td>1.5 s</td><td>Focus never moves while you use the mouse or trackpad, or this long after.</td></tr>
          <tr><td>Learn from my clicks</td><td>On</td><td>Refines the model from where you click.</td></tr>
          <tr><td>Show gaze dot</td><td>Off</td><td>Shows where SightShift thinks you're looking.</td></tr>
        </tbody>
      </table>
      </div>

      <h2 id="typing">Typing and the mouse</h2>
      <p>SightShift is built to stay out of your way:</p>
      <ul>
        <li><strong>Glances are ignored.</strong> A new screen only wins after you've faced it for the full delay.</li>
        <li><strong>Focus holds while you type.</strong> If you turn to another screen right after typing, focus follows once typing has paused for the typing pause.</li>
        <li><strong>Reading while typing is respected.</strong> If your typing carries straight on through a turn, SightShift assumes you're reading the other screen while typing on this one and leaves focus alone until you look away and back.</li>
        <li><strong>The mouse stays in charge.</strong> Nothing moves while you use the mouse or trackpad, or for 1.5 seconds after.</li>
        <li><strong>Its own windows are left alone.</strong> While SightShift's Settings or Diagnostics window is active it only watches, so you can look around and see what it would do.</li>
      </ul>
      <p>If you like to start typing the moment you turn, lower the typing pause.</p>

      <h2 id="panes">Split panes</h2>
      <p>Pane focus works in apps that expose their panes through macOS Accessibility: iTerm2, Terminal, Ghostty, cmux, Xcode, JetBrains IDEs and Android Studio. When a terminal doesn't accept an accessibility focus request, SightShift clicks the middle of the pane, after checking that nothing else covers it. Editors are never clicked, because a click would move the caret. With mouse reporting on, vim and tmux will see that click; turn the fallback off if that bothers you.</p>
      <p>VS Code, Cursor, Windsurf, VSCodium and Hyper are built on Electron, which only reveals its panes when asked. Asking is what screen readers do, so these apps may switch into their screen reader mode. That's why pane focus for them is off until you enable it. To prevent the mode switch, set <code>"editor.accessibilitySupport": "off"</code> in their settings.</p>
      <p>Apps that draw everything themselves without accessibility information, such as kitty, WezTerm, Warp, Zed and Sublime Text, still get window focus but not pane focus. tmux panes live inside a single terminal pane, so keep using the tmux keys for those.</p>

      <h2 id="troubleshooting">Troubleshooting</h2>
      <h3>Nothing happens</h3>
      <p>Open <em>Diagnostics</em> from the menu bar. Check that your face is visible, that <em>Looking at</em> follows your head, and that Accessibility is allowed. If you just granted Accessibility, give it a second; SightShift notices on its own.</p>
      <h3>It picks the wrong screen</h3>
      <p>Recalibrate, facing each screen the way you normally would. If the summary says two screens look alike from the camera, turn your head a little more toward each, or move the camera so it faces you directly.</p>
      <h3>It switches when I don't want it to</h3>
      <p>Raise <em>Head turn needed</em> or <em>Delay before switching</em> in Settings, and check that <em>Wait while I'm typing</em> is on. Press <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>G</kbd> to pause any time.</p>
      <h3>Permissions seem stuck</h3>
      <p>Run <code>make reset-permissions</code> in the project folder, relaunch SightShift and grant them again.</p>
      <h3>The wrong camera is used</h3>
      <p>Pick the right one in Settings → Camera, then recalibrate so SightShift learns how that camera sees you.</p>

      <h2 id="uninstall">Uninstall</h2>
      <ol>
        <li>Quit SightShift from its menu.</li>
        <li>Delete <code>SightShift.app</code> from Applications.</li>
        <li>Delete your calibration: <code>rm -r ~/Library/Application\\ Support/SightShift</code></li>
        <li>Delete its preferences: <code>defaults delete app.sightshift.SightShift</code></li>
        <li>Remove its permissions: <code>tccutil reset Accessibility app.sightshift.SightShift</code> and <code>tccutil reset Camera app.sightshift.SightShift</code></li>
      </ol>
      <p>If you built it yourself, the <code>.signing</code> folder in the project holds the local certificate; delete it along with the project.</p>
    </div>
  </div>
</section>
"""

write("guide/", page(
    "guide/",
    "Set up SightShift: install, calibrate and use it on your Mac",
    "How to install SightShift, grant camera and Accessibility access, calibrate your screens, tune the settings and fix common problems.",
    guide_body,
    depth=1,
    current="guide",
    ld=[
        {
            "@type": "TechArticle",
            "headline": "Set up SightShift",
            "description": "Install SightShift, grant its permissions, calibrate and tune it.",
            "datePublished": DATE,
            "dateModified": DATE,
            "mainEntityOfPage": SITE + "guide/",
            "author": {"@type": "Organization", "name": "SightShift", "url": SITE},
            "proficiencyLevel": "Beginner",
        },
        breadcrumbs([("SightShift", ""), ("Guide", "guide/")]),
    ],
))

# ---------------------------------------------------------------- Privacy

privacy_toc = [("app", "The app"), ("stored", "What's stored"), ("permissions", "Permissions"), ("website", "This website"), ("demo", "The live demo"), ("contact", "Changes and contact")]

privacy_body = f"""
<section>
  <div class="container page-hero">
    <nav class="breadcrumbs" aria-label="Breadcrumb"><a href="../">SightShift</a> / Privacy</nav>
    <h1>Privacy, <em>plainly</em></h1>
    <p>SightShift looks at your face to tell which way you're turned, on your Mac, and forgets each frame immediately. Nothing is recorded, nothing is uploaded, and there's no account.</p>
    <p class="article-meta">Last updated {DATE_LONG}</p>
  </div>
  <div class="container doc">
    <aside class="toc" aria-label="On this page">
      <span class="label">On this page</span>
      <ol>
{"".join(f'        <li><a href="#{a}">{l}</a></li>' + chr(10) for a, l in privacy_toc)}      </ol>
    </aside>
    <div class="prose">
      <h2 id="app">The app</h2>
      <p>While tracking is on, SightShift reads camera frames at up to 720p and no more than 15 frames a second. Each frame is analysed in memory with Apple's Vision framework, which finds your face and its landmarks. From those, SightShift computes ten numbers: head yaw and pitch, two nose offsets, face asymmetry, eye direction, and the position and size of your face in the picture. The frame is then discarded. Frames are never written to disk and never leave your Mac.</p>
      <p><strong>SightShift makes no network requests.</strong> There is no account, no analytics, no crash reporting and no update check. The source code is public, so you can verify all of this.</p>

      <h2 id="stored">What's stored on your Mac</h2>
      <ul>
        <li><strong>Your calibration profile</strong>, at <code>~/Library/Application Support/SightShift/profile.json</code>. It holds the ten numbers for each calibration frame, plus up to 240 recent click samples per screen: the same numbers along with where on the screen you clicked. It contains no images.</li>
        <li><strong>Your preferences</strong>, in the standard macOS preferences system.</li>
      </ul>
      <p>Delete your calibration from Settings → <em>Delete Calibration…</em>, or remove the file. Learned clicks can be cleared on their own with <em>Forget</em> in Settings.</p>

      <h2 id="permissions">Permissions</h2>
      <ul>
        <li><strong>Camera</strong>, to see which way you're facing. The camera is off while SightShift is paused, while your Mac is locked or asleep, and until setup is complete.</li>
        <li><strong>Accessibility</strong>, to move keyboard focus between windows and panes, and to notice when you're typing or using the mouse so it can hold still. SightShift notes <em>when</em> you press a key, never <em>which</em> key.</li>
        <li><strong>Notifications</strong> (optional), only to tell you when a screen needs calibrating or when accuracy has dropped.</li>
      </ul>

      <h2 id="website">This website</h2>
      <p>This site is a set of static pages hosted on GitHub Pages. It sets no cookies and runs no analytics or trackers, and its fonts are served from this site. GitHub may log visitors' IP addresses to operate the service, as described in the <a href="https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement">GitHub General Privacy Statement</a>.</p>

      <h2 id="demo">The live demo</h2>
      <p>The demo on the home page works without a camera. If you choose <em>Use my camera</em>, your browser asks for permission and then runs Google's MediaPipe face tracker inside the page: the tracker code comes from the jsDelivr CDN and the face model from Google's servers. Video is processed locally in your browser tab and is never uploaded. The camera turns off when you click <em>Stop camera</em> or leave the page.</p>

      <h2 id="contact">Changes and contact</h2>
      <p>If this policy changes, this page will say so and the date above will move. Questions are welcome as <a href="{REPO}/issues">issues on GitHub</a>.</p>
    </div>
  </div>
</section>
"""

write("privacy/", page(
    "privacy/",
    "Privacy: SightShift never records or uploads anything",
    "SightShift analyses camera frames on your Mac and discards them immediately. No recording, no network requests, no account, no analytics.",
    privacy_body,
    depth=1,
    current="privacy",
    ld=[
        {"@type": "WebPage", "name": "Privacy", "url": SITE + "privacy/", "dateModified": DATE},
        breadcrumbs([("SightShift", ""), ("Privacy", "privacy/")]),
    ],
))

# ---------------------------------------------------------------- Blog posts

posts = [
    (
        "switch-focus-between-monitors-mac",
        "How to switch keyboard focus between monitors on a Mac",
        "Every way to move keyboard focus to another display on macOS: built-in shortcuts, Mission Control, window managers, and making focus follow where you look.",
    ),
    (
        "focus-follows-mouse-mac",
        "Focus follows mouse on macOS: what exists and a hands-free alternative",
        "macOS has no system-wide focus follows mouse. Here's what exists, from a hidden Terminal setting to AutoRaise, yabai and Amethyst, and the trade-offs.",
    ),
    (
        "stop-typing-into-the-wrong-window",
        "Stop typing into the wrong window on a multi-monitor Mac",
        "Why keystrokes land in the wrong window when you use several displays, how to see which window has focus, and how to make focus follow you.",
    ),
]

post1 = f"""
      <p>With two or three displays, finding a window is rarely the hard part. Getting the keyboard to it is. macOS sends your keystrokes to the focused window, which is wherever you last clicked, not wherever you happen to be looking. Here is every practical way to move focus between displays, from built-in shortcuts to fully automatic.</p>

      <h2 id="click">Click the window</h2>
      <p>The obvious method, and the one everyone uses. It's also the slowest once you notice it: hand off the keyboard, pointer across one or two screens, a click that must avoid buttons and links, hand back. Across a day of switching between an editor, a terminal and a browser, that adds up to hundreds of round trips.</p>

      <h2 id="command-tab">Command-Tab</h2>
      <p><kbd>⌘</kbd><kbd>Tab</kbd> switches between apps, and it works well when each display holds a different app. It is less helpful when the same app has windows on several displays, such as two browser windows or two terminals, because it activates the app rather than a particular window.</p>

      <h2 id="command-backtick">Command-backtick</h2>
      <p><kbd>⌘</kbd><kbd>`</kbd> moves focus to the next window of the frontmost app, and <kbd>⇧</kbd><kbd>⌘</kbd><kbd>`</kbd> goes back. It works across displays, so it's the quickest built-in way to hop between two windows of the same app. You can change the shortcut under System Settings → Keyboard → Keyboard Shortcuts → Keyboard, where it's called <em>Move focus to next window</em>.</p>

      <h2 id="control-f4">Control-F4</h2>
      <p>In the same list you'll find <em>Move focus to active or next window</em>, <kbd>⌃</kbd><kbd>F4</kbd> by default, with <kbd>⇧</kbd><kbd>⌃</kbd><kbd>F4</kbd> to go the other way. On most Mac keyboards you'll need to hold <kbd>fn</kbd> as well, unless you've set the top row to act as standard function keys.</p>

      <h2 id="mission-control">Mission Control</h2>
      <p><kbd>⌃</kbd><kbd>↑</kbd> (or the Mission Control key) spreads out every window so you can click the one you want. It's visual and reliable, but it's still a click, and a full-screen animation every time you switch.</p>

      <h2 id="window-managers">Window managers</h2>
      <p>Tiling window managers give you keyboard commands for moving between windows and displays. <a href="https://github.com/nikitabobko/AeroSpace">AeroSpace</a>, for example, has a <code>focus-monitor</code> command that takes <code>left</code>, <code>right</code>, <code>next</code> or <code>prev</code>; yabai and <a href="https://github.com/ianyh/Amethyst">Amethyst</a> offer similar commands. They're powerful and fast once learned, at the cost of adopting a whole way of arranging windows.</p>

      <h2 id="focus-follows-mouse">Focus follows mouse</h2>
      <p>Tools like <a href="https://github.com/sbmpost/AutoRaise">AutoRaise</a> and yabai's <code>focus_follows_mouse</code> option focus whatever window is under the pointer. That removes the click, but the pointer still has to travel, and on a multi-monitor setup it is often parked on a different screen from the one you're reading. We compare these options in <a href="../focus-follows-mouse-mac/">Focus follows mouse on macOS</a>.</p>

      <h2 id="focus-follows-gaze">Focus follows gaze</h2>
      <p><a href="../../">SightShift</a> takes a different route: it uses your webcam to see which way your head is turned and moves keyboard focus to the screen you're facing, to the window you last used there. On a single display it focuses the window or split pane you look at. It runs entirely on your Mac and is free and open source.</p>
      <ul>
        <li>Turn toward a screen, rest there for 300 ms, and type. The pointer comes along.</li>
        <li>Quick glances are ignored, and focus holds still while you type or use the mouse.</li>
        <li>Looking at a bezel doesn't flip focus back and forth, and looking at your phone is ignored.</li>
      </ul>
      <p>You can try the idea in the browser with the <a href="../../#demo">interactive demo</a>, or follow the <a href="../../guide/">setup guide</a>.</p>

      <h2 id="tips">Tips that help with any method</h2>
      <ul>
        <li><strong>Give each display its own Spaces.</strong> In System Settings → Desktop &amp; Dock → Mission Control, turn on <em>Displays have separate Spaces</em>. Each display gets its own menu bar, and the inactive ones are dimmed, which makes it clearer where focus is.</li>
        <li><strong>Match the arrangement to your desk.</strong> In System Settings → Displays → Arrange, place each display where it physically sits, so the pointer crosses between them where you expect.</li>
        <li><strong>Make focus visible.</strong> A border tool such as <a href="https://github.com/FelixKratz/JankyBorders">JankyBorders</a> draws a colored outline around the focused window, so you can see at a glance where your typing will go.</li>
      </ul>
"""

post2 = f"""
      <p>On Linux and other Unix desktops, many people run with "focus follows mouse": whichever window is under the pointer gets your keystrokes, no click needed. People who move to the Mac often go looking for the same setting and find that it isn't there. Here's what does exist, and what each option costs.</p>

      <h2 id="why">Why macOS doesn't have it</h2>
      <p>macOS is click-to-focus by design. One reason is the menu bar at the top of the screen: to reach an app's menus, the pointer has to travel up, often across other windows. With focus following the pointer, the focus (and the menu bar's contents) would change along the way. Any focus-follows-mouse tool for the Mac has to work around that.</p>

      <h2 id="terminal">Terminal only: a hidden setting</h2>
      <p>Apple's Terminal has a hidden preference that makes Terminal windows take focus when the pointer moves over them:</p>
<pre><code>defaults write com.apple.Terminal FocusFollowsMouse -string YES</code></pre>
      <p>Quit and reopen Terminal for it to take effect, and run the same command with <code>NO</code> to turn it off. It only applies to Terminal windows; every other app keeps click-to-focus.</p>

      <h2 id="autoraise">AutoRaise</h2>
      <p><a href="https://github.com/sbmpost/AutoRaise">AutoRaise</a> is a small open-source utility that raises and focuses the window under the pointer. You can set separate delays for raising and for focusing, so the pointer has to rest for a moment before anything happens, which helps it ignore windows you merely pass over.</p>

      <h2 id="yabai">yabai</h2>
      <p>The yabai window manager has a <code>focus_follows_mouse</code> setting. <code>autofocus</code> focuses the window under the pointer without raising it; <code>autoraise</code> also brings it to the front:</p>
<pre><code>yabai -m config focus_follows_mouse autofocus</code></pre>
      <p>A separate <code>mouse_follows_focus</code> setting does the reverse, moving the pointer when focus changes by keyboard.</p>

      <h2 id="amethyst">Amethyst</h2>
      <p><a href="https://github.com/ianyh/Amethyst">Amethyst</a>, a tiling window manager, includes a focus-follows-mouse option among its settings. If you already like tiling, it's a natural choice.</p>

      <h2 id="trade-offs">The trade-offs</h2>
      <ul>
        <li><strong>Accidental focus changes.</strong> The pointer crosses windows on its way somewhere else. Delays help, but they make every intentional switch slower too.</li>
        <li><strong>The pointer isn't where you're looking.</strong> On a multi-monitor desk, the pointer is often parked on the screen you used a minute ago. Focus follows it, not you.</li>
        <li><strong>Raising reshuffles windows.</strong> Auto-raise brings windows to the front as you pass, which can bury the one you wanted to keep visible.</li>
      </ul>

      <h2 id="gaze">A hands-free alternative: focus follows gaze</h2>
      <p>The pointer is a proxy for your attention. Your eyes are the real thing. <a href="../../">SightShift</a> uses the webcam to see which way you're facing and moves keyboard focus to that screen, window or split pane, leaving the pointer free for pointing. It brings the pointer along when you switch screens, so scrolling still works where you look.</p>
      <p>Because gaze wanders more than a pointer does, SightShift is deliberately calm: a new target has to hold your gaze for a moment, glances are ignored, focus holds still while you type or use the mouse, and poses aimed away from every screen are ignored. It runs entirely on your Mac and is free and open source.</p>

      <h2 id="which">Which should you pick?</h2>
      <ul>
        <li><strong>You mostly live in Terminal</strong> on one screen: try the hidden Terminal setting first.</li>
        <li><strong>You're a heavy mouse user</strong> who wants the click gone: AutoRaise.</li>
        <li><strong>You like tiling</strong>: yabai, AeroSpace or Amethyst.</li>
        <li><strong>You're keyboard-first on several displays</strong>: focus follows gaze. See it in the <a href="../../#demo">interactive demo</a>.</li>
      </ul>
"""

post3 = f"""
      <p>You're reading documentation on the left screen, you turn to the terminal on the right and type a command, and it lands in the documentation's search box. Or worse, in a chat window, and <kbd>Return</kbd> sends it. On a multi-monitor Mac this happens to everyone. Here's why, and how to stop it.</p>

      <h2 id="why">Why it happens</h2>
      <p>macOS sends keystrokes to one window at a time: the focused window, which is the one you last clicked or switched to. Moving your eyes, or even the pointer, to another screen doesn't change that. Your attention moved; focus didn't.</p>

      <h2 id="see-focus">See which window has focus</h2>
      <p>macOS does show focus, just quietly: the focused window's title bar and colored window controls are drawn in full, while other windows are dimmed, and the menu bar shows the name of the active app. A few changes make that much easier to notice:</p>
      <ul>
        <li><strong>Add a focus border.</strong> <a href="https://github.com/FelixKratz/JankyBorders">JankyBorders</a> draws a colored border around the focused window. Install it with <code>brew tap FelixKratz/formulae</code> and <code>brew install borders</code>, then pick an active color that stands out.</li>
        <li><strong>Give each display its own menu bar.</strong> With <em>Displays have separate Spaces</em> turned on (System Settings → Desktop &amp; Dock → Mission Control), each display has a menu bar and the inactive ones are dimmed.</li>
      </ul>

      <h2 id="guardrails">Add guardrails where mistakes hurt</h2>
      <ul>
        <li><strong>Make chat apps send with <kbd>⌘</kbd><kbd>Return</kbd>.</strong> Many chat apps can treat <kbd>Return</kbd> as a new line and send only with a modifier. In Slack, it's under Preferences → Advanced. A stray command then becomes a draft instead of a message.</li>
        <li><strong>Keep terminals on a screen you face often.</strong> Commands typed into the wrong place are harmless in a text editor and harmful in a shell.</li>
      </ul>

      <h2 id="switch-faster">Switch focus deliberately</h2>
      <p>Building the habit of switching focus before you type helps. <kbd>⌘</kbd><kbd>`</kbd> cycles through the frontmost app's windows across displays, and window managers such as AeroSpace can jump focus to another display with a key. We cover all the options in <a href="../switch-focus-between-monitors-mac/">How to switch keyboard focus between monitors on a Mac</a>.</p>

      <h2 id="follow-gaze">Or let focus follow you</h2>
      <p>The underlying problem is that focus doesn't know where you're looking. <a href="../../">SightShift</a> fixes exactly that: it watches which way your head is turned through the webcam and moves keyboard focus to the screen, window or split pane you're facing, so the text lands where your eyes are.</p>
      <p>It is careful about the cases that cause trouble in the first place:</p>
      <ul>
        <li><strong>Reading while typing.</strong> If you keep typing while you read another screen, focus stays where you're typing.</li>
        <li><strong>Glances.</strong> A quick look at another screen is ignored; focus moves only after you settle.</li>
        <li><strong>The mouse.</strong> While you use the mouse or trackpad, nothing moves.</li>
      </ul>
      <p>It runs entirely on your Mac, and it's free and open source. Try it in the <a href="../../#demo">interactive demo</a>, or follow the <a href="../../guide/">setup guide</a>.</p>

      <h2 id="checklist">Checklist</h2>
      <ol>
        <li>Turn on a focus border so you always see where typing goes.</li>
        <li>Turn on <em>Displays have separate Spaces</em>.</li>
        <li>Make chat apps send with <kbd>⌘</kbd><kbd>Return</kbd>.</li>
        <li>Learn <kbd>⌘</kbd><kbd>`</kbd>, or let focus follow your gaze.</li>
      </ol>
"""

article(
    posts[0][0], posts[0][1], "How to switch keyboard focus between <em>monitors</em> on a Mac", posts[0][2],
    "From built-in shortcuts to window managers to letting focus follow where you look: every practical way to get your typing onto the right display.",
    [("click", "Click the window"), ("command-tab", "Command-Tab"), ("command-backtick", "Command-backtick"), ("control-f4", "Control-F4"), ("mission-control", "Mission Control"), ("window-managers", "Window managers"), ("focus-follows-mouse", "Focus follows mouse"), ("focus-follows-gaze", "Focus follows gaze"), ("tips", "Tips")],
    post1,
    [(posts[1][0], posts[1][1]), (posts[2][0], posts[2][1])],
)
article(
    posts[1][0], posts[1][1], "Focus follows mouse on macOS, and a <em>hands-free</em> alternative", posts[1][2],
    "There's no system-wide setting, but there are options: a hidden Terminal preference, AutoRaise, yabai and Amethyst. Here's how they work and what they cost.",
    [("why", "Why macOS lacks it"), ("terminal", "Terminal's hidden setting"), ("autoraise", "AutoRaise"), ("yabai", "yabai"), ("amethyst", "Amethyst"), ("trade-offs", "The trade-offs"), ("gaze", "Focus follows gaze"), ("which", "Which to pick")],
    post2,
    [(posts[0][0], posts[0][1]), (posts[2][0], posts[2][1])],
)
article(
    posts[2][0], posts[2][1], "Stop typing into the <em>wrong window</em> on a multi-monitor Mac", posts[2][2],
    "Keystrokes follow focus, not your eyes. Here's how to see where your typing will go, add guardrails where mistakes hurt, and make focus follow you.",
    [("why", "Why it happens"), ("see-focus", "See which window has focus"), ("guardrails", "Add guardrails"), ("switch-faster", "Switch deliberately"), ("follow-gaze", "Let focus follow you"), ("checklist", "Checklist")],
    post3,
    [(posts[0][0], posts[0][1]), (posts[1][0], posts[1][1])],
)

# ---------------------------------------------------------------- Blog index

post_items = "\n".join(
    f"""      <li><a href="{slug}/"><h2>{html.escape(title)}</h2><p>{html.escape(desc)}</p><span class="label">Read →</span></a></li>"""
    for slug, title, desc in posts
)
blog_body = f"""
<section>
  <div class="container page-hero">
    <nav class="breadcrumbs" aria-label="Breadcrumb"><a href="../">SightShift</a> / Blog</nav>
    <h1>Notes on <em>focus</em></h1>
    <p>Practical guides for multi-monitor Macs, keyboard focus and working without reaching for the mouse.</p>
  </div>
  <div class="container">
    <ul class="post-list">
{post_items}
    </ul>
  </div>
</section>
"""
write("blog/", page(
    "blog/",
    "Blog: guides for focused multi-monitor work on Mac | SightShift",
    "Practical guides for multi-monitor Mac setups: switching focus between displays, focus follows mouse options, and avoiding typing into the wrong window.",
    blog_body,
    depth=1,
    current="blog",
    ld=[
        {"@type": "Blog", "name": "SightShift blog", "url": SITE + "blog/", "blogPost": [{"@type": "BlogPosting", "headline": t, "url": SITE + f"blog/{s}/"} for s, t, _ in posts]},
        breadcrumbs([("SightShift", ""), ("Blog", "blog/")]),
    ],
))

# ---------------------------------------------------------------- 404

not_found = page(
    "404.html",
    "Page not found | SightShift",
    "This page doesn't exist.",
    """
<section class="cta">
  <div class="container">
    <p class="label label--warn" style="color:var(--warn)">404</p>
    <h2 style="margin-top:18px">Lost <em>focus</em>.</h2>
    <p>This page doesn't exist, or it moved. Look over here instead:</p>
    <div class="hero__actions">
      <a class="btn btn--primary" href="/SightShift/">Go to the home page</a>
      <a class="btn btn--ghost" href="/SightShift/guide/">Read the setup guide</a>
    </div>
  </div>
</section>
""",
    depth=0,
)
# The 404 page is served at any depth, so it needs absolute paths.
not_found = not_found.replace('href="assets/', 'href="/SightShift/assets/').replace('src="assets/', 'src="/SightShift/assets/')
not_found = not_found.replace('href="site.webmanifest"', 'href="/SightShift/site.webmanifest"')
not_found = not_found.replace('href="#', 'href="/SightShift/#').replace('href="guide/"', 'href="/SightShift/guide/"').replace('href="blog/"', 'href="/SightShift/blog/"').replace('href="privacy/"', 'href="/SightShift/privacy/"').replace('href=""', 'href="/SightShift/"')
not_found = not_found.replace('<link rel="canonical" href="https://dipeshrajoria007.github.io/SightShift/404.html">', '<meta name="robots" content="noindex">')
not_found = not_found.replace('href="/SightShift/#main"', 'href="#main"')
write("404.html", not_found)
