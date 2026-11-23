# Twin-Pane Explorer  ·  دوصفحه‌ای برای ترموکس

یک **فایل‌منیجر دوصفحه‌ای ترمینالی** به سبک **Norton Commander** (همان `nc` قدیمی ویندوز) که مخصوص
**Termux روی اندروید** ساخته شده است — بدون نیاز به روت، بدون GUI و بسیار سبک.

```
 Twin-Pane Explorer                                              Tab:switch  F1:help  F10:quit
┌─ ~ ─────────────────────────────────────────┐┌─ /sdcard ─────────────────────────────────────┐
│ Name                     Size  Modified     ││ Name                      Size  Modified     │
│ [Download]              <DIR>  Nov 22 10:34 ││ [DCIM]                   <DIR>  Nov 22 10:34 │
│ [projects]              <DIR>  Nov 22 10:34 ││ [Download]               <DIR>  Nov 22 10:34 │
│• .bashrc                  28B  Nov 22 10:34 ││  download.zip             4.1M  Nov 22 10:34 │
│  backup.tar.gz           2.3M  Nov 22 10:34 ││                                              │
│• notes.txt                18B  Nov 22 10:34 ││                                              │
│  setup.sh                 10B  Nov 22 10:34 ││                                              │
│                                             ││                                              │
│                                             ││                                              │
│drwxr-xr-x .bashrc  28B                    N^ ││drwxr-xr-x DCIM  (1 items)                 N^ │
└─────────────────────────────────────────────┘└──────────────────────────────────────────────┘
Tab=switch  c/F5=copy  m/F6=move  F7=new  F8=delete  F10=quit   |   selected: 2
1 Help  2 Refresh  3 View  4 Edit  5 Copy  6 Move  7 MkDir  8 Delete  9 Menu  10 Quit
```

> پیش‌نمایش زنده (اسکرین‌شات‌های **رنگی** استخراج‌شده از خود برنامه): `docs/preview/index.html`

**تازه در ۱.۱** — لاگ روزانه، ادامه از همان‌جایی که بودید، ۱۰ تم قابل‌تغییر، معماری
پارامتری + پلاگین، پکیج واقعی Termux (`.deb`) و مسیر ساخت `.exe` ویندوز.

## چرا این؟

- **دوصفحه واقعی**: پنل چپ = خانه‌ی Termux، پنل راست = `/sdcard` (حافظه‌ی گوشی)
- **ماوس و لمس**: کلیک/تپ = انتخاب، دابل‌تپ = باز کردن، **کشیدن از یک پنل به پنل دیگر = کپی**،
  چرخ ماوس = اسکرول، سوایپ عمودی = اسکرول در حالت گوشی
- **چیدمان خودکار**: روی ترمینال عریض کنار هم (چپ/راست)، روی گوشی عمودی یک پنل تمام‌عرض
  با سوئیچر بالای آن (بالا/پایین) — کلید `L` یا منوی `F9`
- **zip / unzip داخلی**: بدون نصب هیچ بسته‌ای؛ zip، tar.gz، پیش‌نمایش محتوا، و محافظت
  کامل در برابر `zip-slip` (`../` و مسیرهای مطلق رد می‌شوند)
- **ساخت فولدر/فایل روی درایو دلخواه**: `F7` اول می‌پرسد کدام پنل/درایو، مسیر دستی هم می‌شود داد
- **کپی / انتقال با یک کلید**: `F5` کپی، `F6` انتقال (انتقال بین فایل‌سیستم‌های مختلف
  خودکار به «کپی + حذف» تبدیل می‌شود، چون `/sdcard` روی اندروید یک FUSE mount است و rename بین‌شوتری جواب نمی‌دهد)
- **نوار پیشرفت واقعی** با سرعت، حجم، و **قابلیت لغو** (`Esc`)
- **مدیریت تداخل**: Overwrite / Skip / Rename / All / Keep-both
- **بدون وابستگی**: فقط پایتون ۳ و ماژول `curses` که در Termux هست (`zipfile`/`tarfile` هم جزو استانداردند)
- **بازخوانی خودکار**: فایلی که برنامه‌ی دیگری می‌سازد، بدون `F2` ظاهر می‌شود
- **آشتی با صفحه‌کلید اندروید**: کلیدهای جهت‌دار در هر دو حالت terminfo (normal / application) کار می‌کنند
- **هر عملیاتی که `cp -r` و `mv` و `rm -rf` می‌دهند** با تاییدیه و گزارش خطای per-file

> **دانلود آماده (APK · EXE · deb · zip):**
> [Releases v1.1.1](https://github.com/HaadiTaba111/-/releases/tag/v1.1.1)
>
> **راهنمای نصب قدم‌به‌قدم:** [`docs/HOW-TO-RUN-FA.md`](docs/HOW-TO-RUN-FA.md)

## نصب در Termux — یک دستور، همه‌چیز

```bash
curl -fsSL https://raw.githubusercontent.com/HaadiTaba111/-/main/twin-pane-explorer/scripts/termux-install.sh | bash
```

کلون → نصب وابستگی‌ها → دسترسی حافظه → نصب در `$PREFIX` → تست → **اجرا**.
از آن به بعد فقط `twinpane`.

بدون `curl`:

```bash
git clone --depth 1 https://github.com/HaadiTaba111/-.git ~/twinpane-src \
  && bash ~/twinpane-src/twin-pane-explorer/scripts/termux-install.sh
```

گزینه‌ها: `--install` · `--update` · `--run` · `--doctor` · `--uninstall`

```bash
# یا نصب از پکیج آماده (بدون کپی سورس):
python build_dist.py                 # dist/twinpane_1.1.1_all.deb می‌سازد
pkg install ./dist/twinpane_1.1.1_all.deb
```

`scripts/termux-install.sh` خودش python و ncurses را نصب می‌کند، `termux-setup-storage`
را صدا می‌زند و در پایان یک **self-test** واقعی (ساخت zip و استخراج) می‌گیرد.
برای حذف: `... | bash -s -- --uninstall`.

### ساده‌ترین راه: یک فایل، بدون نصب

```bash
python build_dist.py     # می‌سازد: dist/twinpane-1.1.1-standalone.py  
```

همان یک فایل را به گوشی بفرستید (تلگرام، USB، ایمیل، هر چیزی) و:

```bash
pkg install python && termux-setup-storage
python twinpane-1.1.1-standalone.py            # اجرا
python twinpane-1.1.1-standalone.py --install  # یا: نصب دستور twinpane
```

هیچ چیز دیگری لازم نیست — نه git، نه اینترنت، نه unzip. کل برنامه (base64)
داخل همان یک فایل است.

سپس:

```bash
twin          # یا twinpane  → پنل چپ: خانه‌ی ترموکس، پنل راست: /sdcard
explorer      # همان چیز با مسیرهای صریح
twinpane -l ~/Download -r /sdcard/Download   # مسیرها دلخواه
```

اگر روی گوشی خودتان اجرا نمی‌کنید و فقط می‌خواهید امتحان کنید:

```bash
python3 twinpane.py -l . -r /tmp
```

## کلیدها

| کلید | کار |
|---|---|
| **کلیک / تپ** | انتخاب (و فعال‌کردن همان پنل) |
| **دابل‌کلیک / دابل‌تپ** | باز کردن پوشه یا نمایش فایل |
| **کشیدن بین پنل‌ها** | کپی آیتم به پنل دیگر (با تاییدیه) |
| چرخ ماوس / سوایپ عمودی | اسکرول لیست |
| `L` یا `F9` → Switch layout | جابه‌جایی بین چپ/راست و بالا/پایین |
| `↑` `↓` `PgUp` `PgDn` `Home` `End` | حرکت |
| `Enter` | باز کردن پوشه / نمایش فایل |
| `Backspace` | رفتن به پوشه‌ی والد |
| `Tab` یا `←` `→` | تغییر پنل فعال |
| `Space` | انتخاب آیتم و رفتن به بعدی |
| `+` / `-` | انتخاب همه / حذف انتخاب |
| **`c` یا `F5`** | **کپی → پنل دیگر** |
| **`m` یا `F6`** | **انتقال → پنل دیگر** |
| `F7` | پوشه‌ی جدید (**انتخاب درایو**) |
| `n` | فایل خالی جدید (انتخاب درایو) |
| **`Z`** | **فشرده‌سازی انتخاب به zip در پنل دیگر** |
| **`u`** | **استخراج آرشیو زیر کرسر به پنل دیگر** |
| **`x`** | **منوی zip/unzip** (tar.gz، پیش‌نمایش محتوا، استخراج همین‌جا) |
| `Q` | منوی سریع — همه‌ی دستورها یک‌جا (برای گوشی) |
| `F8` یا `Del` | حذف |
| `r` یا `Ctrl+R` | تغییر نام |
| `o` | منوی عملیات (فایل جدید، symlink، chmod، بازکردن با اپ) |
| `i` | جزئیات (مجوزها، اندازه، مالک، inode) |
| `a` یا `Ctrl+H` | نمایش/مخفی‌کردن فایل‌های مخفی |
| `z` یا `f` | فیلتر لیست (`*.jpg`) |
| `/` یا `Ctrl+G` | رفتن به مسیر (`~` و `$VARS` هم کار می‌کند) |
| `F2` | بازخوانی |
| `F3` یا `v` | نمایش فایل متنی |
| `F4` | ویرایش `config.json` در ادیتور |
| `F9` | منو (شامل Settings و Log و دستورهای پلاگین) |
| **`t`** | **تم بعدی** (۱۰ تم آماده، فوری عوض می‌شود) |
| **`S`** | **تنظیمات** — هر ۲۹ پارامتر از روی schema |
| **`G`** | **لاگ روزانه** (چه کارهایی امروز انجام شده) |
| `F10` یا `q` | خروج (و ذخیره‌ی نشست) |
| `Esc` | لغو انتقال در حال اجرا / پاک‌کردن انتخاب |

## نکته‌های اندروید

- **`/sdcard` و Permission denied** → یک بار `termux-setup-storage` و Allow.
- روی `/sdcard` عمل `chmod` و `chown` بی‌اثر است (ماهیت FUSE)؛ برنامه به‌جای خطا دادن،
  فقط هشدار می‌دهد و کار را ادامه می‌دهد.
- فایل‌های حذف‌شده به سطل بازیافت نمی‌روند؛ **حذف قطعی** است (تاییدیه دارد).
- اجرای برنامه به‌صورت پس‌زمینه در Termux Widget: فایل `termux-widget.sh` را ببینید.

## ساختار پروژه

```
twin-pane-explorer/
├── twinpane/
│   ├── fsops.py        # عملیات فایل خالص (بدون curses) - تست‌پذیر
│   ├── ui.py           # رابط curses دو-پنلی، دیالوگ‌ها، پروگرس‌بار
│   ├── config.py       # schema پارامترها + Config (JSON اتمیک) + CLI
│   ├── themes.py       # ۱۰ تم، نقش‌های رنگ، قاب‌ها، تم سفارشی از JSON
│   ├── logging_setup.py# لاگ روزانه‌ی فعالیت + لاگ خطا با traceback
│   ├── session.py      # ذخیره/بازیابی نشست (پوشه، کرسر، سورت، چیدمان)
│   └── plugins.py      # API قلاب/دستور/تنظیم برای افزونه‌ها
├── twinpane.py         # لانچر ساده  (python3 twinpane.py)
├── run.py              # همان کار برای اجرای مستقیم از این پوشه
├── install-termux.sh   # نصب در Termux + self-test
├── build_dist.py       # ساخت .deb + .zip در dist/
├── build-exe.bat       # ساخت TwinPane.exe روی ویندوز
├── TwinPane.bat        # لانچر ویندوز
├── termux-widget.sh    # شورتکات صفحه‌ی خانه
├── tests/              # ۱۳۱ تست (fsops، آرشیو، UI با pty، ماوس، هسته)
└── docs/               # راهنماها  (+ docs/preview/index.html)
```

## تست‌ها

```bash
python3 -m pytest tests/ -q      # ۱۳۱ تست
# تست‌های UI به pexpect و pyte نیاز دارند:  pip install pexpect pyte
```

تست‌های UI واقعاً برنامه را داخل یک pseudo-terminal اجرا می‌کنند، صفحه‌ی رندرشده را
می‌خوانند و کپی/انتقال/حذف را با کیبورد انجام می‌دهند.

## مجوز

MIT — راحت فورک کنید و کلید دلخواه‌تان را اضافه کنید.

## ماوس و لمس — چطور کار می‌کند

| حرکت | نتیجه |
|---|---|
| یک تپ/کلیک روی آیتم | آن آیتم انتخاب و پنل همان طرف فعال می‌شود |
| دابل‌تپ (دو تپ سریع) | پوشه باز می‌شود / فایل نمایش داده می‌شود |
| **کشیدن (drag)** از یک پنل به پنل دیگر | کپی آیتم به پنل مقصد، با یک تاییدیه |
| کشیدن عمودی داخل یک پنل (حالت گوشی) | اسکرول لیست |
| چرخ ماوس | اسکرول |
| کلیک راست | پرش به پنل دیگر |

برنامه هر دو پروتکل ماوس ترمینال را می‌خواند: **SGR** (`ESC [ < …`) که ترمینال‌های امروزی
می‌فرستند و **X10** (`ESC [ M …`) که بعضی تنظیمات قدیمی‌تر می‌فرستند. کدهای escape
دستی رمزگشایی می‌شوند، بنابراین کلیدهای جهت‌دار و F-key هم در حالت `CSI` و هم `SS3`
کار می‌کنند. اگر ترمینال شما ماوس را خراب کرد: `twinpane --no-mouse`.

## چیدمان: چپ/راست یا بالا/پایین

| حالت | چه وقت |
|---|---|
| `auto` (پیش‌فرض) | عرض ≥ ۶۴ ستون → دوصفحه کنار هم؛ باریک‌تر → یک پنل تمام‌عرض |
| `split` | همیشه چپ و راست |
| `stack` | همیشه یک پنل، با نوار سوئیچر بالای آن و `Tab` برای عوض‌کردن |

```bash
twinpane --layout stack      # برای گوشی در حالت عمودی
twinpane --layout split -l ~ -r /sdcard/Download
```
در حالت `stack` خط بالای پنل نشان می‌دهد در کدام پنل هستید (`▶` = فعال) و با `Tab` یا
تپ روی آن جابه‌جا می‌شوید.

## zip / unzip

```text
Z       انتخاب را در پنل مقابل به .zip تبدیل می‌کند
u       آرشیو زیر کرسر را در پنل مقابل باز می‌کند
x       منوی کامل: zip، tar.gz، استخراج همین‌جا، پیش‌نمایش محتوا
```

* پسوندهای پشتیبانی‌شده: `.zip` (و `.apk`/`.jar` که همان zip هستند)، `.tar`،
  `.tar.gz`/`.tgz`، `.tar.bz2`، `.tar.xz` — همه با کتابخانه‌ی استاندارد پایتون،
  **بدون نیاز به `pkg install zip`**.
* استخراج امن است: عضوهایی با `../` یا مسیر مطلق رد می‌شوند (محافظت zip-slip)،
  symlink‌هایی که به بیرون اشاره کنند ساخته نمی‌شوند، و دستگاه/fifo ساخته نمی‌شود.
* اگر مقصد وجود داشته باشد می‌پرسد «بازنویسی شود؟» و در حالت پیش‌فرض فایل‌های موجود را
  دست نمی‌زند. مقصد پیشنهادی هم همیشه یک نام یکتا است (`project (1)`).
* حجم/درصد/سرعت در همان نوار پیشرفت نمایش داده می‌شود و با `Esc` قابل لغو است.

## ساخت پوشه/فایل روی درایو مشخص

`F7` (پوشه) و `n` (فایل) اول یک منوی کوچک نشان می‌دهند:

```text
┌─ New folder ──────────────────────────────────┐
│  1. Left panel    /data/data/.../home          │
│  2. Right panel   /sdcard                      │
│  3. Other drive...                             │
└────────────────────────────────────────────────┘
```

گزینه‌ی ۳ هر مسیری را می‌پذیرد (`/sdcard/Download`, `$EXTERNAL_STORAGE/pics`, `~/x`).

## کلیدهای اضافه‌ی Termux (پیشنهادی برای گوشی)

`install-termux.sh` این را خودکار به `~/.termux/termux.properties` اضافه می‌کند؛ اگر
دستی می‌خواهید، فایل [`docs/termux.properties`](docs/termux.properties) را ببینید:

```properties
extra-keys = [ \
 ['ESC','TAB','/','-','HOME','UP','END','PGUP'], \
 ['CTRL','LEFT','DOWN','RIGHT','PGDN','F5','F6','F10'] \
]
```

بعد `termux-reload-settings` را اجرا کنید. این کار کلیدهای F5/F6/F10 و جهت‌دار را
در دسترس می‌گذارد؛ البته برنامه بدون آن‌ها هم با `c`/`m`/`u`/`Z`/`Q` کار می‌کند.

## لاگ روزانه — «امروز چه کار کردم؟»

هر روز یک فایل جدا نوشته می‌شود و **هر اقدام** با ساعت، هدف و جزئیات ثبت می‌شود:

```bash
ls ~/.local/state/twinpane/logs/
#   activity-2026-11-23.log    errors-2026-11-23.log
```

```
2026-11-23 06:58:00 INFO  --- session start ---  version=1.1.1 left=~ right=/sdcard theme=gruvbox
2026-11-23 06:58:01 INFO  cd             /sdcard/DCIM  from_=/sdcard
2026-11-23 06:58:04 INFO  copy           /sdcard/DCIM/photo.jpg  dest=~  files=1 bytes=890000 seconds=0.12
2026-11-23 06:58:09 INFO  archive        ~/photos.zip  sources=1 files=1 bytes=890000
2026-11-23 06:58:12 INFO  setting        ui.theme  value=midnight
2026-11-23 06:58:20 INFO  --- session end ---  reason=quit
```

- داخل برنامه: کلید **`G`** یا `F9 → Activity log` — فقط tail فایل نمایش داده می‌شود.
- فایل **`errors-…log`** جداست و **traceback کامل** دارد؛ یک باگ را می‌شود مستقیم فرستاد
  یا خودم بخوانم بدون اینکه لاگ روزمره شلوغ شود.
- هر لاگ روز حداکثر **۲ مگابایت**، پس گوشی هیچ‌وقت پر نمی‌شود؛ فایل‌های قدیمی‌تر از
  `logging.keep_days` (پیش‌فرض ۱۴ روز) خودکار پاک می‌شوند.
- هیچ‌وقت برنامه را از کار نمی‌اندازد: اگر پوشه‌ی لاگ قابل نوشتن نبود، لاگ خاموش
  می‌شود و برنامه ادامه می‌دهد (در Settings علتش را نشان می‌دهد).
- `logging.level = debug` تکتک کلیدها را هم ثبت می‌کند (برای پیدا کردن باگ).

## ادامه از همان‌جا (Resume)

برنامه هنگام خروج، و همچنین **با هر بار عوض کردن پوشه**، وضعیت را در
`~/.local/state/twinpane/session.json` ذخیره می‌کند:

```json
{ "active": 0, "layout": "auto",
  "left":  {"path": "/storage/emulated/0/DCIM", "cursor": "photo.jpg", "sort": "size", "reverse": true},
  "right": {"path": "/data/data/com.termux/files/home", "cursor": "notes.txt"} }
```

دفعه‌ی بعد که `twinpane` را باز کنید، **همان پوشه‌ها، همان کرسر، همان ترتیب مرتب‌سازی
و همان پنل فعال** برمی‌گردند و بالای صفحه `Resumed your last session` می‌بینید.

اولویت انتخاب پوشه‌ی شروع: **آرگومان خط فرمان (`-l`/`-r`) > نشست > `startup.left/right` > پیش‌فرض هوشمند.**
یعنی اگر صریح مسیر بدهید، حرف شما مقدم است. برای خاموش‌کردن:

```bash
python -m twinpane.config --set behaviour.restore_session=off
```
یا `S` → `behaviour.restore_session` → off.

## تم و ظاهر دلخواه

**`t`** = تم بعدی، **`S`** = صفحه‌ی تنظیمات (Enter = تغییر، Esc = برگشت).

| تم | حس و حال |
|---|---|
| `classic` | آبی/سفید کلاسیک NC — پیش‌فرض |
| `midnight` | سرمه‌ای تیره، مناسب شب |
| `amber` | کهربایی روی مشکی، شبیه ترمینال‌های قدیمی |
| `forest` | سبز جنگلی |
| `mono` | سیاه‌وسفید، بی‌رنگ (برای کنسول‌های ساده) |
| `solarized` | خنثی و کم‌خسته‌کننده |
| `paper` | روشن، برای زیر آفتاب |
| `dracula` | بنفش/صورتی |
| `nord` | یخی/آبی |
| `gruvbox` | خاکی و گرم |

علاوه بر رنگ، **قاب‌ها** هم عوض می‌شوند: `auto` (یونیکد اگر UTF-8 باشد)، `unicode`،
`double` (╔═╗)، `rounded` (╭─╮)، `ascii` (+-+ برای فونت‌های شکسته) و `none`.
`ui.density = compact` سرستون‌ها و فوتر پنل را حذف می‌کند تا در ۲۰ خط هم چیز بیشتری جا شود.

**تم سفارشی** — یک فایل JSON در `~/.config/twinpane/themes/` بگذارید؛ خودکار بارگذاری می‌شود:

```json
{ "name": "neon",
  "roles": { "panel": ["#e0e0ff", "#101020"],
             "current": ["black", "magenta"],
             "title": ["#00ffcc", "#101020", ["bold"]] } }
```

نقش‌ها: `panel`, `panel_border`, `panel_dim`, `current`, `title`, `dialog`, `input`,
`bar`, `title_screen`, `ok`, `error`, `warning`, `dim`, `link`, `header`, `status_bar`,
`selected_mark`. هر نقشی که ندهید از `classic` ارث می‌برد. رنگ‌ها را می‌شود نام
(`red`)، شماره‌ی ۲۵۶ رنگی (`208`)، هگز (`#ff8700`) یا `-1` نوشت.

## سیستم پارامتری و ماژولار

کل برنامه یک **schema** دارد: هر رفتار یک `Param` است با نوع، مقدار پیش‌فرض، گزینه‌ها،
راهنما و بخش. صفحه‌ی تنظیمات از همین schema ساخته می‌شود — یعنی **افزودن یک تنظیم
جدید، کد UI نمی‌خواهد**، فقط یک خط:

```python
_p("ui.compact_title", False, "bool", None, "Shorten path titles", "appearance")
```

فایل تنظیمات: `~/.config/twinpane/config.json` (روی ویندوز `%APPDATA%\twinpane\`).
مسیرها با `TWINPANE_CONFIG_DIR` / `TWINPANE_STATE_DIR` قابل تغییرند.

```bash
python -m twinpane.config --schema          # همه‌ی پارامترها
python -m twinpane.config --json            # مقادیر فعلی
python -m twinpane.config --set ui.theme=nord logging.level=debug
python -m twinpane.config --reset           # برگشت به پیش‌فرض
python -m twinpane.config --path            # فایل کجاست
```

**پلاگین** — یک فایل پایتون در `~/.config/twinpane/plugins/`. قلاب‌ها، دستورها و
تنظیمات خودش را اضافه می‌کند و در `F9` ظاهر می‌شود:

```python
# ~/.config/twinpane/plugins/upload.py
def register(api):
    @api.hook("copy")                     # startup quit navigate copy move delete
    def after_copy(sources, dest, result): # archive extract key theme_change config_change
        api.log.action("upload", dest, files=result.files)

    api.command("Sync to Nextcloud", lambda app: app.info("todo"))
```

یک پلاگین خراب **هرگز** برنامه را زمین نمی‌زند: خطا در `errors-*.log` ثبت و رد می‌شود.

## پکیج اندروید و ویندوز

### Termux (روش واقعی روی گوشی)

```bash
python build_dist.py                 # dist/twinpane_1.1.1_all.deb + zip + SHA256SUMS
pkg install ./dist/twinpane_1.1.1_all.deb
twinpane
```

`.deb` یک **پکیج بومی Termux** است (نه APK): بدون روت، بدون Android SDK، با
`Depends: python, ncurses-utils`، خودش را روی `$PREFIX/bin` نصب می‌کند و با
`pkg uninstall twinpane` کامل پاک می‌شود.

### آیکون روی صفحه‌ی خانه (بدون APK)

`pkg install termux-widget` (از F-Droid) و بعد:

```bash
# install-termux.sh خودش این کار را می‌کند
mkdir -p ~/.shortcuts && cp termux-widget.sh ~/.shortcuts/explorer.sh
chmod +x ~/.shortcuts/explorer.sh
```

حالا نگه‌داشتن انگشت روی صفحه‌ی خانه → Widgets → **Termux:Widget** → `explorer`.
یک تپ = باز شدن برنامه با پنل چپ `~` و راست `/sdcard` (یا `$HOME/storage/shared`).
این نزدیک‌ترین چیز به «اپ» است بدون نیاز به SDK اندروید.

### APK اندروید

**ساخته می‌شود و آماده است:** `twinpane-1.1.1-debug.apk` در
[Releases](https://github.com/HaadiTaba111/-/releases/tag/v1.1.1).

نسخه‌ی **1.1.1** دو نیمه دارد:

**۱) مرورگر فایل بومی — مستقل از Termux.** دکمه‌ی آبی روی صفحه‌ی اول.
`BrowserActivity` با `ListView` خالص (بدون AndroidX) پوشه‌های گوشی را لیست می‌کند:
`/sdcard`، Downloads، DCIM، Pictures، Music، Documents، `Android/data`.
فولدرها اول، اندازه و تاریخ، پیش‌نمایش فایل متنی، نصب `.apk`، حذف با long-press.
دسترسی: `READ_EXTERNAL_STORAGE` تا API 32، `requestLegacyExternalStorage` برای
API 29، و `MANAGE_EXTERNAL_STORAGE` برای API 30+ (یک تپ، و اگر ندهی نوار پایین
دقیقاً می‌گوید چه کار کنی — به‌جای لیست خالی).

**۲) راه‌انداز ترمکس.** دکمه‌ی سبز. `RUN_COMMAND` را از **Service** صدا می‌زند
(نسخه‌ی 1.1.0 اشتباهاً `startActivity` می‌زد، و ترمکس دستور را اجرا نمی‌کرد —
همین دلیل «هیچ اتفاقی نیفتاد» بود). payload را در `/sdcard/Download/TwinPane/`
می‌گذارد که ترمکس بتواند بخواندش (مسیر قبلی `/data/data/...` خصوصی بود).

**چرا TUI داخل APK اجرا نمی‌شود؟** یک برنامه‌ی curses به ترمینال نیاز دارد و
اندروید ترمینال ندارد. هر APKای که یک TUI را «واقعاً» داخل خودش اجرا کند، در عمل
یک شبیه‌ساز ترمینال ۵۰–۸۰ مگابایتی است. این APK ۲۳۵ کیلوبایت است و از ترمینال
واقعی Termux استفاده می‌کند — و برای وقتی که Termux نیست، مرورگر بومی خودش را دارد.

```bash
# ساخت مجدد (روی هر ماشینی با JDK 17 + Android SDK):
python build_dist.py && python build_apk.py

# یا در CI (ubuntu-latest خودش SDK دارد):
gh workflow run build-apk.yml --ref main
```

نصب: APK را باز کنید → دکمه‌ی آبی فوراً پوشه‌ها را نشان می‌دهد؛ برای TUI دکمه‌ی سبز.
برای امضای release، سه secret بگذارید: `ANDROID_KEYSTORE_BASE64`،
`ANDROID_KEY_ALIAS`، `ANDROID_KEY_PASSWORD`.

### ویندوز — `TwinPane.exe` (ساخته شد)

**دانلود:** `TwinPane.exe` (۸.۶MB) در [Releases](https://github.com/HaadiTaba111/-/releases/tag/v1.1.1).
دوبار کلیک = اجرا. کد قابل‌حمل است: `pwd`/`grp`/`termios` همه اختیاری شده‌اند و
`windows-curses` فقط برای رابط لازم است.

برای ساخت مجدد، دو راه:

```bat
:: روی ویندوز، کنار پوشه‌ی پروژه
build-exe.bat              :: یا  build-exe.bat --test
dist\TwinPane.exe
```

یا بدون ویندوز: تگ بزنید تا GitHub Actions روی `windows-latest` بسازد و به Release
بچسباند —

```bash
git tag v1.1.1 && git push origin v1.1.1
```

خروجی: `TwinPane.exe` + `TwinPane-windows.zip` در تب Actions/Releases.

## رفع اشکال

| نشانه | راه‌حل |
|---|---|
| کلیک/لمس جواب نمی‌دهد | `twinpane --no-mouse` و با کیبورد کار کنید؛ یا در Termux گزینه‌ی "Terminal emulator for Android" را چک کنید |
| متن ماوس را روی صفحه می‌بینم | همان `--no-mouse` |
| `Permission denied` روی `/sdcard` | `termux-setup-storage` و Allow |
| کادرها به‌هم می‌ریزند | `twinpane --ascii` |
| می‌خواهم ببینم چه کلیدهایی می‌رسد | `TWINPANE_DEBUG=/sdcard/tp.log twinpane` سپس فایل لاگ را ببینید |
