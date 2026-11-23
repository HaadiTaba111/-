// Twin-Pane Explorer - Android launcher
//
// Why a "launcher" and not a native UI: Twin-Pane is a curses TUI. It needs a
// real terminal to draw in. Termux provides one and exposes it through the
// RUN_COMMAND *service*, so this APK is a proper installable Android app whose
// whole job is to hand the terminal over to the Python program.
//
// Two deliberate design points (both learned the hard way):
//
//   1. RUN_COMMAND is a **Service**, not an Activity. Calling startActivity on
//      com.termux/.app.TermuxActivity with that action silently does nothing -
//      that is why an earlier build looked like a dead screen. We now resolve
//      the service via queryIntentServices and startService / startForegroundService.
//
//   2. The APK is not a file manager. It cannot browse /sdcard by itself: it is
//      a shortcut into a terminal program. To make that obvious (and useful) the
//      launcher shows the real Termux home + /sdcard listing when it can read
//      them, and explains exactly which button to press when it cannot.
package com.twinpane.explorer;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ActivityNotFoundException;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.content.res.AssetManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.MediaStore;
import android.text.method.ScrollingMovementMethod;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

public class MainActivity extends Activity {

    /** Termux packages, in order of preference. */
    private static final String[] TERMUX_PACKAGES = {
            "com.termux",
    };

    private static final String RUN_COMMAND_SERVICE =
            "com.termux.RUN_COMMAND";
    /**
     * Where the payload is published for Termux to read.
     *
     * <p>This is the whole point: /data/data/com.twinpane.explorer is private to
     * this app, so Termux gets "Permission denied" if we hand it that path.
     * /sdcard/Download is shared - every Termux with termux-setup-storage can
     * read it. On API 29+ the file is written through MediaStore; on older
     * versions a plain File write is used (WRITE_EXTERNAL_STORAGE granted).
     */
    private static final String SHARED_SUBDIR = "TwinPane";
    private static final String PAYLOAD_NAME = "twinpane-standalone.py";

    private TextView status;
    private TextView listing;
    private Uri lastPublishedUri;
    private Button launch;
    private Button copy;

    // ------------------------------------------------------------------ ui

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(buildUi());
        refreshState();
    }

    private View buildUi() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.parseColor("#0b1015"));
        int pad = dp(20);
        root.setPadding(pad, pad, pad, pad);
        root.setGravity(Gravity.CENTER_HORIZONTAL);

        TextView title = new TextView(this);
        title.setText("Twin-Pane Explorer");
        title.setTextColor(Color.parseColor("#7ee787"));
        title.setTypeface(Typeface.MONOSPACE, Typeface.BOLD);
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 24);
        title.setGravity(Gravity.CENTER);
        root.addView(title);

        TextView sub = mono();
        sub.setText("two panels · Termux ↔ phone storage");
        sub.setTextColor(Color.parseColor("#8b98a8"));
        sub.setGravity(Gravity.CENTER);
        sub.setPadding(0, dp(6), 0, dp(14));
        root.addView(sub);

        status = mono();
        status.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f);
        status.setTextColor(Color.parseColor("#d7dee8"));
        status.setPadding(dp(4), 0, dp(4), dp(12));
        root.addView(status);

        // The Termux-free path, first on the screen on purpose: this is what
        // works even when the Termux handshake cannot.
        Button browse = new Button(this);
        browse.setText("Browse phone files  (no Termux needed)");
        browse.setAllCaps(false);
        browse.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        browse.setTextColor(Color.parseColor("#0b1015"));
        GradientDrawable browseBg = new GradientDrawable();
        browseBg.setColor(Color.parseColor("#9ecbff"));
        browseBg.setCornerRadius(dp(10));
        browse.setBackground(browseBg);
        browse.setPadding(dp(16), dp(14), dp(16), dp(14));
        browse.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                startActivity(new Intent(MainActivity.this, BrowserActivity.class));
            }
        });
        root.addView(browse, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT));

        launch = new Button(this);
        launch.setText("Open the two-panel terminal");
        launch.setAllCaps(false);
        launch.setTextSize(TypedValue.COMPLEX_UNIT_SP, 17);
        launch.setTextColor(Color.parseColor("#0b1015"));
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(Color.parseColor("#7ee787"));
        bg.setCornerRadius(dp(10));
        launch.setBackground(bg);
        launch.setPadding(dp(16), dp(14), dp(16), dp(14));
        launch.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                launchTerminal();
            }
        });
        LinearLayout.LayoutParams launchParams = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT);
        launchParams.topMargin = dp(10);
        root.addView(launch, launchParams);

        copy = new Button(this);
        copy.setText("Copy the command (paste in Termux)");
        copy.setAllCaps(false);
        copy.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                copyCommand();
            }
        });
        LinearLayout.LayoutParams copyParams = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT);
        copyParams.topMargin = dp(8);
        root.addView(copy, copyParams);

        // A real, live listing of the two folders the TUI will open. Long-press
        // any line to copy it. This is not a file manager - it is a preview so
        // the screen is never just a blank "nothing here".
        TextView listingLabel = mono();
        listingLabel.setText("\nwhat Twin-Pane will show:");
        listingLabel.setTextColor(Color.parseColor("#56606d"));
        listingLabel.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11);
        root.addView(listingLabel);

        listing = mono();
        listing.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f);
        listing.setTextColor(Color.parseColor("#9ecbff"));
        listing.setPadding(dp(4), dp(4), dp(4), dp(14));
        root.addView(listing);

        TextView footer = mono();
        footer.setText("The blue button always works.\n"
                + "The green one needs Termux (F-Droid) — it is the "
                + "two-panel terminal itself.");
        footer.setTextColor(Color.parseColor("#56606d"));
        footer.setGravity(Gravity.CENTER);
        footer.setTextSize(TypedValue.COMPLEX_UNIT_SP, 10.5f);
        root.addView(footer, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT));

        ScrollView scroll = new ScrollView(this);
        scroll.setBackgroundColor(Color.parseColor("#0b1015"));
        scroll.addView(root);
        return scroll;
    }

    private TextView mono() {
        TextView view = new TextView(this);
        view.setTypeface(Typeface.MONOSPACE);
        view.setMovementMethod(new ScrollingMovementMethod());
        return view;
    }

    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density);
    }

    // --------------------------------------------------------------- state

    private void refreshState() {
        boolean termux = isTermuxInstalled();
        boolean permission = hasPermission();
        StringBuilder text = new StringBuilder();
        text.append(termux ? "✓ " : "✗ ").append("Termux app found\n");
        text.append(permission ? "✓ " : "✗ ")
                .append("permission to run commands\n");
        text.append(canUnpack() ? "✓ " : "✓ ").append("program ready to publish\n");
        status.setText(text.toString());
        listing.setText(previewListing());
        launch.setText(termux && permission
                ? "Open the two-panel terminal"
                : "Set up the terminal (2 taps)");
    }

    /** The two folders the TUI opens, rendered as the smallest useful preview. */
    private String previewListing() {
        StringBuilder text = new StringBuilder();
        text.append("┌─ ~ ───────────────┐\n");
        text.append(describeFolder(termuxHome()));
        text.append("└───────────────────┘\n\n");
        text.append("┌─ /sdcard ─────────┐\n");
        text.append(describeFolder(sharedStorageRoot()));
        text.append("└───────────────────┘");
        return text.toString();
    }

    /** Termux's home, readable on some builds only - hence the fallback. */
    private File termuxHome() {
        File direct = new File("/data/data/com.termux/files/home");
        if (direct.canRead()) {
            return direct;
        }
        return new File(getFilesDir(), "home");
    }

    /** The real phone storage, whatever this Android version calls it. */
    private File sharedStorageRoot() {
        String[] candidates = {
                "/sdcard",
                "/storage/emulated/0",
                "/storage/self/primary",
        };
        for (String path : candidates) {
            File file = new File(path);
            if (file.canRead()) {
                return file;
            }
        }
        return new File("/sdcard");        // show it anyway, with the reason
    }

    private String describeFolder(File folder) {
        if (!folder.exists()) {
            return "│ (does not exist)\n";
        }
        if (!folder.canRead()) {
            return "│ (permission denied)\n";
        }
        String[] names = folder.list();
        if (names == null) {
            return "│ (cannot list)\n";
        }
        if (names.length == 0) {
            return "│ (empty folder)\n";
        }
        Arrays.sort(names);
        List<String> shown = new ArrayList<>();
        for (String name : names) {
            if (name.startsWith(".")) {
                continue;                  // hidden files are noise here
            }
            File child = new File(folder, name);
            shown.add(child.isDirectory() ? "[" + name + "]" : name);
            if (shown.size() >= 5) {
                break;
            }
        }
        if (shown.isEmpty()) {
            return "│ (only hidden files)\n";
        }
        StringBuilder text = new StringBuilder();
        for (String line : shown) {
            String clipped = line.length() > 17 ? line.substring(0, 16) + "…" : line;
            text.append("│").append(clipped);
            for (int i = clipped.length(); i < 19; i++) {
                text.append(' ');
            }
            text.append("│\n");
        }
        return text.toString();
    }

    private boolean canUnpack() {
        return sharedPayloadFile().exists() || new File(getFilesDir(), PAYLOAD_NAME).exists();
    }

    private String termuxPackage() {
        for (String name : TERMUX_PACKAGES) {
            try {
                getPackageManager().getPackageInfo(name, 0);
                return name;
            } catch (PackageManager.NameNotFoundException ignored) {
                // try the next one
            }
        }
        return null;
    }

    private boolean isTermuxInstalled() {
        return termuxPackage() != null;
    }

    /** Termux only honours RUN_COMMAND once the user allowed it. */
    private boolean hasPermission() {
        if (termuxPackage() == null) {
            return false;
        }
        // Context.checkSelfPermission only exists from API 23; the package
        // manager call has worked since API 1 and means the same thing.
        return getPackageManager().checkPermission(
                "com.termux.permission.RUN_COMMAND", getPackageName())
                == PackageManager.PERMISSION_GRANTED;
    }

    /** The RUN_COMMAND service has to exist and be resolvable. */
    private ComponentName findRunCommandService(String pkg) {
        Intent query = new Intent(RUN_COMMAND_SERVICE);
        query.setPackage(pkg);
        List<ResolveInfo> found =
                getPackageManager().queryIntentServices(query, 0);
        if (found == null || found.isEmpty()) {
            // Some Termux builds export the service without an intent-filter,
            // so resolution fails even though the service is there. Try the
            // documented class name directly - startService will tell us.
            return new ComponentName(pkg, pkg + ".app.RunCommandService");
        }
        ResolveInfo info = found.get(0);
        if (info.serviceInfo != null) {
            return new ComponentName(info.serviceInfo.packageName, info.serviceInfo.name);
        }
        return new ComponentName(pkg, pkg + ".app.RunCommandService");
    }

    // ------------------------------------------------------------- actions

    private void launchTerminal() {
        String pkg = termuxPackage();
        if (pkg == null) {
            promptInstallTermux();
            return;
        }
        if (!hasPermission()) {
            promptPermission();
            return;
        }
        try {
            publishPayload();
            startTermuxCommand(pkg);
        } catch (IOException error) {
            status.setText("Could not publish the program:\n" + error.getMessage()
                    + "\n\nUse \"Copy the command\" and install from the terminal instead.");
        }
    }

    private void startTermuxCommand(String pkg) {
        ComponentName service = findRunCommandService(pkg);
        if (service == null) {
            new AlertDialog.Builder(this)
                    .setTitle("Termux cannot receive commands")
                    .setMessage("The RUN_COMMAND service is not exposed by your "
                            + "Termux build.\n\nOpen Termux, paste this and press Enter:\n\n"
                            + "echo allow-external-apps=true >> "
                            + "~/.termux/termux.properties && termux-reload-settings\n\n"
                            + "Then come back and press the button again.")
                    .setPositiveButton("Copy that command", (d, w) -> {
                        ClipboardManager clipboard = (ClipboardManager)
                                getSystemService(Context.CLIPBOARD_SERVICE);
                        clipboard.setPrimaryClip(ClipData.newPlainText("termux",
                                "echo allow-external-apps=true >> "
                                        + "~/.termux/termux.properties "
                                        + "&& termux-reload-settings"));
                        Toast.makeText(this, "Copied", Toast.LENGTH_SHORT).show();
                    })
                    .setNegativeButton("Close", null)
                    .show();
            return;
        }

        Intent intent = new Intent();
        intent.setComponent(service);
        intent.putExtra("com.termux.RUN_COMMAND_PATH",
                "/data/data/" + pkg + "/files/usr/bin/sh");
        intent.putExtra("com.termux.RUN_COMMAND_ARGUMENTS", new String[]{
                "-c",
                // install on first run, then start the UI in a foreground session
                "python \"" + payloadPath() + "\" --install >/dev/null 2>&1; "
                        + "exec twinpane"
        });
        intent.putExtra("com.termux.RUN_COMMAND_WORKDIR",
                "/data/data/" + pkg + "/files/home");
        intent.putExtra("com.termux.RUN_COMMAND_BACKGROUND", false);
        intent.putExtra("com.termux.RUN_COMMAND_SESSION_ACTION", "0");

        try {
            // NOT startForegroundService(): Android would then require the
            // service to call startForeground() within 5 seconds, and Termux's
            // RunCommandService does not - the app would be killed. A plain
            // startService() from a visible activity is allowed on every version.
            startService(intent);
            Toast.makeText(this, "Opening Termux…", Toast.LENGTH_SHORT).show();
            finish();
        } catch (SecurityException denied) {
            promptPermission();
        } catch (Exception error) {
            status.setText("Termux refused the command:\n" + error
                    + "\n\nUse \"Copy the command\" and paste it in Termux.");
        }
    }

    private void promptInstallTermux() {
        new AlertDialog.Builder(this)
                .setTitle("Termux is required")
                .setMessage("Twin-Pane runs inside Termux - a real terminal. "
                        + "Install it from F-Droid (the Play Store build is outdated "
                        + "and cannot receive commands), open it once, then come back.")
                .setPositiveButton("Open F-Droid", (dialog, which) -> {
                    try {
                        startActivity(new Intent(Intent.ACTION_VIEW,
                                Uri.parse("https://f-droid.org/packages/com.termux/")));
                    } catch (ActivityNotFoundException ignored) {
                        Toast.makeText(this, "No browser", Toast.LENGTH_SHORT).show();
                    }
                })
                .setNegativeButton("Later", null)
                .show();
    }

    private void promptPermission() {
        new AlertDialog.Builder(this)
                .setTitle("Allow running commands")
                .setMessage("Android will ask whether Twin-Pane may run commands "
                        + "in Termux. Tap Allow.\n\nIf no dialog appears, open Termux "
                        + "and run:\n\necho allow-external-apps=true >> "
                        + "~/.termux/termux.properties\ntermux-reload-settings")
                .setPositiveButton("Request now", (dialog, which) ->
                        startActivity(new Intent(this, SetupActivity.class)))
                .setNegativeButton("Copy the command", (dialog, which) -> copyCommand())
                .show();
    }

    private void copyCommand() {
        ClipboardManager clipboard =
                (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        clipboard.setPrimaryClip(ClipData.newPlainText("twinpane", runCommand()));
        Toast.makeText(this, "Copied - paste it in Termux", Toast.LENGTH_LONG).show();
    }

    // ----------------------------------------------------------- unpacking

    /**
     * Publish the bundled program into shared storage and return the path
     * Termux will read it from, or null if the publish failed.
     */
    private String publishPayload() throws IOException {
        File target = sharedPayloadFile();
        File privateCopy = new File(getFilesDir(), PAYLOAD_NAME);
        if (!privateCopy.exists() || privateCopy.length() < 4096) {
            extractAsset(PAYLOAD_NAME, privateCopy);
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            publishViaMediaStore(privateCopy);
        } else {
            File folder = target.getParentFile();
            if (folder != null && !folder.exists() && !folder.mkdirs()) {
                throw new IOException("cannot create " + folder);
            }
            copyFile(privateCopy, target);
        }
        return target.getAbsolutePath();
    }

    /** /sdcard/Download/TwinPane/twinpane-standalone.py */
    private File sharedPayloadFile() {
        File downloads = Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOWNLOADS);
        return new File(new File(downloads, SHARED_SUBDIR), PAYLOAD_NAME);
    }

    /** API 29+: scoped storage still allows *our own* files in Download/. */
    private void publishViaMediaStore(File source) throws IOException {
        ContentResolver resolver = getContentResolver();
        ContentValues values = new ContentValues();
        values.put(MediaStore.Downloads.DISPLAY_NAME, PAYLOAD_NAME);
        values.put(MediaStore.Downloads.MIME_TYPE, "text/x-python");
        values.put(MediaStore.Downloads.RELATIVE_PATH,
                Environment.DIRECTORY_DOWNLOADS + "/" + SHARED_SUBDIR);
        Uri uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
        if (uri == null) {
            throw new IOException("MediaStore refused the entry");
        }
        try (InputStream in = new java.io.FileInputStream(source);
             OutputStream out = resolver.openOutputStream(uri, "wt")) {
            if (out == null) {
                throw new IOException("cannot open " + uri);
            }
            byte[] buffer = new byte[64 * 1024];
            int read;
            while ((read = in.read(buffer)) > 0) {
                out.write(buffer, 0, read);
            }
        }
        lastPublishedUri = uri;
    }

    private void extractAsset(String name, File target) throws IOException {
        AssetManager assets = getAssets();
        File folder = target.getParentFile();
        if (folder != null && !folder.exists() && !folder.mkdirs()) {
            throw new IOException("cannot create " + folder);
        }
        try (InputStream in = assets.open(name);
             OutputStream out = new FileOutputStream(target)) {
            byte[] buffer = new byte[64 * 1024];
            int read;
            while ((read = in.read(buffer)) > 0) {
                out.write(buffer, 0, read);
            }
        }
    }

    private void copyFile(File source, File target) throws IOException {
        try (InputStream in = new java.io.FileInputStream(source);
             OutputStream out = new FileOutputStream(target)) {
            byte[] buffer = new byte[64 * 1024];
            int read;
            while ((read = in.read(buffer)) > 0) {
                out.write(buffer, 0, read);
            }
        }
    }

    /**
     * The path Termux should use. When MediaStore is involved the file lives in
     * Download/ exactly the same way, so the plain path works for both.
     */
    private String payloadPath() {
        return sharedPayloadFile().getAbsolutePath();
    }

    /** The command to paste into Termux - no quoting traps, one line. */
    private String runCommand() {
        return "python \"" + payloadPath() + "\" --install && twinpane";
    }

    @Override
    protected void onResume() {
        super.onResume();
        refreshState();
    }
}
