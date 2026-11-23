// Twin-Pane on the phone: two panels, stacked, either of which can be the
// phone's storage or the Termux home directory.
//
// Why two engines
// ---------------
// This app can only see /sdcard. Termux can see /sdcard *and* its own home.
// So:
//
//   local -> local     handled here, in Java (works with no Termux at all)
//   anything + Termux  handed to the worker in Termux through TermuxBridge
//
// That split is deliberate: the dependable path never depends on Termux, and
// the powerful path says plainly when Termux is not answering instead of
// pretending a transfer happened.
//
// Interaction (a phone, not a keyboard):
//   tap a row            tick / untick
//   tap a row's "›"      open that folder
//   tap a path bar       type any path
//   tap the other panel  make it active
//   tap Termux / Phone   switch what this panel is showing
//   Copy / Move          write everything ticked into the other panel's folder
package com.twinpane.explorer;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.DialogInterface;
import android.content.Intent;
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
import android.widget.BaseAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.TextView;
import android.widget.Toast;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

public class TwinPaneActivity extends Activity {

    private static final int REQUEST_STORAGE = 21;

    // ══════════════════════════════════════════════════════════════════ model

    /** One visible row, whichever engine produced it. */
    private static class Row {
        final String name;
        final String path;
        final boolean dir;
        final long size;
        final long mtime;

        Row(String name, String path, boolean dir, long size, long mtime) {
            this.name = name;
            this.path = path;
            this.dir = dir;
            this.size = size;
            this.mtime = mtime;
        }
    }

    private class Panel {
        final boolean isTop;
        /** True when this panel is showing Termux's own filesystem. */
        boolean termux;
        /** Current folder, as a real path for local and a guest path for Termux. */
        String path;
        final List<Row> rows = new ArrayList<>();
        final Set<String> selected = new LinkedHashSet<>();
        /** Local folders only: lets the cheap Java engine do the work. */
        File dir;

        ListView list;
        TextView pathLabel;
        TextView modeLabel;
        LinearLayout card;
        RowAdapter adapter;

        Panel(boolean isTop) {
            this.isTop = isTop;
        }

        boolean isLocal() {
            return !termux;
        }
    }

    private Panel top;
    private Panel bottom;
    private Panel active;
    private Button copyButton;
    private Button moveButton;
    private TextView statusLabel;

    private volatile boolean busy;
    private volatile boolean cancelled;
    private AlertDialog progressDialog;
    private TextView progressText;

    private boolean warnedAboutStorage;

    // ══════════════════════════════════════════════════════════════════════ ui

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        top = new Panel(true);
        bottom = new Panel(false);
        active = top;
        setContentView(buildUi());

        File start = firstReadable(startCandidates());
        setLocal(top, start);
        setLocal(bottom, start);
        focus(top);
        refreshWorkerState();
    }

    private View buildUi() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.parseColor("#0b1015"));

        root.addView(buildPanelHeader(top), wrap());
        root.addView(buildList(top), new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        root.addView(buildActionBar());

        root.addView(buildPanelHeader(bottom), wrap());
        root.addView(buildList(bottom), new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        statusLabel = new TextView(this);
        statusLabel.setTypeface(Typeface.MONOSPACE);
        statusLabel.setTextColor(Color.parseColor("#56606d"));
        statusLabel.setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f);
        statusLabel.setPadding(dp(10), dp(5), dp(10), dp(5));
        statusLabel.setBackgroundColor(Color.parseColor("#131a22"));
        statusLabel.setText(" tap = tick ·  ›  = open · tap the other panel to send files there");
        root.addView(statusLabel);
        return root;
    }

    private LinearLayout.LayoutParams wrap() {
        return new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    private View buildPanelHeader(final Panel panel) {
        LinearLayout column = new LinearLayout(this);
        column.setOrientation(LinearLayout.VERTICAL);
        panel.card = column;

        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setPadding(dp(4), dp(4), dp(4), dp(2));

        panel.modeLabel = new TextView(this);
        panel.modeLabel.setTypeface(Typeface.MONOSPACE, Typeface.BOLD);
        panel.modeLabel.setTextSize(TypedValue.COMPLEX_UNIT_SP, 9.5f);
        panel.modeLabel.setPadding(dp(6), dp(4), dp(8), dp(4));
        panel.modeLabel.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                focus(panel);
                chooseSource(panel);
            }
        });
        bar.addView(panel.modeLabel);

        panel.pathLabel = new TextView(this);
        panel.pathLabel.setTypeface(Typeface.MONOSPACE);
        panel.pathLabel.setTextColor(Color.parseColor("#9ecbff"));
        panel.pathLabel.setTextSize(TypedValue.COMPLEX_UNIT_SP, 10.5f);
        panel.pathLabel.setSingleLine(true);
        panel.pathLabel.setPadding(dp(2), dp(4), dp(2), dp(4));
        panel.pathLabel.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                focus(panel);
                editPath(panel);
            }
        });
        bar.addView(panel.pathLabel, new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        TextView up = tinyButton("↑");
        up.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                focus(panel);
                goUp(panel);
            }
        });
        bar.addView(up);

        TextView jump = tinyButton("≡");
        jump.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                focus(panel);
                showShortcuts(panel);
            }
        });
        bar.addView(jump);

        column.addView(bar, wrap());
        return column;
    }

    private View buildList(final Panel panel) {
        panel.list = new ListView(this);
        panel.list.setBackgroundColor(Color.parseColor("#0b1015"));
        panel.list.setDividerHeight(1);
        panel.list.setAdapter(panel.adapter = new RowAdapter(panel));
        panel.list.setOnItemClickListener(new AdapterView.OnItemClickListener() {
            @Override
            public void onItemClick(AdapterView<?> parent, View view, int position, long id) {
                focus(panel);
                toggle(panel, position);
            }
        });
        panel.list.setOnItemLongClickListener(new AdapterView.OnItemLongClickListener() {
            @Override
            public boolean onItemLongClick(AdapterView<?> parent, View view,
                                           int position, long id) {
                focus(panel);
                showEntryOptions(panel, position);
                return true;
            }
        });
        return panel.list;
    }

    private View buildActionBar() {
        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setBackgroundColor(Color.parseColor("#131a22"));
        bar.setPadding(dp(4), dp(4), dp(4), dp(4));

        copyButton = actionButton("Copy ▼", "#7ee787");
        copyButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                startTransfer(false);
            }
        });
        bar.addView(copyButton, weight());

        moveButton = actionButton("Move ▼", "#ffd479");
        moveButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                startTransfer(true);
            }
        });
        bar.addView(moveButton, weight());

        Button newFolder = actionButton("+ Folder", "#9ecbff");
        newFolder.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                createFolder(active);
            }
        });
        bar.addView(newFolder, weight());

        Button delete = actionButton("Delete", "#ff9b9b");
        delete.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                confirmDelete(active);
            }
        });
        bar.addView(delete, weight());
        return bar;
    }

    private LinearLayout.LayoutParams weight() {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        params.leftMargin = dp(2);
        params.rightMargin = dp(2);
        return params;
    }

    private Button actionButton(String label, String color) {
        Button button = new Button(this);
        button.setText(label);
        button.setAllCaps(false);
        button.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f);
        button.setTextColor(Color.parseColor(color));
        GradientDrawable background = new GradientDrawable();
        background.setColor(Color.parseColor("#1d2733"));
        background.setCornerRadius(dp(8));
        button.setBackground(background);
        button.setPadding(dp(2), dp(8), dp(2), dp(8));
        return button;
    }

    private TextView tinyButton(String label) {
        TextView view = new TextView(this);
        view.setText(label);
        view.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
        view.setTextColor(Color.parseColor("#7ee787"));
        view.setGravity(Gravity.CENTER);
        GradientDrawable background = new GradientDrawable();
        background.setColor(Color.parseColor("#1d2733"));
        background.setCornerRadius(dp(7));
        view.setBackground(background);
        view.setPadding(dp(10), dp(3), dp(10), dp(5));
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        params.leftMargin = dp(4);
        view.setLayoutParams(params);
        return view;
    }

    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density);
    }

    private void toast(String message) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
    }

    // ══════════════════════════════════════════════════════════════════ rows

    private class RowAdapter extends BaseAdapter {

        private final Panel panel;

        RowAdapter(Panel panel) {
            this.panel = panel;
        }

        @Override
        public int getCount() {
            return panel.rows.size();
        }

        @Override
        public Object getItem(int position) {
            return position >= 0 && position < panel.rows.size()
                    ? panel.rows.get(position) : null;
        }

        @Override
        public long getItemId(int position) {
            return position;
        }

        @Override
        public View getView(int position, View convertView, ViewGroup parent) {
            LinearLayout row = new LinearLayout(TwinPaneActivity.this);
            row.setOrientation(LinearLayout.HORIZONTAL);
            row.setGravity(Gravity.CENTER_VERTICAL);
            row.setPadding(dp(8), dp(6), dp(8), dp(6));

            if (position < 0 || position >= panel.rows.size()) {
                return row;
            }
            final Row entry = panel.rows.get(position);
            boolean ticked = panel.selected.contains(entry.path);

            row.setBackgroundColor(ticked
                    ? Color.parseColor("#16243a") : Color.parseColor("#0b1015"));

            TextView mark = new TextView(TwinPaneActivity.this);
            mark.setText(ticked ? "☑" : "☐");
            mark.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
            mark.setTextColor(Color.parseColor(ticked ? "#7ee787" : "#3d4652"));
            mark.setPadding(0, 0, dp(8), 0);
            row.addView(mark);

            LinearLayout column = new LinearLayout(TwinPaneActivity.this);
            column.setOrientation(LinearLayout.VERTICAL);

            TextView name = new TextView(TwinPaneActivity.this);
            name.setTypeface(Typeface.MONOSPACE);
            name.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f);
            name.setTextColor(Color.parseColor(entry.dir ? "#9ecbff" : "#d7dee8"));
            name.setSingleLine(true);
            name.setText(entry.name);
            column.addView(name);

            TextView meta = new TextView(TwinPaneActivity.this);
            meta.setTypeface(Typeface.MONOSPACE);
            meta.setTextSize(TypedValue.COMPLEX_UNIT_SP, 9.5f);
            meta.setTextColor(Color.parseColor("#56606d"));
            meta.setSingleLine(true);
            meta.setText(entry.dir ? "folder" : readableSize(entry.size));
            column.addView(meta);

            row.addView(column, new LinearLayout.LayoutParams(
                    0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

            if (entry.dir) {
                TextView open = new TextView(TwinPaneActivity.this);
                open.setText("›");
                open.setTextSize(TypedValue.COMPLEX_UNIT_SP, 20);
                open.setTextColor(Color.parseColor("#7ee787"));
                open.setGravity(Gravity.CENTER);
                open.setPadding(dp(10), dp(2), dp(6), dp(2));
                open.setOnClickListener(new View.OnClickListener() {
                    @Override
                    public void onClick(View v) {
                        focus(panel);
                        openRow(panel, entry);
                    }
                });
                row.addView(open);
            }
            return row;
        }
    }

    // ══════════════════════════════════════════════════════════════ panel state

    private File[] startCandidates() {
        List<File> list = new ArrayList<>();
        File shared = Environment.getExternalStorageDirectory();
        if (shared != null) {
            list.add(shared);
        }
        list.add(new File("/storage/emulated/0"));
        File downloads = Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOWNLOADS);
        if (downloads != null) {
            list.add(downloads);
        }
        File appExternal = getExternalFilesDir(null);
        if (appExternal != null) {
            list.add(appExternal);
        }
        list.add(getFilesDir());
        return list.toArray(new File[0]);
    }

    private File firstReadable(File[] candidates) {
        for (File candidate : candidates) {
            if (candidate != null && candidate.isDirectory() && candidate.canRead()) {
                return candidate;
            }
        }
        return getFilesDir();
    }

    private boolean hasSharedAccess() {
        File root = Environment.getExternalStorageDirectory();
        return root != null && root.isDirectory() && root.canRead() && root.list() != null;
    }

    /** Point a panel at a local folder and fill it. */
    private void setLocal(Panel panel, File folder) {
        panel.termux = false;
        panel.dir = folder;
        panel.path = folder == null ? null : folder.getAbsolutePath();
        panel.selected.clear();
        refresh(panel);
    }

    /** Point a panel at a Termux folder and fill it through the bridge. */
    private void setTermux(final Panel panel, final String path) {
        panel.termux = true;
        panel.dir = null;
        panel.path = path;
        panel.selected.clear();
        refresh(panel);
        if (!TermuxBridge.workerAlive()) {
            return;                                  // refresh() already explained
        }
        new Thread(new Runnable() {
            @Override
            public void run() {
                final TermuxBridge.Listing listing = TermuxBridge.list(path, false);
                runOnUiThread(new Runnable() {
                    @Override
                    public void run() {
                        if (panel.path == null || !panel.path.equals(path)
                                && !panel.path.equals(listing.path)) {
                            return;                  // user moved on while we waited
                        }
                        if (listing.failure != null) {
                            statusLabel.setText(" " + listing.failure);
                            toast(listing.failure);
                            return;
                        }
                        applyListing(panel, listing);
                    }
                });
            }
        }).start();
    }

    private void applyListing(Panel panel, TermuxBridge.Listing listing) {
        panel.path = listing.path;
        panel.rows.clear();
        for (TermuxBridge.Item item : listing.items) {
            panel.rows.add(new Row(item.name, item.path, item.dir, item.size, item.mtime));
        }
        panel.adapter.notifyDataSetChanged();
        paintPanel(panel);
        paintFocus();
    }

    /** Re-read the panel's folder, whichever engine it uses. */
    private void refresh(Panel panel) {
        if (panel.isLocal()) {
            File folder = panel.dir;
            if (folder == null || !folder.canRead()) {
                panel.rows.clear();
                panel.adapter.notifyDataSetChanged();
                paintPanel(panel);
                return;
            }
            File[] children = folder.listFiles();
            panel.rows.clear();
            if (children != null) {
                List<File> sorted = new ArrayList<>(Arrays.asList(children));
                Collections.sort(sorted, new Comparator<File>() {
                    @Override
                    public int compare(File a, File b) {
                        if (a.isDirectory() != b.isDirectory()) {
                            return a.isDirectory() ? -1 : 1;
                        }
                        return a.getName().compareToIgnoreCase(b.getName());
                    }
                });
                for (File child : sorted) {
                    if (child.getName().startsWith(".")) {
                        continue;
                    }
                    panel.rows.add(new Row(child.getName(), child.getAbsolutePath(),
                            child.isDirectory(),
                            child.isDirectory() ? 0 : child.length(),
                            child.lastModified()));
                }
            }
            dropDeadTicks(panel);
            panel.adapter.notifyDataSetChanged();
            paintPanel(panel);
        } else {
            setTermux(panel, panel.path == null ? TermuxBridge.termuxHome() : panel.path);
        }
    }

    private void dropDeadTicks(Panel panel) {
        Set<String> alive = new LinkedHashSet<>();
        for (Row row : panel.rows) {
            if (panel.selected.contains(row.path)) {
                alive.add(row.path);
            }
        }
        panel.selected.retainAll(alive);
    }

    private void paintPanel(Panel panel) {
        boolean termux = panel.termux;
        panel.modeLabel.setText(termux ? " TERMUX " : " PHONE ");
        panel.modeLabel.setTextColor(Color.parseColor(termux ? "#ffd479" : "#7ee787"));
        GradientDrawable chip = new GradientDrawable();
        chip.setColor(Color.parseColor(termux ? "#3a2f16" : "#13301c"));
        chip.setCornerRadius(dp(6));
        panel.modeLabel.setBackground(chip);

        String shown = panel.path == null ? "…" : shortPath(panel.path, termux);
        panel.pathLabel.setText(shown);
    }

    private String shortPath(String path, boolean termux) {
        String home = TermuxBridge.termuxHome();
        if (termux && path != null && path.startsWith(home)) {
            return "~" + path.substring(home.length());
        }
        File root = Environment.getExternalStorageDirectory();
        if (!termux && root != null && path != null
                && path.startsWith(root.getAbsolutePath())) {
            return "/sdcard" + path.substring(root.getAbsolutePath().length());
        }
        return path == null ? "…" : path;
    }

    private void focus(Panel panel) {
        active = panel;
        paintFocus();
    }

    private void paintFocus() {
        if (top.card != null) {
            paintCard(top.card, top == active, top.termux);
        }
        if (bottom.card != null) {
            paintCard(bottom.card, bottom == active, bottom.termux);
        }
        boolean topActive = active == top;
        copyButton.setText(topActive ? "Copy ▼" : "Copy ▲");
        moveButton.setText(topActive ? "Move ▼" : "Move ▲");
        boolean hasTicks = !active.selected.isEmpty();
        copyButton.setAlpha(hasTicks ? 1f : 0.45f);
        moveButton.setAlpha(hasTicks ? 1f : 0.45f);
    }

    private void paintCard(LinearLayout card, boolean isActive, boolean termux) {
        GradientDrawable background = new GradientDrawable();
        String color;
        if (!isActive) {
            color = "#131a22";
        } else {
            color = termux ? "#2b2415" : "#1b2b40";
        }
        background.setColor(Color.parseColor(color));
        background.setCornerRadius(dp(6));
        card.setBackground(background);
    }

    private void refreshWorkerState() {
        if (TermuxBridge.workerAlive()) {
            statusLabel.setText(" Termux worker: ready");
            return;
        }
        statusLabel.setText(" Termux worker: not running · tap here for the command");
        statusLabel.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                showWorkerHelp();
            }
        });
    }

    private void showWorkerHelp() {
        final String command = "twinpane-bridge";
        new AlertDialog.Builder(this)
                .setTitle("Termux panel is inactive")
                .setMessage("To read Termux's own files, a small worker must run "
                        + "inside Termux. Open Termux and run:\n\n"
                        + command + "\n\n"
                        + "Or in the background, so it survives:\n\n"
                        + "sv-enable twinpane-bridge\n\n"
                        + "The phone panel needs none of this — it always works.")
                .setPositiveButton("Got it", null)
                .setNegativeButton("Copy command", new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        android.content.ClipboardManager clipboard =
                                (android.content.ClipboardManager) getSystemService(
                                        CLIPBOARD_SERVICE);
                        clipboard.setPrimaryClip(
                                android.content.ClipData.newPlainText("termux", command));
                        toast("Copied");
                    }
                })
                .show();
    }

    // ══════════════════════════════════════════════════════════════ navigation

    private void toggle(Panel panel, int position) {
        if (position < 0 || position >= panel.rows.size()) {
            return;
        }
        String key = panel.rows.get(position).path;
        if (!panel.selected.remove(key)) {
            panel.selected.add(key);
        }
        panel.adapter.notifyDataSetChanged();
        paintFocus();
    }

    private void openRow(Panel panel, Row row) {
        if (!row.dir) {
            return;
        }
        if (panel.isLocal()) {
            File folder = new File(row.path);
            if (!folder.canRead()) {
                toast("No access to " + row.name);
                return;
            }
            setLocal(panel, folder);
        } else {
            setTermux(panel, row.path);
        }
        paintFocus();
    }

    private void goUp(Panel panel) {
        if (panel.isLocal()) {
            File parent = panel.dir == null ? null : panel.dir.getParentFile();
            if (parent == null || !parent.canRead()) {
                showShortcuts(panel);
                return;
            }
            setLocal(panel, parent);
        } else {
            if (panel.path == null) {
                return;
            }
            String parent = new File(panel.path).getParent();
            if (parent == null) {
                showShortcuts(panel);
                return;
            }
            setTermux(panel, parent);
        }
        paintFocus();
    }

    private void chooseSource(final Panel panel) {
        final String[] options = {
                "Phone storage  (works always)",
                "Termux home  (needs the worker)",
        };
        new AlertDialog.Builder(this)
                .setTitle("What should this panel show?")
                .setItems(options, new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        if (which == 0) {
                            setLocal(panel, firstReadable(startCandidates()));
                        } else {
                            if (!TermuxBridge.workerAlive()) {
                                showWorkerHelp();
                                return;
                            }
                            setTermux(panel, TermuxBridge.termuxHome());
                        }
                        paintFocus();
                    }
                })
                .show();
    }

    private void editPath(final Panel panel) {
        final EditText input = new EditText(this);
        input.setTypeface(Typeface.MONOSPACE);
        input.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f);
        input.setText(panel.path == null ? "" : panel.path);
        input.setPadding(dp(12), dp(8), dp(12), dp(8));

        new AlertDialog.Builder(this)
                .setTitle(panel.termux ? "Termux path" : "Phone path")
                .setView(input)
                .setPositiveButton("Open", new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        String typed = input.getText().toString().trim();
                        if (typed.isEmpty()) {
                            return;
                        }
                        if (panel.isLocal()) {
                            File wanted = new File(typed);
                            if (!wanted.isDirectory()) {
                                toast("Not a folder");
                                return;
                            }
                            if (!wanted.canRead()) {
                                toast("Not readable — grant storage access");
                                return;
                            }
                            setLocal(panel, wanted);
                        } else {
                            setTermux(panel, typed);
                        }
                        paintFocus();
                    }
                })
                .setNegativeButton("Cancel", null)
                .show();
    }

    private void showShortcuts(final Panel panel) {
        final List<String> names = new ArrayList<>();
        final List<Runnable> actions = new ArrayList<>();

        if (panel.isLocal()) {
            addLocalPlace(names, actions, "Phone storage  /sdcard",
                    Environment.getExternalStorageDirectory());
            addLocalPlace(names, actions, "Downloads",
                    Environment.getExternalStoragePublicDirectory(
                            Environment.DIRECTORY_DOWNLOADS));
            addLocalPlace(names, actions, "DCIM (camera)",
                    Environment.getExternalStoragePublicDirectory(
                            Environment.DIRECTORY_DCIM));
            addLocalPlace(names, actions, "Pictures",
                    Environment.getExternalStoragePublicDirectory(
                            Environment.DIRECTORY_PICTURES));
            addLocalPlace(names, actions, "Music",
                    Environment.getExternalStoragePublicDirectory(
                            Environment.DIRECTORY_MUSIC));
            addLocalPlace(names, actions, "Documents",
                    Environment.getExternalStoragePublicDirectory(
                            Environment.DIRECTORY_DOCUMENTS));
            File shared = Environment.getExternalStorageDirectory();
            if (shared != null) {
                addLocalPlace(names, actions, "Android/data",
                        new File(shared, "Android/data"));
                addLocalPlace(names, actions, "shared  (TwinPane)",
                        new File(shared, "TwinPane"));
            }
            addLocalPlace(names, actions, "This app's files", getFilesDir());
        } else {
            String home = TermuxBridge.termuxHome();
            for (final String candidate : new String[]{home}) {
                final String label = "Termux home  ~";
                names.add(label);
                actions.add(new Runnable() {
                    @Override
                    public void run() {
                        setTermux(panel, candidate);
                    }
                });
            }
            final TermuxBridge.Listing probe = TermuxBridge.list(home, false);
            for (final String[] place : probe.places) {
                names.add(place[0]);
                actions.add(new Runnable() {
                    @Override
                    public void run() {
                        setTermux(panel, place[1]);
                    }
                });
            }
            if (probe.failure != null) {
                toast(probe.failure);
            }
        }

        new AlertDialog.Builder(this)
                .setTitle((panel.isTop ? "Top" : "Bottom") + " panel → jump to")
                .setItems(names.toArray(new String[0]), new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        actions.get(which).run();
                        paintFocus();
                    }
                })
                .setPositiveButton(panel.isLocal() ? "Grant full access" : "Worker help",
                        new DialogInterface.OnClickListener() {
                            @Override
                            public void onClick(DialogInterface dialog, int which) {
                                if (panel.isLocal()) {
                                    requestStorage();
                                } else {
                                    showWorkerHelp();
                                }
                            }
                        })
                .setNegativeButton("Close", null)
                .show();
    }

    private void addLocalPlace(List<String> names, List<Runnable> actions,
                               String label, final File folder) {
        if (folder == null) {
            return;
        }
        names.add(label + (folder.canRead() ? "" : "   (no access)"));
        actions.add(new Runnable() {
            @Override
            public void run() {
                if (!folder.isDirectory()) {
                    toast("Does not exist on this phone");
                    return;
                }
                if (!folder.canRead()) {
                    toast("Permission denied — Android blocks this path");
                    return;
                }
                setLocal(active, folder);
            }
        });
    }

    // ══════════════════════════════════════════════════════════════ transfer

    private void startTransfer(final boolean move) {
        if (busy) {
            toast("Already working…");
            return;
        }
        final Panel source = active;
        final Panel target = active == top ? bottom : top;
        if (source.rows.isEmpty()) {
            toast("This panel is empty");
            return;
        }
        if (source.selected.isEmpty()) {
            toast("Tick some items first");
            return;
        }
        if (target.path == null) {
            toast("The other panel has no folder open");
            return;
        }

        boolean crossesTermux = source.termux || target.termux;
        if (!crossesTermux && (!hasSharedAccess() || !target.dir.canWrite())) {
            toast("Android is blocking storage — tap the bottom bar");
            return;
        }

        final List<String> items = new ArrayList<>(source.selected);
        final boolean viaBridge = crossesTermux;
        askConflictIfNeeded(items, target, new ConflictAnswer() {
            @Override
            public void onAnswer(String conflict) {
                if (viaBridge) {
                    if (!TermuxBridge.workerAlive()) {
                        showWorkerHelp();
                        return;
                    }
                    runBridgeTransfer(move ? "move" : "copy", items, target,
                            conflict, source, target);
                } else {
                    runLocalTransfer(items, move, conflict, source, target);
                }
            }
        });
    }

    /**
     * The phone's own two panels keep the fast Java path: no worker, no JSON,
     * no delay, and it is the path that works when Termux is not installed.
     */
    private void runLocalTransfer(final List<String> items, final boolean move,
                                  final String conflict, final Panel source,
                                  final Panel target) {
        busy = true;
        cancelled = false;
        showProgress(move ? "Moving" : "Copying", items.size());

        new Thread(new Runnable() {
            @Override
            public void run() {
                final List<String> problems = new ArrayList<>();
                int done = 0;
                int skipped = 0;
                for (String item : items) {
                    if (cancelled) {
                        break;
                    }
                    setProgressText("working on  " + new File(item).getName());
                    try {
                        if (copyOne(new File(item), target.dir, move,
                                "skip".equals(conflict) ? 1
                                        : "rename".equals(conflict) ? 2 : 0)) {
                            done++;
                        } else {
                            skipped++;
                        }
                    } catch (IOException error) {
                        problems.add(new File(item).getName() + "  —  "
                                + error.getMessage());
                    }
                }
                final int finished = done;
                final int left = skipped;
                finishTransfer(finished, left, problems, move, source, target);
            }
        }).start();
    }

    /** Anything touching Termux goes through the worker, which sees both sides. */
    private void runBridgeTransfer(final String mode, final List<String> items,
                                   final Panel target, final String conflict,
                                   final Panel source, final Panel targetPanel) {
        busy = true;
        cancelled = false;
        showProgress("move".equals(mode) ? "Moving" : "Copying", items.size());

        new Thread(new Runnable() {
            @Override
            public void run() {
                setProgressText("asking Termux…");
                TermuxBridge.Outcome outcome =
                        TermuxBridge.transfer(mode, items, target.path, conflict);
                final List<String> problems = new ArrayList<>(outcome.problems);
                if (outcome.error != null) {
                    problems.add(outcome.error);
                }
                finishTransfer(outcome.files + outcome.dirs, outcome.skipped,
                        problems, "move".equals(mode), source, targetPanel);
            }
        }).start();
    }

    private void finishTransfer(int done, int skipped, List<String> problems,
                                boolean move, Panel source, Panel target) {
        final int finished = done;
        final int left = skipped;
        final List<String> issues = problems;
        final boolean wasMove = move;
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                dismissProgress();
                busy = false;
                source.selected.clear();
                refresh(source);
                refresh(target);
                paintFocus();
                String summary = (wasMove ? "Moved " : "Copied ") + finished
                        + (left > 0 ? " · skipped " + left : "")
                        + (issues.isEmpty() ? "" : " · " + issues.size() + " failed");
                statusLabel.setText(" " + summary);
                toast(summary);
                if (!issues.isEmpty()) {
                    showProblems(issues);
                }
            }
        });
    }

    /**
     * Works out what to do about names that already exist.
     *
     * <p>An AlertDialog is asynchronous, so this cannot return the answer.
     * It calls {@code proceed} once the user has decided - and calls nothing at
     * all when they cancel, which is what makes "Cancel" actually cancel.
     */
    private void askConflictIfNeeded(List<String> items, Panel target,
                                     ConflictAnswer proceed) {
        int conflicts = 0;
        for (String item : items) {
            String name = new File(item).getName();
            if (target.isLocal()) {
                if (new File(target.dir, name).exists()) {
                    conflicts++;
                }
            }
        }

        if (conflicts == 0) {
            // Nothing to clash with on the side we can see. "Keep both" is the
            // safe default everywhere else: the worker never destroys a file
            // just because two names matched.
            proceed.onAnswer("rename");
            return;
        }

        final ConflictAnswer callback = proceed;
        new AlertDialog.Builder(this)
                .setTitle(conflicts + (conflicts == 1 ? " item already exists"
                        : " items already exist"))
                .setItems(new String[]{"Keep both", "Overwrite", "Skip", "Cancel"},
                        new DialogInterface.OnClickListener() {
                            @Override
                            public void onClick(DialogInterface dialog, int which) {
                                String choice = which == 0 ? "rename"
                                        : which == 1 ? "overwrite"
                                        : which == 2 ? "skip" : null;
                                if (choice != null) {
                                    callback.onAnswer(choice);
                                }
                            }
                        })
                .setNegativeButton("Cancel", null)
                .show();
    }

    private interface ConflictAnswer {
        void onAnswer(String conflict);
    }

    private void showProgress(String title, int count) {
        progressText = new TextView(this);
        progressText.setTypeface(Typeface.MONOSPACE);
        progressText.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f);
        progressText.setTextColor(Color.parseColor("#d7dee8"));
        progressText.setPadding(dp(16), dp(12), dp(16), dp(12));
        progressText.setText(count + (count == 1 ? " item" : " items") + " queued");

        progressDialog = new AlertDialog.Builder(this)
                .setTitle(title)
                .setView(progressText)
                .setNegativeButton("Cancel", new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        cancelled = true;
                    }
                })
                .create();
        progressDialog.setCancelable(false);
        progressDialog.show();
    }

    private void setProgressText(final String message) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                if (progressText != null) {
                    progressText.setText(message);
                }
            }
        });
    }

    private void dismissProgress() {
        if (progressDialog != null && progressDialog.isShowing()) {
            progressDialog.dismiss();
        }
        progressDialog = null;
    }

    private void showProblems(List<String> problems) {
        StringBuilder body = new StringBuilder();
        int limit = Math.min(problems.size(), 8);
        for (int index = 0; index < limit; index++) {
            body.append("• ").append(problems.get(index)).append('\n');
        }
        if (problems.size() > limit) {
            body.append("… and ").append(problems.size() - limit).append(" more");
        }
        new AlertDialog.Builder(this)
                .setTitle("Could not finish everything")
                .setMessage(body.toString())
                .setPositiveButton("OK", null)
                .show();
    }

    /**
     * Copy or move one local item into {@code targetDir}.
     *
     * @return true when written, false when deliberately skipped
     */
    private boolean copyOne(File item, File targetDir, boolean move, int mode)
            throws IOException {
        File destination = new File(targetDir, item.getName());

        if (item.isDirectory() && isInside(targetDir, item)) {
            throw new IOException("cannot put a folder inside itself");
        }
        File parent = item.getParentFile();
        if (parent != null && parent.equals(targetDir) && mode != 2) {
            return false;
        }

        if (destination.exists()) {
            if (mode == 1) {
                return false;                            // skip
            }
            if (mode == 2) {
                destination = uniqueName(targetDir, item.getName());
            } else {
                deleteRecursive(destination);
            }
        }

        if (move && item.renameTo(destination)) {
            return true;                                 // same filesystem
        }
        copyRecursive(item, destination);
        if (move && !deleteRecursive(item)) {
            throw new IOException("copied, but could not remove the original");
        }
        return true;
    }

    private static boolean isInside(File child, File parent) {
        String childPath = child.getAbsolutePath();
        String parentPath = parent.getAbsolutePath();
        return childPath.equals(parentPath)
                || childPath.startsWith(parentPath + File.separator);
    }

    private File uniqueName(File folder, String name) {
        String stem = name;
        String extension = "";
        int dot = name.lastIndexOf('.');
        if (dot > 0) {
            stem = name.substring(0, dot);
            extension = name.substring(dot);
        }
        File candidate = new File(folder, name);
        int counter = 1;
        while (candidate.exists() && counter < 1000) {
            candidate = new File(folder, stem + " (" + counter + ")" + extension);
            counter++;
        }
        return candidate;
    }

    private void copyRecursive(File source, File destination) throws IOException {
        if (source.isDirectory()) {
            if (!destination.exists() && !destination.mkdirs()) {
                throw new IOException("cannot create folder " + destination.getName());
            }
            File[] children = source.listFiles();
            if (children == null) {
                return;
            }
            for (File child : children) {
                copyRecursive(child, new File(destination, child.getName()));
            }
        } else {
            File folder = destination.getParentFile();
            if (folder != null && !folder.exists() && !folder.mkdirs()) {
                throw new IOException("cannot create " + folder.getName());
            }
            InputStream in = null;
            OutputStream out = null;
            try {
                in = new FileInputStream(source);
                out = new FileOutputStream(destination);
                byte[] buffer = new byte[64 * 1024];
                int read;
                while ((read = in.read(buffer)) > 0) {
                    out.write(buffer, 0, read);
                    if (cancelled) {
                        break;
                    }
                }
            } finally {
                closeQuietly(in);
                closeQuietly(out);
            }
        }
    }

    private static void closeQuietly(java.io.Closeable stream) {
        if (stream != null) {
            try {
                stream.close();
            } catch (IOException ignored) {
                // nothing useful to do
            }
        }
    }

    private boolean deleteRecursive(File file) {
        if (file.isDirectory()) {
            File[] children = file.listFiles();
            if (children != null) {
                for (File child : children) {
                    deleteRecursive(child);
                }
            }
        }
        return file.delete();
    }

    private String readableSize(long bytes) {
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

    // ══════════════════════════════════════════════════════════════ authoring

    private void createFolder(final Panel panel) {
        final EditText input = new EditText(this);
        input.setTypeface(Typeface.MONOSPACE);
        input.setHint("new folder");
        input.setPadding(dp(12), dp(8), dp(12), dp(8));

        new AlertDialog.Builder(this)
                .setTitle("New folder")
                .setView(input)
                .setPositiveButton("Create", new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        String name = input.getText().toString().trim();
                        if (name.isEmpty()) {
                            return;
                        }
                        if (panel.isLocal()) {
                            File created = new File(panel.dir, name);
                            if (created.exists()) {
                                toast("Already exists");
                                return;
                            }
                            if (created.mkdirs()) {
                                refresh(panel);
                                toast("Created " + name);
                            } else {
                                toast("Could not create — no write access");
                            }
                        } else {
                            if (!TermuxBridge.workerAlive()) {
                                showWorkerHelp();
                                return;
                            }
                            TermuxBridge.Outcome outcome =
                                    TermuxBridge.makeFolder(panel.path, name);
                            if (outcome.ok) {
                                refresh(panel);
                                toast("Created " + name);
                            } else {
                                toast(outcome.error == null
                                        ? "Could not create" : outcome.error);
                            }
                        }
                    }
                })
                .setNegativeButton("Cancel", null)
                .show();
    }

    private void confirmDelete(final Panel panel) {
        if (panel.selected.isEmpty()) {
            toast("Tick some items first");
            return;
        }
        new AlertDialog.Builder(this)
                .setTitle("Delete " + panel.selected.size()
                        + (panel.selected.size() == 1 ? " item?" : " items?"))
                .setMessage("This cannot be undone.")
                .setPositiveButton("Delete", new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        List<String> items = new ArrayList<>(panel.selected);
                        if (panel.isLocal()) {
                            int removed = 0;
                            for (String path : items) {
                                if (deleteRecursive(new File(path))) {
                                    removed++;
                                }
                            }
                            panel.selected.clear();
                            refresh(panel);
                            paintFocus();
                            toast("Deleted " + removed);
                        } else {
                            if (!TermuxBridge.workerAlive()) {
                                showWorkerHelp();
                                return;
                            }
                            TermuxBridge.Outcome outcome = TermuxBridge.delete(items);
                            panel.selected.clear();
                            refresh(panel);
                            paintFocus();
                            toast(outcome.ok
                                    ? "Deleted " + (outcome.files + outcome.dirs)
                                    : String.valueOf(outcome.error));
                        }
                    }
                })
                .setNegativeButton("Cancel", null)
                .show();
    }

    private void showEntryOptions(final Panel panel, int position) {
        if (position < 0 || position >= panel.rows.size()) {
            return;
        }
        final Row entry = panel.rows.get(position);
        String[] options = entry.dir
                ? new String[]{"Tick / untick", "Open folder", "Show details"}
                : new String[]{"Tick / untick", "Show details"};
        new AlertDialog.Builder(this)
                .setTitle(entry.name)
                .setItems(options, new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        if (which == 0) {
                            toggle(panel, panel.rows.indexOf(entry));
                        } else if (which == 1 && entry.dir) {
                            openRow(panel, entry);
                        } else {
                            showDetails(entry);
                        }
                    }
                })
                .show();
    }

    private void showDetails(Row entry) {
        String body = "size     : " + readableSize(entry.size)
                + "\npath     : " + entry.path
                + "\nsource   : " + (active.termux
                ? "Termux (via the worker)" : "phone storage");
        new AlertDialog.Builder(this)
                .setTitle(entry.name)
                .setMessage(body)
                .setPositiveButton("OK", null)
                .show();
    }

    // ══════════════════════════════════════════════════════════════ storage

    private void requestStorage() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                startActivity(new Intent(
                        Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                        Uri.parse("package:" + getPackageName())));
                return;
            } catch (Exception ignored) {
                // some manufacturers only expose the general screen
            }
            try {
                startActivity(new Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION));
                return;
            } catch (Exception ignored) {
                // fall through to the legacy request
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            requestPermissions(new String[]{"android.permission.READ_EXTERNAL_STORAGE"},
                    REQUEST_STORAGE);
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions,
                                           int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQUEST_STORAGE) {
            warnIfBlocked();
            refresh(top);
            refresh(bottom);
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        warnIfBlocked();
        refreshWorkerState();
        refresh(top);
        refresh(bottom);
        paintFocus();
    }

    private void warnIfBlocked() {
        if (hasSharedAccess() || warnedAboutStorage) {
            return;
        }
        warnedAboutStorage = true;
        statusLabel.setText(" ⚠ no access to /sdcard — tap here");
        statusLabel.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                requestStorage();
            }
        });
        toast("Tap the bottom bar to allow file access");
    }
}
