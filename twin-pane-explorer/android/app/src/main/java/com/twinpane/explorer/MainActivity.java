// Twin-Pane Explorer - Android launcher
//
// Why a "launcher" and not a native UI: Twin-Pane is a curses TUI. It needs a
// real terminal to draw in. Termux provides one and exposes it through the
// RUN_COMMAND intent, so this APK is a proper installable Android app whose
// whole job is to hand the terminal over to the Python program.
//
// Flow:
//   1. find a Termux package (com.termux or a fork such as the izzysoft build)
//   2. make sure the user granted "run commands in Termux" (ALLOW_EXTERNAL_APPS)
//   3. bootstrap python/termux-setup-storage once, install the bundled program
//   4. launch the TUI in a foreground session
package com.twinpane.explorer;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ActivityNotFoundException;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.res.AssetManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
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

public class MainActivity extends Activity {

    /** Termux packages, in order of preference. */
    private static final String[] TERMUX_PACKAGES = {
            "com.termux",
            "com.termux.api",
    };

    private static final String TERMUX_RUN_COMMAND =
            "com.termux.RUN_COMMAND";
    private static final String EXTRA_PATH = "com.termux.RUN_COMMAND_PATH";
    private static final String EXTRA_ARGUMENTS = "com.termux.RUN_COMMAND_ARGUMENTS";
    private static final String EXTRA_WORKDIR = "com.termux.RUN_COMMAND_WORKDIR";
    private static final String EXTRA_BACKGROUND = "com.termux.RUN_COMMAND_BACKGROUND";
    private static final String EXTRA_SESSION_ACTION = "com.termux.RUN_COMMAND_SESSION_ACTION";
    private static final String EXTRA_COMMAND_LABEL = "com.termux.RUN_COMMAND_COMMAND_LABEL";
    private static final String EXTRA_COMMAND_DESCRIPTION =
            "com.termux.RUN_COMMAND_COMMAND_DESCRIPTION";
    private static final String EXTRA_COMMAND_HELP = "com.termux.RUN_COMMAND_COMMAND_HELP";

    private static final int REQUEST_INSTALL = 41;

    private TextView status;
    private Button launch;
    private Button copy;

    // ------------------------------------------------------------------ ui

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(buildUi());
        refreshState();
        // First run: go straight to the terminal if everything is ready.
        if (isTermuxInstalled() && hasPermission()) {
            status.postDelayed(new Runnable() {
                @Override
                public void run() {
                    launchTerminal();
                }
            }, 300);
        }
    }

    private View buildUi() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.parseColor("#0b1015"));
        int pad = dp(22);
        root.setPadding(pad, pad, pad, pad);
        root.setGravity(Gravity.CENTER_HORIZONTAL);

        TextView title = new TextView(this);
        title.setText("Twin-Pane Explorer");
        title.setTextColor(Color.parseColor("#7ee787"));
        title.setTypeface(Typeface.MONOSPACE, Typeface.BOLD);
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 25);
        title.setGravity(Gravity.CENTER);
        root.addView(title);

        TextView sub = mono();
        sub.setText("two panels · Termux ↔ phone storage");
        sub.setTextColor(Color.parseColor("#8b98a8"));
        sub.setGravity(Gravity.CENTER);
        sub.setPadding(0, dp(6), 0, dp(18));
        root.addView(sub);

        // a tiny box-drawing "screenshot" so the app looks like what it is
        TextView art = mono();
        art.setTextColor(Color.parseColor("#9ecbff"));
        art.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f);
        art.setText("┌─ ~ ────────────┐┌─ /sdcard ──────┐\n"
                + "│ [Download]     ││ [DCIM]         │\n"
                + "│ [projects]     ││ [Download]     │\n"
                + "│• notes.txt     ││  photo.jpg     │\n"
                + "│  setup.sh      ││                │\n"
                + "└────────────────┘└────────────────┘");
        art.setPadding(dp(4), 0, dp(4), dp(20));
        root.addView(art);

        status = mono();
        status.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f);
        status.setTextColor(Color.parseColor("#d7dee8"));
        status.setPadding(0, 0, 0, dp(16));
        status.setGravity(Gravity.START);
        root.addView(status);

        launch = new Button(this);
        launch.setText("Open Twin-Pane");
        launch.setAllCaps(false);
        launch.setTextSize(TypedValue.COMPLEX_UNIT_SP, 17);
        launch.setTextColor(Color.parseColor("#0b1015"));
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(Color.parseColor("#7ee787"));
        bg.setCornerRadius(dp(10));
        launch.setBackground(bg);
        launch.setPadding(dp(18), dp(14), dp(18), dp(14));
        launch.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                launchTerminal();
            }
        });
        root.addView(launch, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT));

        copy = new Button(this);
        copy.setText("Copy the run command");
        copy.setAllCaps(false);
        copy.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                ClipboardManager clipboard =
                        (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
                clipboard.setPrimaryClip(ClipData.newPlainText("twinpane", runCommand()));
                Toast.makeText(MainActivity.this, "Copied", Toast.LENGTH_SHORT).show();
            }
        });
        LinearLayout.LayoutParams copyParams = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT);
        copyParams.topMargin = dp(10);
        root.addView(copy, copyParams);

        ScrollView scroll = new ScrollView(this);
        scroll.setBackgroundColor(Color.parseColor("#0b1015"));
        scroll.addView(root);
        TextView footer = mono();
        footer.setText("\nNeeds the Termux app (F-Droid).\nThis APK is just the launcher.");
        footer.setTextColor(Color.parseColor("#56606d"));
        footer.setGravity(Gravity.CENTER);
        footer.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11);
        root.addView(footer, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT));
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
        text.append(termux ? "\u2713" : "\u2717").append(" Termux found\n");
        text.append(permission ? "\u2713" : "\u2717")
                .append(" permission to run commands\n");
        status.setText(text.toString());
        launch.setText(termux && permission
                ? "Open Twin-Pane" : "Set up (2 taps)");
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
        String pkg = termuxPackage();
        if (pkg == null) {
            return false;
        }
        try {
            return checkCallingOrSelfPermission(
                    "com.termux.permission.RUN_COMMAND") == PackageManager.PERMISSION_GRANTED;
        } catch (Exception ignored) {
            return false;
        }
    }

    // ------------------------------------------------------------- actions

    private void launchTerminal() {
        String pkg = termuxPackage();
        if (pkg == null) {
            promptInstallTermux();
            return;
        }
        if (!hasPermission()) {
            promptPermission(pkg);
            return;
        }
        try {
            installBundledProgram();
            startActivity(buildRunIntent(pkg));
        } catch (IOException error) {
            status.setText("Could not unpack the program:\n" + error.getMessage());
        } catch (ActivityNotFoundException error) {
            status.setText("Termux refused the command.\n"
                    + "Open Termux once, then allow \"run commands\" in its settings:\n\n"
                    + "Termux \u2192 long-press \u2192 More \u2192 Settings \u2192 "
                    + "allow-external-apps");
        }
    }

    private void promptInstallTermux() {
        new AlertDialog.Builder(this)
                .setTitle("Termux is required")
                .setMessage("Twin-Pane runs inside Termux - a real terminal. "
                        + "Install it from F-Droid (the Play Store build is outdated), "
                        + "open it once, then come back.")
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

    private void promptPermission(String pkg) {
        new AlertDialog.Builder(this)
                .setTitle("Allow running commands")
                .setMessage("Android will ask whether this app may run commands in "
                        + "Termux. Tap Allow.\n\nIf the dialog does not appear, open "
                        + "Termux and switch on:\n\n~/.termux/termux.properties\n"
                        + "  allow-external-apps=true\nthen restart Termux.")
                .setPositiveButton("Request now", (dialog, which) -> {
                    try {
                        startActivity(new Intent(this, SetupActivity.class)
                                .putExtra("termux", pkg));
                    } catch (Exception error) {
                        Toast.makeText(this, error.toString(), Toast.LENGTH_LONG).show();
                    }
                })
                .setNegativeButton("Copy the shell command", (dialog, which) -> {
                    ClipboardManager clipboard =
                            (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
                    clipboard.setPrimaryClip(ClipData.newPlainText("twinpane", runCommand()));
                    Toast.makeText(this, "Copied - paste it in Termux",
                            Toast.LENGTH_LONG).show();
                })
                .show();
    }

    /**
     * Copy the bundled Python program out of assets into Termux-visible storage.
     * Termux can read the app's own directory only on some builds, so the files
     * are unpacked next to the launcher and the command is pointed at them.
     */
    private void installBundledProgram() throws IOException {
        File root = new File(getFilesDir(), "twinpane");
        File payload = new File(root, "twinpane-standalone.py");
        if (payload.exists() && payload.length() > 4096) {
            return;                                     // already unpacked
        }
        if (!root.exists() && !root.mkdirs()) {
            throw new IOException("cannot create " + root);
        }
        AssetManager assets = getAssets();
        String[] names = assets.list("");
        if (names == null) {
            throw new IOException("empty assets");
        }
        for (String name : names) {
            copyAsset(assets, name, new File(root, name));
        }
    }

    private void copyAsset(AssetManager assets, String name, File target)
            throws IOException {
        try (InputStream in = assets.open(name);
             OutputStream out = new FileOutputStream(target)) {
            byte[] buffer = new byte[64 * 1024];
            int read;
            while ((read = in.read(buffer)) > 0) {
                out.write(buffer, 0, read);
            }
        }
    }

    private String payloadPath() {
        return new File(new File(getFilesDir(), "twinpane"),
                "twinpane-standalone.py").getAbsolutePath();
    }

    /** The exact command a power user can paste into Termux by hand. */
    private String runCommand() {
        return "python \"" + payloadPath() + "\" --install && twinpane";
    }

    private Intent buildRunIntent(String pkg) {
        Intent intent = new Intent();
        intent.setClassName(pkg, pkg + ".app.TermuxActivity");
        intent.setAction(TERMUX_RUN_COMMAND);
        intent.putExtra(EXTRA_PATH, "/data/data/" + pkg + "/files/usr/bin/sh");
        intent.putExtra(EXTRA_ARGUMENTS, new String[]{
                "-c",
                // install on first run, then start the UI in a foreground session
                "python \"" + payloadPath() + "\" --install >/dev/null 2>&1; "
                        + "exec twinpane"
        });
        intent.putExtra(EXTRA_WORKDIR, "/data/data/" + pkg + "/files/home");
        intent.putExtra(EXTRA_BACKGROUND, false);
        intent.putExtra(EXTRA_SESSION_ACTION, "0");
        intent.putExtra(EXTRA_COMMAND_LABEL, "Twin-Pane Explorer");
        intent.putExtra(EXTRA_COMMAND_DESCRIPTION, "Two-panel file manager");
        intent.putExtra(EXTRA_COMMAND_HELP, "Opens the twin-panel TUI");
        return intent;
    }

    @Override
    protected void onResume() {
        super.onResume();
        refreshState();
    }
}
