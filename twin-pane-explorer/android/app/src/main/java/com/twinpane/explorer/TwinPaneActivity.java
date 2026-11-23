// Twin-Pane, on the phone, with two real panels.
//
// The whole point: two lists stacked top/bottom (a phone is tall, not wide),
// each with its own folder, its own multi-selection, and Copy/Move from the
// active panel into the *other* panel's folder. Everything here works on plain
// local paths, so it needs no Termux at all - which is exactly what makes it
// dependable. A Termux home directory can be opened in either panel the moment
// the OS lets the app read it.
//
// Interaction model (deliberately simple, matching how a phone is used):
//   * tap a row            -> tick / untick it (files and folders alike)
//   * tap the "›" on a row -> walk into that folder
//   * tap a path bar       -> type any path directly
//   * tap the other panel  -> make it the active one
//   * Copy / Move          -> take everything ticked and write it into the
//                             folder the other panel is showing
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

    private static final int CONFLICT_ASK = 0;

    // ── one panel ────────────────────────────────────────────────────────────
    private class Panel {
        final boolean isTop;
        File dir;
        final List<File> entries = new ArrayList<>();
        final Set<String> selected = new LinkedHashSet<>();
        ListView list;
        TextView pathLabel;
        LinearLayout card;
        RowAdapter adapter;

        Panel(boolean isTop) {
            this.isTop = isTop;
        }
    }

    private Panel top;
    private Panel bottom;
    private Panel active;
    private Button copyButton;
    private Button moveButton;
    private TextView statusLabel;

    /** Set while a transfer runs, so Cancel and re-entry stay predictable. */
    private volatile boolean transferRunning;
    private volatile boolean transferCancelled;
    private AlertDialog transferDialog;
    private TextView transferText;

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
        // Both panels start in the same place: the phone's storage. One tap on
        // a folder's ">" and they are two different folders, which is the
        // moment Copy/Move becomes useful.
        top.dir = start;
        bottom.dir = start;
        refresh(top);
        refresh(bottom);
        focus(top);
    }

    private View buildUi() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.parseColor("#0b1015"));

        root.addView(buildPanelHeader(top), new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        root.addView(buildList(top), new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        root.addView(buildActionBar());

        root.addView(buildPanelHeader(bottom), new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        root.addView(buildList(bottom), new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        statusLabel = new TextView(this);
        statusLabel.setTypeface(Typeface.MONOSPACE);
        statusLabel.setTextColor(Color.parseColor("#56606d"));
        statusLabel.setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f);
        statusLabel.setPadding(dp(10), dp(5), dp(10), dp(5));
        statusLabel.setBackgroundColor(Color.parseColor("#131a22"));
        statusLabel.setText(" tap = tick ·  ›  = open folder · tap a panel to make it active");
        root.addView(statusLabel);
        return root;
    }

    private View buildPanelHeader(final Panel panel) {
        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setPadding(dp(4), dp(5), dp(4), dp(5));

        panel.card = bar;

        panel.pathLabel = new TextView(this);
        panel.pathLabel.setTypeface(Typeface.MONOSPACE);
        panel.pathLabel.setTextColor(Color.parseColor("#9ecbff"));
        panel.pathLabel.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f);
        panel.pathLabel.setSingleLine(true);
        panel.pathLabel.setPadding(dp(4), dp(4), dp(4), dp(4));
        panel.pathLabel.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                focus(panel);
                editPath(panel);
            }
        });
        LinearLayout.LayoutParams pathParams = new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        bar.addView(panel.pathLabel, pathParams);

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
        return bar;
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
        button.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f);
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
        view.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        view.setTextColor(Color.parseColor("#7ee787"));
        view.setGravity(Gravity.CENTER);
        GradientDrawable background = new GradientDrawable();
        background.setColor(Color.parseColor("#1d2733"));
        background.setCornerRadius(dp(7));
        view.setBackground(background);
        view.setPadding(dp(11), dp(3), dp(11), dp(5));
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
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

    /** Draws one row: a tick, the name, a size/date line, and "›" for folders. */
    private class RowAdapter extends BaseAdapter {

        private final Panel panel;

        RowAdapter(Panel panel) {
            this.panel = panel;
        }

        @Override
        public int getCount() {
            return panel.entries.size();
        }

        @Override
        public Object getItem(int position) {
            return position >= 0 && position < panel.entries.size()
                    ? panel.entries.get(position) : null;
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
            int pad = dp(8);
            row.setPadding(pad, dp(6), pad, dp(6));

            if (position < 0 || position >= panel.entries.size()) {
                return row;
            }
            final File file = panel.entries.get(position);
            boolean ticked = panel.selected.contains(file.getAbsolutePath());
            boolean isDir = file.isDirectory();

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
            LinearLayout.LayoutParams columnParams = new LinearLayout.LayoutParams(
                    0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);

            TextView name = new TextView(TwinPaneActivity.this);
            name.setTypeface(Typeface.MONOSPACE);
            name.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f);
            name.setTextColor(Color.parseColor(isDir ? "#9ecbff" : "#d7dee8"));
            name.setSingleLine(true);
            name.setText(file.getName().isEmpty()
                    ? file.getAbsolutePath() : file.getName());
            column.addView(name);

            TextView meta = new TextView(TwinPaneActivity.this);
            meta.setTypeface(Typeface.MONOSPACE);
            meta.setTextSize(TypedValue.COMPLEX_UNIT_SP, 9.5f);
            meta.setTextColor(Color.parseColor("#56606d"));
            meta.setSingleLine(true);
            meta.setText(isDir ? "folder" : readableSize(file.length()));
            column.addView(meta);

            row.addView(column, columnParams);

            if (isDir) {
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
                        openDirectory(panel, file);
                    }
                });
                row.addView(open);
            }
            return row;
        }
    }

    // ══════════════════════════════════════════════════════════════ navigation

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

    private void refresh(Panel panel) {
        if (panel.dir == null) {
            panel.dir = getFilesDir();
        }
        File[] children = panel.dir.canRead() ? panel.dir.listFiles() : null;
        panel.entries.clear();
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
                if (!child.getName().startsWith(".")) {
                    panel.entries.add(child);
                }
            }
        }
        // drop ticks for anything that is no longer listed
        Set<String> alive = new LinkedHashSet<>();
        for (File entry : panel.entries) {
            if (panel.selected.contains(entry.getAbsolutePath())) {
                alive.add(entry.getAbsolutePath());
            }
        }
        panel.selected.retainAll(alive);

        panel.pathLabel.setText(shortPath(panel.dir));
        panel.adapter.notifyDataSetChanged();
    }

    private String shortPath(File folder) {
        String full = folder.getAbsolutePath();
        File root = Environment.getExternalStorageDirectory();
        if (root != null) {
            String prefix = root.getAbsolutePath();
            if (full.startsWith(prefix)) {
                return "/sdcard" + full.substring(prefix.length());
            }
        }
        return full;
    }

    private void focus(Panel panel) {
        if (active == panel) {
            paintFocus();
            return;
        }
        active = panel;
        paintFocus();
    }

    private void paintFocus() {
        if (top.card != null) {
            paintCard(top.card, top == active);
        }
        if (bottom.card != null) {
            paintCard(bottom.card, bottom == active);
        }
        boolean topActive = active == top;
        copyButton.setText(topActive ? "Copy ▼" : "Copy ▲");
        moveButton.setText(topActive ? "Move ▼" : "Move ▲");
        boolean hasTicks = !active.selected.isEmpty();
        copyButton.setAlpha(hasTicks ? 1f : 0.45f);
        moveButton.setAlpha(hasTicks ? 1f : 0.45f);
    }

    private void paintCard(LinearLayout card, boolean isActive) {
        GradientDrawable background = new GradientDrawable();
        background.setColor(Color.parseColor(isActive ? "#1b2b40" : "#131a22"));
        background.setCornerRadius(dp(6));
        card.setBackground(background);
    }

    private void toggle(Panel panel, int position) {
        if (position < 0 || position >= panel.entries.size()) {
            return;
        }
        File file = panel.entries.get(position);
        String key = file.getAbsolutePath();
        if (!panel.selected.remove(key)) {
            panel.selected.add(key);
        }
        panel.adapter.notifyDataSetChanged();
        paintFocus();
    }

    private void openDirectory(Panel panel, File folder) {
        if (folder == null || !folder.isDirectory()) {
            return;
        }
        if (!folder.canRead()) {
            toast("No access to " + folder.getName());
            return;
        }
        panel.dir = folder;
        panel.selected.clear();
        refresh(panel);
        paintFocus();
    }

    private void goUp(Panel panel) {
        File parent = panel.dir == null ? null : panel.dir.getParentFile();
        if (parent == null || !parent.canRead()) {
            showShortcuts(panel);
            return;
        }
        panel.dir = parent;
        panel.selected.clear();
        refresh(panel);
        paintFocus();
    }

    private void editPath(final Panel panel) {
        final EditText input = new EditText(this);
        input.setTypeface(Typeface.MONOSPACE);
        input.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f);
        input.setText(panel.dir == null ? "" : panel.dir.getAbsolutePath());
        input.setPadding(dp(12), dp(8), dp(12), dp(8));

        new AlertDialog.Builder(this)
                .setTitle(panel.isTop ? "Top panel folder" : "Bottom panel folder")
                .setView(input)
                .setPositiveButton("Open", new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        File wanted = new File(input.getText().toString().trim());
                        if (!wanted.isDirectory()) {
                            toast("Not a folder: " + wanted.getPath());
                            return;
                        }
                        if (!wanted.canRead()) {
                            toast("Not readable — grant storage access");
                            return;
                        }
                        panel.dir = wanted;
                        panel.selected.clear();
                        refresh(panel);
                        paintFocus();
                    }
                })
                .setNegativeButton("Cancel", null)
                .show();
    }

    private void showShortcuts(final Panel panel) {
        final List<File> places = new ArrayList<>();
        final List<String> names = new ArrayList<>();
        File shared = Environment.getExternalStorageDirectory();
        addPlace(places, names, "Phone storage  /sdcard", shared);
        addPlace(places, names, "Downloads", Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOWNLOADS));
        addPlace(places, names, "DCIM (camera)", Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DCIM));
        addPlace(places, names, "Pictures", Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_PICTURES));
        addPlace(places, names, "Music", Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_MUSIC));
        addPlace(places, names, "Documents", Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOCUMENTS));
        if (shared != null) {
            addPlace(places, names, "Android/data", new File(shared, "Android/data"));
            addPlace(places, names, "shared  (TwinPane)", new File(shared, "TwinPane"));
        }
        // Ready for when the Termux panel is wired in: show it, say why if not.
        addPlace(places, names, "Termux home  ~",
                new File("/data/data/com.termux/files/home"));
        addPlace(places, names, "This app's files", getFilesDir());

        new AlertDialog.Builder(this)
                .setTitle((panel.isTop ? "Top" : "Bottom") + " panel → jump to")
                .setItems(names.toArray(new String[0]), new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        File place = places.get(which);
                        if (!place.isDirectory()) {
                            toast("Does not exist on this phone");
                            return;
                        }
                        if (!place.canRead()) {
                            toast("Permission denied — Android blocks this path");
                            return;
                        }
                        panel.dir = place;
                        panel.selected.clear();
                        refresh(panel);
                        paintFocus();
                    }
                })
                .setPositiveButton("Grant full access", new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        requestStorage();
                    }
                })
                .setNegativeButton("Close", null)
                .show();
    }

    private void addPlace(List<File> places, List<String> names, String label, File folder) {
        if (folder == null) {
            return;
        }
        places.add(folder);
        names.add(label + (folder.canRead() ? "" : "   (no access)"));
    }

    // ══════════════════════════════════════════════════════════════ transfer

    private void startTransfer(final boolean move) {
        if (transferRunning) {
            toast("Already working…");
            return;
        }
        final Panel source = active;
        final Panel target = active == top ? bottom : top;
        if (source.selected.isEmpty()) {
            toast("Tick some items first");
            return;
        }
        if (target.dir == null || !target.dir.canWrite()) {
            toast("Cannot write into " + (target.dir == null ? "?" : target.dir.getName())
                    + " — grant storage access");
            return;
        }
        if (hasSharedAccess() == false) {
            toast("Android is blocking storage — tap the bottom bar");
            return;
        }

        final List<File> items = new ArrayList<>();
        for (String path : source.selected) {
            items.add(new File(path));
        }

        int conflicts = 0;
        for (File item : items) {
            if (new File(target.dir, item.getName()).exists()) {
                conflicts++;
            }
        }
        if (conflicts == 0) {
            runTransfer(items, target.dir, move, 0, source, target);
            return;
        }

        final String[] choices = {"Overwrite all", "Skip existing", "Keep both", "Cancel"};
        new AlertDialog.Builder(this)
                .setTitle(conflicts + (conflicts == 1 ? " item already exists"
                        : " items already exist"))
                .setItems(choices, new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        if (which == 3) {
                            return;
                        }
                        runTransfer(items, target.dir, move, which, source, target);
                    }
                })
                .show();
    }

    private void runTransfer(final List<File> items, final File targetDir,
                             final boolean move, final int mode,
                             final Panel source, final Panel target) {
        transferRunning = true;
        transferCancelled = false;

        transferText = new TextView(this);
        transferText.setTypeface(Typeface.MONOSPACE);
        transferText.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f);
        transferText.setTextColor(Color.parseColor("#d7dee8"));
        transferText.setPadding(dp(16), dp(12), dp(16), dp(12));
        transferText.setText(readyMessage(items.size()));

        transferDialog = new AlertDialog.Builder(this)
                .setTitle(move ? "Moving" : "Copying")
                .setView(transferText)
                .setNegativeButton("Cancel", new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        transferCancelled = true;
                    }
                })
                .create();
        transferDialog.setCancelable(false);
        transferDialog.show();

        final File destination = targetDir;
        Thread worker = new Thread(new Runnable() {
            @Override
            public void run() {
                int done = 0;
                int skipped = 0;
                final List<String> problems = new ArrayList<>();
                for (File item : items) {
                    if (transferCancelled) {
                        break;
                    }
                    setTransferText("working on  " + item.getName());
                    try {
                        int result = transferOne(item, destination, move, mode);
                        if (result == 1) {
                            skipped++;
                        } else {
                            done++;
                        }
                    } catch (Exception error) {
                        problems.add(item.getName() + "  —  " + error.getMessage());
                    }
                }
                final int finished = done;
                final int left = skipped;
                runOnUiThread(new Runnable() {
                    @Override
                    public void run() {
                        if (transferDialog != null && transferDialog.isShowing()) {
                            transferDialog.dismiss();
                        }
                        transferRunning = false;
                        transferCancelled = false;
                        refresh(source);
                        refresh(target);
                        paintFocus();
                        String summary = (move ? "Moved " : "Copied ") + finished
                                + (left > 0 ? " · skipped " + left : "")
                                + (problems.isEmpty() ? "" : " · " + problems.size() + " failed");
                        statusLabel.setText(" " + summary);
                        toast(summary);
                        if (!problems.isEmpty()) {
                            showProblems(problems);
                        }
                    }
                });
            }
        });
        worker.setDaemon(true);
        worker.start();
    }

    private String readyMessage(int count) {
        return count + (count == 1 ? " item" : " items") + " queued";
    }

    private void setTransferText(final String message) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                if (transferText != null) {
                    transferText.setText(message);
                }
            }
        });
    }

    private void showProblems(List<String> problems) {
        StringBuilder body = new StringBuilder();
        int limit = Math.min(problems.size(), 8);
        for (int i = 0; i < limit; i++) {
            body.append("• ").append(problems.get(i)).append('\n');
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
     * Moves or copies one item into {@code targetDir}.
     *
     * @return 0 when written, 1 when deliberately skipped
     */
    private int transferOne(File item, File targetDir, boolean move, int mode)
            throws IOException {
        File destination = new File(targetDir, item.getName());

        // Refuse the two ways this could eat data.
        if (item.isDirectory() && isInside(targetDir, item)) {
            throw new IOException("cannot " + (move ? "move" : "copy")
                    + " a folder into itself");
        }
        File parent = item.getParentFile();
        if (parent != null && parent.equals(targetDir) && mode != 2) {
            return 1;                                     // already in this folder
        }

        if (destination.exists()) {
            if (mode == 1) {
                return 1;                                 // skip existing
            }
            if (mode == 2) {
                destination = uniqueName(targetDir, item.getName());
            } else {
                deleteRecursive(destination);
            }
        }

        if (move) {
            if (item.renameTo(destination)) {
                return 0;                                 // same filesystem: instant
            }
        }
        copyRecursive(item, destination);
        if (move) {
            if (!deleteRecursive(item)) {
                throw new IOException("copied, but could not remove the original");
            }
        }
        return 0;
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
        int counter = 2;
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
                return;                                   // nothing readable inside
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
                    if (transferCancelled) {
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
                .setTitle("New folder in " + shortPath(panel.dir))
                .setView(input)
                .setPositiveButton("Create", new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        String name = input.getText().toString().trim();
                        if (name.isEmpty()) {
                            return;
                        }
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
                        int removed = 0;
                        for (String path : new ArrayList<>(panel.selected)) {
                            if (deleteRecursive(new File(path))) {
                                removed++;
                            }
                        }
                        panel.selected.clear();
                        refresh(panel);
                        paintFocus();
                        toast("Deleted " + removed);
                    }
                })
                .setNegativeButton("Cancel", null)
                .show();
    }

    private void showEntryOptions(final Panel panel, int position) {
        if (position < 0 || position >= panel.entries.size()) {
            return;
        }
        final File file = panel.entries.get(position);
        final String[] options = file.isDirectory()
                ? new String[]{"Tick / untick", "Open folder", "Show details"}
                : new String[]{"Tick / untick", "Show details"};
        new AlertDialog.Builder(this)
                .setTitle(file.getName())
                .setItems(options, new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        if (which == 0) {
                            toggle(panel, panel.entries.indexOf(file));
                        } else if (which == 1 && file.isDirectory()) {
                            openDirectory(panel, file);
                        } else {
                            showDetails(file);
                        }
                    }
                })
                .show();
    }

    private void showDetails(File file) {
        String body = "size     : " + readableSize(file.length())
                + "\npath     : " + file.getAbsolutePath()
                + "\nwritable : " + (file.canWrite() ? "yes" : "no")
                + "\nparent   : " + (file.getParentFile() == null
                ? "—" : file.getParentFile().getAbsolutePath());
        new AlertDialog.Builder(this)
                .setTitle(file.getName())
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
