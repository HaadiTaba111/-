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

> پیش‌نمایش زنده (اسکرین‌شات‌های استخراج‌شده از خود برنامه): `docs/preview/index.html`

## چرا این؟

- **دوصفحه واقعی**: پنل چپ = خانه‌ی Termux، پنل راست = `/sdcard` (حافظه‌ی گوشی)
- **کپی / انتقال با یک کلید**: `F5` کپی، `F6` انتقال (انتقال بین فایل‌سیستم‌های مختلف
  خودکار به «کپی + حذف» تبدیل می‌شود، چون `/sdcard` روی اندروید یک FUSE mount است و rename بین‌شوتری جواب نمی‌دهد)
- **نوار پیشرفت واقعی** با سرعت، حجم، و **قابلیت لغو** (`Esc`)
- **مدیریت تداخل**: Overwrite / Skip / Rename / All / Keep-both
- **بدون وابستگی**: فقط پایتون ۳ و ماژول `curses` که در Termux هست
- **آشتی با صفحه‌کلید اندروید**: کلیدهای جهت‌دار در هر دو حالت terminfo (normal / application) کار می‌کنند
- **هر عملیاتی که `cp -r` و `mv` و `rm -rf` می‌دهند** با تاییدیه و گزارش خطای per-file

## نصب در Termux (سه خط)

```bash
pkg install python termux-tools      # اگر نصب نیست
termux-setup-storage                 # یک بار، برای دسترسی به /sdcard (Allow بزنید)
cd twin-pane-explorer && bash install-termux.sh
```

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
| `↑` `↓` `PgUp` `PgDn` `Home` `End` | حرکت |
| `Enter` | باز کردن پوشه / نمایش فایل |
| `Backspace` | رفتن به پوشه‌ی والد |
| `Tab` یا `←` `→` | تغییر پنل فعال |
| `Space` | انتخاب آیتم و رفتن به بعدی |
| `+` / `-` | انتخاب همه / حذف انتخاب |
| **`c` یا `F5`** | **کپی → پنل دیگر** |
| **`m` یا `F6`** | **انتقال → پنل دیگر** |
| `F7` | پوشه‌ی جدید |
| `F8` یا `Del` | حذف |
| `r` یا `Ctrl+R` | تغییر نام |
| `o` | منوی عملیات (فایل جدید، symlink، chmod، بازکردن با اپ) |
| `i` | جزئیات (مجوزها، اندازه، مالک، inode) |
| `a` یا `Ctrl+H` | نمایش/مخفی‌کردن فایل‌های مخفی |
| `z` یا `f` | فیلتر لیست (`*.jpg`) |
| `/` یا `Ctrl+G` | رفتن به مسیر (`~` و `$VARS` هم کار می‌کند) |
| `F2` | بازخوانی |
| `F3` یا `v` | نمایش فایل متنی |
| `F4` | ویرایش `~/.twinpanerc` |
| `F9` | منو |
| `F10` یا `q` | خروج |
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
│   ├── fsops.py      # عملیات فایل خالص (بدون curses) - تست‌پذیر
│   └── ui.py         # رابط curses دو-پنلی، دیالوگ‌ها، پروگرس‌بار
├── twinpane.py       # لانچر ساده  (python3 twinpane.py)
├── run.py            # همان کار برای اجرای مستقیم از این پوشه
├── install-termux.sh # نصب در Termux + self-test
├── termux-widget.sh  # شورتکات صفحه‌ی خانه
├── tests/            # 22 تست عملیات فایل + 10 تست رابط با pty واقعی
└── docs/             # راهنماها
```

## تست‌ها

```bash
python3 -m pytest tests/ -q      # ۳۲ تست
# تست‌های UI به pexpect و pyte نیاز دارند:  pip install pexpect pyte
```

تست‌های UI واقعاً برنامه را داخل یک pseudo-terminal اجرا می‌کنند، صفحه‌ی رندرشده را
می‌خوانند و کپی/انتقال/حذف را با کیبورد انجام می‌دهند.

## مجوز

MIT — راحت فورک کنید و کلید دلخواه‌تان را اضافه کنید.
