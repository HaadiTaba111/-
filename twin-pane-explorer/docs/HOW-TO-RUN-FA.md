# چطور از Twin-Pane Explorer استفاده کنم؟

سه راه. اولی را انتخاب کنید — ۹۹٪ آدم‌ها همین را می‌خواهند.

---

## ۳۰ ثانیه‌ای — با یک فایل (ساده‌ترین راه)

روی کامپیوتر، فایل `dist/twinpane-1.1.0-standalone.py` را بسازید:

```bash
python build_dist.py
```

یا اگر از قبل ساخته شده، همان یک فایل را بردارید و **با تلگرام / کابل USB / ایمیل**
به گوشی بفرستید. بعد در Termux:

```bash
# ۱) پایتون را نصب کنید (اگر ندارید)
pkg install python

# ۲) دسترسی به حافظه‌ی گوشی (یک بار، Allow بزنید)
termux-setup-storage

# ۳) همان یک فایل را اجرا کنید
cd ~/storage/downloads          # جایی که فایل را فرستادید
python twinpane-1.1.0-standalone.py
```

همین. برنامه باز می‌شود: پنل چپ خانه‌ی Termux، پنل راست `/sdcard`.

**می‌خواهید دستور `twinpane` هم داشته باشید؟**

```bash
python twinpane-1.1.0-standalone.py --install
twinpane          # از این به بعد از هر جا
```

این کار:
- برنامه را در `$PREFIX/lib/twinpane` می‌گذارد
- دستور `twinpane` را در `$PREFIX/bin` می‌سازد
- آیکون صفحه‌ی خانه را در `~/.shortcuts/explorer.sh` می‌گذارد

برای حذف: `python twinpane-1.1.0-standalone.py --uninstall`

> چرا این بهتر از APK است؟ همان تجربه، بدون ۳۰ مگابایت دانلود، بدون اجازه‌ی
> نصب APK، بدون آیکون‌های اضافه. و چون یک فایل پایتون است، روی هر تلفنی و هر
> نسخه‌ای از اندروید کار می‌کند.

---

## راه دوم — پکیج `.deb` (حرفه‌ای‌تر)

اگر Termux را دوست دارید و می‌خواهید `pkg install` کنید:

```bash
python build_dist.py                       # می‌سازد: dist/twinpane_1.1.0_all.deb
pkg install ./dist/twinpane_1.1.0_all.deb  # نصب (۲۰ ثانیه)
twinpane                                   # اجرا
pkg uninstall twinpane                     # حذف
```

تفاوتش با راه اول: در `pkg list-installed` دیده می‌شود و به‌صورت پکیج مدیریت
می‌شود. نتیجه‌ی نهایی یکی است.

---

## راه سوم — آیکون روی صفحه‌ی خانه (نزدیک‌ترین چیز به «اپ»)

```bash
pkg install termux-widget        # از F-Droid نصب کنید
# install-termux.sh خودش این کار را می‌کند:
mkdir -p ~/.shortcuts && cp termux-widget.sh ~/.shortcuts/explorer.sh
chmod +x ~/.shortcuts/explorer.sh
```

بعد: نگه‌داشتن انگشت روی صفحه‌ی خانه → **Widgets** → **Termux:Widget** → `explorer`

حالا یک آیکون دارید که با یک تپ برنامه را باز می‌کند.

---

## اگر روی کامپیوتر می‌خواهید (لینوکس / مک / ویندوز)

```bash
# لینوکس / مک
python3 -m pip install --user -r requirements-dev.txt   # نیاز نیست، فقط pty برای تست
python3 run.py

# ویندوز
pip install windows-curses
python run.py
```

یا در ویندوز فایل `TwinPane.exe` بسازید (روی ویندوز):

```bat
build-exe.bat
dist\TwinPane.exe
```

---

## سوال: چرا APK نمی‌سازید؟

سه دلیل، به ترتیب اهمیت:

**۱) APK برای برنامه‌های گرافیکی اندروید است، نه ترمینالی.**
Twin-Pane Explorer یک برنامه‌ی **curses** است — یعنی با ترمینال حرف می‌زند
(رنگ، مکان‌نما، کلیدهای F1..F10). اندروید اصلاً ترمینال ندارد. برای اجرای
curses داخل یک اپ اندرویدی باید یک **شبیه‌ساز ترمینال** کامل داخلش بگذارید یا
از برنامه‌ی دیگری (Termux) استفاده کنید. برای همین هیچ‌کس TUI را به APK تبدیل
نمی‌کند.

**۲) ساخت APK به ابزارهای گوگل نیاز دارد.**
به `aapt2` و `d8`/`R8` و `apksigner` (از Android SDK) و **NDK** (کامپایلر C
برای پایتون بومی) نیاز دارید. من JDK و aapt2 و apksigner را از PyPI گرفتم، اما
SDK و NDK از `dl.google.com` می‌آیند که در این محیط بلاک است. راه دیگری هم
(دانلود APK آماده از GitHub Releases برای استخراج `classes.dex`) امتحان کردم —
`release-assets.githubusercontent.com` هم بلاک است، حتی با توکن.

**۳) حتی اگر می‌ساختم، نتیجه بدتر بود.**
یک APK که فقط یک ترمینال شبیه‌سازی‌شده باز می‌کند ۵۰–۸۰ مگابایت می‌شود،
باید امضا شود (پس هر بار نصب دستی)، و روی اندروید ۱۲+ با محدودیت حافظه
دست‌وپنجه نرم می‌کند. یک فایل ۸۳ کیلوبایتی پایتون همین کار را می‌کند.

**اگر باز هم APK می‌خواهید:** کاری که واقعاً کار می‌کند این است:

1. ریپو را عمومی کنید (یا Fork بزنید)،
2. Actions را در Settings → Actions → General فعال کنید،
3. از تب Actions ورک‌فلوی `build-windows-exe.yml` را اجرا کنید (برای EXE)
   یا `build-termux-deb.yml` (برای پکیج).

اگر بخواهید ورک‌فلوی APK واقعی هم بنویسم، بگویید. آن یکی به
`python-for-android` + `kivy` نیاز دارد و یک لانچر می‌سازد که
`com.termux` را باز می‌کند — یعنی باز هم به Termux وابسته است.

---

## خلاصه در یک جدول

| چی می‌خواهید | چی بردارید | چطور |
|---|---|---|
| سریع، بدون دردسر | `twinpane-1.1.0-standalone.py` | `python twinpane-*-standalone.py` |
| دستور `twinpane` | همان فایل | `python twinpane-*-standalone.py --install` |
| مدیریت پکیج | `twinpane_1.1.0_all.deb` | `pkg install ./twinpane-*.deb` |
| آیکون صفحه‌ی خانه | `termux-widget.sh` | `cp` به `~/.shortcuts/` |
| فایل قابل‌حمل چندتایی | `twinpane-1.1.0.zip` | `unzip && ./run.py` |
| ویندوز | `TwinPane.exe` | `build-exe.bat` (روی ویندوز) |
