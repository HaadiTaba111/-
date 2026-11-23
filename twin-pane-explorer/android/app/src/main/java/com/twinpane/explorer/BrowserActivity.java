// A native, standalone file browser for the APK.
//
// This is deliberately dependency-free (no AndroidX, no RecyclerView) so it
// builds with plain `assembleDebug` and runs on API 21+. It exists because the
// launcher used to show a blank screen on devices where the Termux handshake
// failed - now the phone's storage is always browsable, no Termux needed.
//
// Storage access strategy (each Android generation differs):
//   * API 21-22 : /sdcard works after READ_EXTERNAL_STORAGE at install time.
//   * API 23-28 : same, plus a runtime permission request.
//   * API 29-32 : requestLegacyExternalStorage=true restores /sdcard paths.
//   * API 30+   : MANAGE_EXTERNAL_STORAGE ("All files access") if the user
//                 grants it; otherwise we fall back to the app's own directory
//                 and say so plainly instead of showing an empty list.
package com.twinpane.explorer;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.Settings;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.AdapterView;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.TextView;
import android.widget.Toast;

import java.io.File;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.Date;
import java.util.List;
import java.util.Locale;

public class BrowserActivity extends Activity {

    private static final int REQUEST_STORAGE = 11;

    private File current;
    private TextView pathLabel;
    private TextView statusLabel;
    private ListView list;
    private final List<File> entries = new ArrayList<>();
    private boolean warnedAboutStorage;
    private List<String> rows = new ArrayList<>();

    // ------------------------------------------------------------------ ui

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(buildUi());
        // Start where a phone user actually wants to be.
        File start = firstReadable(startCandidates());
        current = start;
        open(current);
    }

    private View buildUi() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.parseColor("#0b1015"));

        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setBackgroundColor(Color.parseColor("#131a22"));
        bar.setPadding(dp(8), dp(8), dp(8), dp(8));
        root.addView(bar);

        Button up = glyph("↑");
        up.setOnClickListener(v -> openParent());
        bar.addView(up);

        pathLabel = new TextView(this);
        pathLabel.setTypeface(Typeface.MONOSPACE);
        pathLabel.setTextColor(Color.parseColor("#9ecbff"));
        pathLabel.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f);
        pathLabel.setSingleLine(true);
        LinearLayout.LayoutParams pathParams = new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        pathParams.leftMargin = dp(8);
        bar.addView(pathLabel, pathParams);

        Button shortcuts = glyph("≡");
        shortcuts.setOnClickListener(v -> showShortcuts());
        bar.addView(shortcuts);
        root.addView(divider());

        list = new ListView(this);
        list.setBackgroundColor(Color.parseColor("#0b1015"));
        list.setDividerHeight(dp(1));
        list.setOnItemClickListener(new AdapterView.OnItemClickListener() {
            @Override
            public void onItemClick(AdapterView<?> parent, View view, int position, long id) {
                if (position < entries.size()) {
                    File picked = entries.get(position);
                    if (picked.isDirectory()) {
                        open(picked);
                    } else {
                        showFileInfo(picked);
                    }
                } else {
                    openParent();
                }
            }
        });
        list.setOnItemLongClickListener(new AdapterView.OnItemLongClickListener() {
            @Override
            public boolean onItemLongClick(AdapterView<?> parent, View view,
                                           int position, long id) {
                if (position < entries.size()) {
                    confirmDelete(entries.get(position));
                    return true;
                }
                return false;
            }
        });
        root.addView(list, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        statusLabel = new TextView(this);
        statusLabel.setTypeface(Typeface.MONOSPACE);
        statusLabel.setTextColor(Color.parseColor("#56606d"));
        statusLabel.setTextSize(TypedValue.COMPLEX_UNIT_SP, 10.5f);
        statusLabel.setPadding(dp(10), dp(6), dp(10), dp(6));
        statusLabel.setBackgroundColor(Color.parseColor("#131a22"));
        root.addView(statusLabel);
        return root;
    }

    private Button glyph(String text) {
        Button button = new Button(this);
        button.setText(text);
        button.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        button.setTextColor(Color.parseColor("#7ee787"));
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(Color.parseColor("#1d2733"));
        bg.setCornerRadius(dp(8));
        button.setBackground(bg);
        button.setLayoutParams(new LinearLayout.LayoutParams(dp(52), dp(44)));
        return button;
    }

    private View divider() {
        View view = new View(this);
        view.setBackgroundColor(Color.parseColor("#1d2733"));
        view.setLayoutParams(new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 1));
        return view;
    }

    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density);
    }

    // -------------------------------------------------------------- storage

    private File[] startCandidates() {
        return new File[]{
                Environment.getExternalStorageDirectory(),   // /sdcard
                new File("/storage/emulated/0"),
                Environment.getExternalStoragePublicDirectory(
                        Environment.DIRECTORY_DOWNLOADS),
                getExternalFilesDir(null) != null
                        ? getExternalFilesDir(null) : getFilesDir(),
                getFilesDir(),
        };
    }

    private File firstReadable(File[] candidates) {
        for (File candidate : candidates) {
            if (candidate != null && candidate.isDirectory() && candidate.canRead()) {
                return candidate;
            }
        }
        return getFilesDir();
    }

    /**
     * True when we can actually list the phone's shared storage. Distinguishes
     * "empty folder" from "blocked by Android", which is what made the old build
     * look broken.
     */
    private boolean hasSharedAccess() {
        File root = Environment.getExternalStorageDirectory();
        return root != null && root.isDirectory() && root.canRead()
                && root.list() != null;
    }

    private void requestStorage() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // "All files access" is the only way to browse /sdcard on API 30+.
            try {
                Intent intent = new Intent(
                        Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                        Uri.parse("package:" + getPackageName()));
                startActivity(intent);
                return;
            } catch (Exception ignored) {
                // some OEMs only expose the general list
            }
            try {
                startActivity(new Intent(
                        Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION));
                return;
            } catch (Exception ignored) {
                // fall through to the legacy request
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            requestPermissions(new String[]{
                    "android.permission.READ_EXTERNAL_STORAGE"}, REQUEST_STORAGE);
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions,
                                           int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQUEST_STORAGE) {
            open(current == null ? firstReadable(startCandidates()) : current);
        }
    }

    // ---------------------------------------------------------------- listing

    private void open(File folder) {
        if (folder == null) {
            return;
        }
        if (!folder.canRead()) {
            toast("Cannot read " + folder.getName());
            return;
        }
        current = folder;
        pathLabel.setText(shorten(folder.getAbsolutePath()));

        File[] children = folder.listFiles();
        rows = new ArrayList<>();
        entries.clear();
        if (children == null) {
            rows.add("  (cannot list this folder)");
        } else {
            List<File> sorted = new ArrayList<>(Arrays.asList(children));
            final boolean showHidden = false;
            // Collections.sort, not List.sort: the latter is API 24+ and this
            // app supports API 21.
            java.util.Collections.sort(sorted, new Comparator<File>() {
                @Override
                public int compare(File a, File b) {
                    if (a.isDirectory() != b.isDirectory()) {
                        return a.isDirectory() ? -1 : 1;      // folders first
                    }
                    return a.getName().compareToIgnoreCase(b.getName());
                }
            });
            SimpleDateFormat stamp = new SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US);
            for (File child : sorted) {
                if (!showHidden && child.getName().startsWith(".")) {
                    continue;
                }
                entries.add(child);
                String kind = child.isDirectory() ? "d" : "f";
                String size = child.isDirectory() ? "     -" : humanSize(child.length());
                String when = stamp.format(new Date(child.lastModified()));
                rows.add(" " + kind + "  " + pad(child.getName(), 22)
                        + pad(size, 8) + when + "\n     "
                        + (child.isDirectory()
                        ? countChildren(child) + " items"
                        : child.getName().toLowerCase(Locale.US).endsWith(".apk")
                        ? "installable app" : "tap for details"));
            }
            if (entries.isEmpty()) {
                rows.add("  (empty folder)");
            }
        }

        ArrayAdapter<String> adapter = new ArrayAdapter<String>(
                this, android.R.layout.simple_list_item_1, rows) {
            @Override
            public View getView(int position, View convertView, ViewGroup parent) {
                TextView view = (TextView) super.getView(position, convertView, parent);
                view.setTypeface(Typeface.MONOSPACE);
                view.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f);
                view.setTextColor(Color.parseColor(
                        position < entries.size() && entries.get(position).isDirectory()
                                ? "#9ecbff" : "#d7dee8"));
                view.setBackgroundColor(Color.parseColor("#0b1015"));
                view.setPadding(dp(6), dp(9), dp(6), dp(9));
                return view;
            }
        };
        list.setAdapter(adapter);

        if (hasSharedAccess()) {
            statusLabel.setText(" " + shortPath(folder) + " · "
                    + entries.size() + " items");
        } else {
            statusLabel.setText(" ⚠ no access to /sdcard — tap here to grant it");
            statusLabel.setOnClickListener(v -> requestStorage());
            if (!warnedAboutStorage) {
                warnedAboutStorage = true;
                Toast.makeText(this,
                        "Android is blocking /sdcard. Tap the bottom bar to allow it.",
                        Toast.LENGTH_LONG).show();
            }
        }
    }

    private String shortPath(File file) {
        String full = file.getAbsolutePath();
        String root = Environment.getExternalStorageDirectory().getAbsolutePath();
        return full.startsWith(root) ? full.substring(root.length()) : full;
    }

    private String shorten(String path) {
        return path.length() > 44 ? "…" + path.substring(path.length() - 43) : path;
    }

    private String pad(String text, int width) {
        if (text.length() > width - 1) {
            return text.substring(0, width - 2) + "… ";
        }
        StringBuilder builder = new StringBuilder(text);
        while (builder.length() < width) {
            builder.append(' ');
        }
        return builder.toString();
    }

    private String countChildren(File folder) {
        String[] names = folder.list();
        return names == null ? "?" : String.valueOf(names.length);
    }

    private String humanSize(long bytes) {
        if (bytes < 1024) {
            return bytes + " B";
        }
        String[] units = {"KB", "MB", "GB", "TB"};
        double value = bytes / 1024.0;
        int unit = 0;
        while (value >= 1024 && unit < units.length - 1) {
            value /= 1024;
            unit++;
        }
        return String.format(Locale.US, "%.1f %s", value, units[unit]);
    }

    private void openParent() {
        if (current == null) {
            return;
        }
        // Stop at the top of the shared storage instead of walking up into
        // /system; and never treat /sdcard/Download as if it were the root.
        if (isStorageRoot(current)) {
            showShortcuts();
            return;
        }
        File parent = current.getParentFile();
        if (parent == null || !parent.canRead()) {
            showShortcuts();
        } else {
            open(parent);
        }
    }

    private boolean isStorageRoot(File folder) {
        String path = folder.getAbsolutePath();
        if (folder.equals(Environment.getExternalStorageDirectory())) {
            return true;
        }
        return "/".equals(path)
                || "/storage".equals(path)
                || "/storage/emulated".equals(path)
                || "/storage/emulated/0".equals(path);
    }

    private void showShortcuts() {
        final List<File> places = new ArrayList<>();
        final List<String> names = new ArrayList<>();
        File shared = Environment.getExternalStorageDirectory();
        addPlace(places, names, "Phone storage  /sdcard", shared);
        addPlace(places, names, "Downloads",
                Environment.getExternalStoragePublicDirectory(
                        Environment.DIRECTORY_DOWNLOADS));
        addPlace(places, names, "Pictures",
                Environment.getExternalStoragePublicDirectory(
                        Environment.DIRECTORY_PICTURES));
        addPlace(places, names, "Music",
                Environment.getExternalStoragePublicDirectory(
                        Environment.DIRECTORY_MUSIC));
        addPlace(places, names, "DCIM (camera)",
                Environment.getExternalStoragePublicDirectory(
                        Environment.DIRECTORY_DCIM));
        addPlace(places, names, "Documents",
                Environment.getExternalStoragePublicDirectory(
                        Environment.DIRECTORY_DOCUMENTS));
        addPlace(places, names, "Android/data", new File(shared, "Android/data"));
        addPlace(places, names, "This app's files", getFilesDir());

        new AlertDialog.Builder(this)
                .setTitle("Jump to")
                .setItems(names.toArray(new String[0]),
                        new DialogInterface.OnClickListener() {
                            @Override
                            public void onClick(DialogInterface dialog, int which) {
                                open(places.get(which));
                            }
                        })
                .setPositiveButton("Grant full access", (d, w) -> requestStorage())
                .setNegativeButton("Close", null)
                .show();
    }

    private void addPlace(List<File> places, List<String> names,
                          String label, File folder) {
        if (folder != null) {
            places.add(folder);
            names.add(label + (folder.canRead() ? "" : "  (no access)"));
        }
    }

    private void showFileInfo(File file) {
        String extension = "";
        String name = file.getName();
        int dot = name.lastIndexOf('.');
        if (dot > 0) {
            extension = name.substring(dot + 1).toLowerCase(Locale.US);
        }
        String details = "size      : " + humanSize(file.length())
                + "\nmodified  : " + new SimpleDateFormat("yyyy-MM-dd HH:mm",
                Locale.US).format(new Date(file.lastModified()))
                + "\npath      : " + file.getAbsolutePath()
                + "\ntype      : " + (extension.isEmpty() ? "unknown" : extension);
        AlertDialog.Builder builder = new AlertDialog.Builder(this)
                .setTitle(name)
                .setMessage(details)
                .setNegativeButton("Close", null);
        if ("apk".equals(extension)) {
            builder.setPositiveButton("Open", (dialog, which) -> openWith(file));
        } else if ("txt".equals(extension) || "md".equals(extension)
                || "py".equals(extension) || "json".equals(extension)
                || "log".equals(extension) || "sh".equals(extension)) {
            builder.setPositiveButton("View", (dialog, which) -> previewText(file));
        }
        builder.show();
    }

    private void openWith(File file) {
        try {
            Intent intent = new Intent(Intent.ACTION_VIEW);
            intent.setDataAndType(Uri.fromFile(file), "application/vnd.android.package-archive");
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            startActivity(intent);
        } catch (Exception error) {
            toast("Cannot open this file: " + error.getMessage());
        }
    }

    /** Reads a small text file - handy to peek at a log from the phone itself. */
    private void previewText(File file) {
        if (file.length() > 256 * 1024) {
            toast("File too large to preview (" + humanSize(file.length()) + ")");
            return;
        }
        StringBuilder body = new StringBuilder();
        try (java.io.BufferedReader reader = new java.io.BufferedReader(
                new java.io.InputStreamReader(new java.io.FileInputStream(file)))) {
            String line;
            int count = 0;
            while ((line = reader.readLine()) != null && count < 400) {
                body.append(line).append('\n');
                count++;
            }
        } catch (Exception error) {
            toast("Cannot read: " + error.getMessage());
            return;
        }
        TextView view = new TextView(this);
        view.setTypeface(Typeface.MONOSPACE);
        view.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f);
        view.setTextColor(Color.parseColor("#d7dee8"));
        view.setBackgroundColor(Color.parseColor("#0b1015"));
        view.setPadding(dp(12), dp(12), dp(12), dp(12));
        view.setText(body.toString());
        android.widget.ScrollView scroll = new android.widget.ScrollView(this);
        scroll.addView(view);
        new AlertDialog.Builder(this)
                .setTitle(file.getName())
                .setView(scroll)
                .setNegativeButton("Close", null)
                .show();
    }

    private void confirmDelete(final File file) {
        new AlertDialog.Builder(this)
                .setTitle("Delete?")
                .setMessage(file.getName())
                .setPositiveButton("Delete", (dialog, which) -> {
                    if (delete(file)) {
                        toast("Deleted");
                        open(current);
                    } else {
                        toast("Could not delete — no write access");
                    }
                })
                .setNegativeButton("Cancel", null)
                .show();
    }

    private boolean delete(File file) {
        if (file.isDirectory()) {
            File[] children = file.listFiles();
            if (children != null) {
                for (File child : children) {
                    delete(child);
                }
            }
        }
        return file.delete();
    }

    private void toast(String message) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
    }
}
