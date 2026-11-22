# نصب و استفاده — Twin-Pane Explorer

## گام ۱: آماده‌سازی Termux

اگر Termux تازه نصب شده:

```bash
pkg update
pkg install python termux-tools
termux-setup-storage
```

`termux-setup-storage` یک پنجره‌ی مجوز اندروید باز می‌کند؛ **Allow** را بزنید تا
پوشه‌ی `/sdcard` (حافظه‌ی مشترک گوشی) قابل خواندن و نوشتن شود. بعد از این کار،
`~/storage/shared` هم به همان حافظه اشاره می‌کند.

بررسی سریع:

```bash
ls /sdcard          # باید محتویات گوشی را نشان دهد
python3 -c "import curses; print('curses ok')"
```

## گام ۲: گرفتن پروژه

ساده‌ترین راه: پوشه‌ی `twin-pane-explorer` را در خانه‌ی Termux کپی کنید.

اگر گیت دارید:

```bash
cd ~
git clone <repo-url> twin-pane-explorer
# در این مخزن، پوشه داخل خود ریپو است:
#   ~/-/twin-pane-explorer
```

## گام ۳: نصب

```bash
cd ~/twin-pane-explorer
bash install-termux.sh
```

این اسکریپت:

1. وجود `python3` و ماژول `curses` را چک می‌کند و اگر نبود نصبشان می‌کند.
2. یک لانچر به `$PREFIX/bin/twinpane` می‌سازد (به‌روزرسانی‌های کد را مستقیم می‌بیند).
3. دو alias به `~/.bashrc` اضافه می‌کند: `twin` و `explorer`.
4. یک **self-test** واقعی می‌زند (کپی و انتقال در پوشه‌ی موقت).

## گام ۴: اجرا

```bash
twin
```

- پنل چپ: خانه‌ی Termux (`/data/data/com.termux/files/home`)
- پنل راست: `/sdcard` (اگر وجود نداشت، پوشه‌ی جاری)

با مسیرهای دلخواه:

```bash
twinpane -l ~/Download -r /sdcard/Download
twinpane -l /sdcard/DCIM/Camera -r ~/pics
twinpane --ascii        # برای ترمینال‌های قدیمی که کادر یونیکد نمی‌کشند
```

## گام ۵: اولین انتقال

مثلاً می‌خواهید فایل `notes.txt` را از خانه‌ی ترموکس به `/sdcard` ببرید:

1. در پنل چپ با `↑`/`↓` روی `notes.txt` بروید.
2. `Space` بزنید (یک بولت کنارش می‌آید و کرسر پایین می‌رود).
3. `F5` (یا `c`) بزنید → پنجره‌ی تایید باز می‌شود که مقصد را نشان می‌دهد.
4. `y` بزنید. نوار پیشرفت و سرعت را می‌بینید؛ می‌توانید با `Esc` وسط کار لغو کنید.
5. در پنل راست `F2` بزنید تا `notes.txt` را ببینید.

برای انتقال (کپی + حذف مبدأ) همان مراحل با **`F6`** (یا `m`).

> **نکته‌ی فنی:** `/sdcard` روی اندروید یک FUSE mount است؛ `os.rename` بین خانه‌ی
> ترموکس و `/sdcard` خطای `EXDEV` می‌دهد. برنامه این را تشخیص می‌دهد و خودکار
> به «کپی + حذف مبدأ» تبدیل می‌کند، فقط اگر کپی بدون خطا تمام شود حذف انجام می‌شود.

## اگر کلیدهای F1..F10 روی کیبورد گوشی نیستند

از کلیدهای جایگزین استفاده کنید: `c` کپی، `m` انتقال، `r` تغییرنام، `F8`=کلید `Del`
(یا از منوی `o` استفاده کنید). در Termux هم می‌توانید
`~/.termux/termux.properties` را باز کنید و یک ردیف **extra-keys** با `F5 F6` بسازید:

```properties
extra-keys = [['ESC','/','-','HOME','UP','END','PGUP'],['TAB','CTRL','ALT','LEFT','DOWN','RIGHT','PGDN']]
```

## رفع اشکال

| نشانه | علت / راه‌حل |
|---|---|
| `Permission denied` روی `/sdcard` | `termux-setup-storage` را یک بار اجرا و Allow کنید |
| «Terminal too small» | ترمینال را بزرگ‌تر کنید (حداقل ۳۴×۱۰) یا فونت را کوچک کنید |
| کادرها به‌هم می‌ریزند | `twinpane --ascii` یا `export TWINPANE_ASCII=1` |
| کلیدهای جهت‌دار کار نمی‌کنند | نسخه‌ی جدید همین پروژه این را حل کرده (decoder دستی escape)؛ اگر باز هم بود `echo $TERM` را چک کنید |
| فونت مربع‌ها را نشان نمی‌دهد | در Termux فونت را به یکی مثل **JetBrains Mono** تغییر دهید یا `--ascii` بزنید |
| برنامه با صفحه‌کلید خارجی | مستقیم کار می‌کند؛ Tab/Arrows/F-keys همه تست شده‌اند |
