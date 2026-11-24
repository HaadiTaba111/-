// The phone end of the Termux bridge.
//
// Termux can read both its own home and /sdcard; this app can only read
// /sdcard. So whenever a file has to cross that boundary, the only program that
// can do it is the one inside Termux. This class talks to it through a folder
// both sides can see (shared storage), using one JSON file per request:
//
//     <bridge>/requests/<id>.json   we write what we want
//     <bridge>/results/<id>.json    the worker writes the outcome
//     <bridge>/worker.json          a heartbeat, so we know it is alive
//
// No sockets, no ports, no root, and nothing to keep running in Termux unless
// the user wants the background service.
package com.twinpane.explorer;

import android.os.Environment;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.atomic.AtomicLong;

public final class TermuxBridge {

    /** How long to wait for a worker to answer before giving up. */
    private static final long TIMEOUT_MS = 20000;
    private static final long POLL_MS = 120;

    private static final AtomicLong COUNTER = new AtomicLong();

    /** One row the worker reported. */
    public static final class Item {
        public final String name;
        public final String path;
        public final boolean dir;
        public final long size;
        public final long mtime;

        Item(String name, String path, boolean dir, long size, long mtime) {
            this.name = name;
            this.path = path;
            this.dir = dir;
            this.size = size;
            this.mtime = mtime;
        }
    }

    /** A listing plus the shortcuts the worker knows about. */
    public static final class Listing {
        public String path;
        public String parent;
        public final List<Item> items = new ArrayList<>();
        public final List<String[]> places = new ArrayList<>();
        public final List<String> errors = new ArrayList<>();
        public String failure;
    }

    /** The outcome of a copy / move / delete / mkdir. */
    public static final class Outcome {
        public boolean ok;
        public String error;
        public String summary;
        public int files;
        public int dirs;
        public long bytes;
        public int skipped;
        public final List<String> problems = new ArrayList<>();
    }

    private TermuxBridge() {
    }

    // ------------------------------------------------------------------ paths

    /** ``/sdcard/TwinPane/bridge`` - the folder Termux also writes to. */
    public static File bridgeDir() {
        File shared = Environment.getExternalStorageDirectory();
        return new File(new File(shared, "TwinPane"), "bridge");
    }

    private static File requestsDir() {
        return new File(bridgeDir(), "requests");
    }

    private static File resultsDir() {
        return new File(bridgeDir(), "results");
    }

    /**
     * True when a worker has written a heartbeat recently enough to trust.
     * A stale heartbeat means "Termux is not running right now", which the UI
     * shows plainly instead of pretending the call worked.
     */
    public static boolean workerAlive() {
        File beat = new File(bridgeDir(), "worker.json");
        if (!beat.isFile()) {
            return false;
        }
        JSONObject object = readJson(beat);
        if (object == null) {
            return false;
        }
        // The worker touches this file on every poll, so a heartbeat older than
        // a couple of minutes means it has stopped.
        return System.currentTimeMillis() - beat.lastModified() < 150000;
    }

    /**
     * Which link in the chain is broken, in plain words.
     *
     * <p>This exists because "it does not work" cost a whole evening once. The
     * four things that can be wrong are checked in order, and the first one
     * that is wrong is the only thing the user is told.
     */
    public static final class Diagnosis {
        public final String what;
        public final String fix;

        Diagnosis(String what, String fix) {
            this.what = what;
            this.fix = fix;
        }

        public boolean isReady() {
            return fix == null;
        }
    }

    public static Diagnosis diagnose() {
        File shared = Environment.getExternalStorageDirectory();
        if (shared == null || !shared.canRead() || shared.list() == null) {
            return new Diagnosis("This app cannot read the phone's storage.",
                    "Grant \"All files access\" to Twin-Pane, then come back.");
        }
        File bridge = bridgeDir();
        File requests = new File(bridge, "requests");
        if (!bridge.isDirectory() && !bridge.mkdirs()) {
            return new Diagnosis("The bridge folder could not be created.",
                    "Create it by hand in Termux: mkdir -p /sdcard/TwinPane/bridge");
        }
        if (!requests.isDirectory() && !requests.mkdirs()) {
            return new Diagnosis("The bridge folder has no requests/ subfolder.",
                    "In Termux: mkdir -p /sdcard/TwinPane/bridge/{requests,work,results}");
        }
        File beat = new File(bridge, "worker.json");
        if (!beat.isFile()) {
            return new Diagnosis("The Termux worker has never run.",
                    "Open Termux and run:  twinpane-bridge");
        }
        long age = System.currentTimeMillis() - beat.lastModified();
        if (age > 150000) {
            long minutes = age / 60000;
            return new Diagnosis("The Termux worker stopped " + minutes
                    + " minute" + (minutes == 1 ? "" : "s") + " ago.",
                    "Open Termux and run:  twinpane-bridge\n\n"
                            + "To keep it alive, run:  termux-wake-lock");
        }
        return new Diagnosis(null, null);
    }

    /** Where Termux's own home is, as reported by the worker (or guessed). */
    public static String termuxHome() {
        JSONObject beat = readJson(new File(bridgeDir(), "worker.json"));
        if (beat != null) {
            String home = beat.optString("home", "");
            if (!home.isEmpty()) {
                return home;
            }
        }
        return "/data/data/com.termux/files/home";
    }

    // ------------------------------------------------------------------- call

    /**
     * Send one request and wait for its answer. Must not run on the UI thread.
     *
     * @return the parsed result, or null when nothing answered in time
     */
    private static JSONObject call(JSONObject request) throws IOException {
        File requests = requestsDir();
        File results = resultsDir();
        if (!requests.isDirectory() && !requests.mkdirs()) {
            throw new IOException("cannot create " + requests);
        }
        if (!results.isDirectory() && !results.mkdirs()) {
            throw new IOException("cannot create " + results);
        }

        String id = newId();
        try {
            request.put("id", id);
        } catch (JSONException error) {
            throw new IOException("cannot build the request: " + error.getMessage());
        }

        File temporary = new File(requests, id + ".json.tmp");
        File finalName = new File(requests, id + ".json");
        writeJson(temporary, request);
        // Publish atomically: the worker only ever sees a complete file.
        if (!temporary.renameTo(finalName)) {
            throw new IOException("cannot publish the request");
        }

        File answer = new File(results, id + ".json");
        long deadline = System.currentTimeMillis() + TIMEOUT_MS;
        while (System.currentTimeMillis() < deadline) {
            if (answer.isFile()) {
                JSONObject parsed = readJson(answer);
                //noinspection ResultOfMethodCallIgnored
                answer.delete();
                removeStaleRequest(finalName);
                return parsed;
            }
            try {
                Thread.sleep(POLL_MS);
            } catch (InterruptedException interrupted) {
                Thread.currentThread().interrupt();
                return null;
            }
        }
        // Leave the request alone: a worker that starts later can still do the
        // work, which is better than losing the user's instruction.
        return null;
    }

    private static void removeStaleRequest(File request) {
        if (request.isFile()) {
            //noinspection ResultOfMethodCallIgnored
            request.delete();
        }
    }

    private static String newId() {
        return String.format(Locale.US, "%d-%d",
                System.currentTimeMillis(), COUNTER.incrementAndGet());
    }

    // ------------------------------------------------------------- operations

    /** Ask the worker for a folder listing. */
    public static Listing list(String path, boolean showHidden) {
        Listing listing = new Listing();
        listing.path = path;
        JSONObject request = new JSONObject();
        try {
            request.put("op", "list");
            request.put("path", path);
            request.put("hidden", showHidden);
            JSONObject result = call(request);
            if (result == null) {
                listing.failure = "Termux did not answer — is the worker running?";
                return listing;
            }
            if (!result.optBoolean("ok", false)) {
                listing.failure = result.optString("error", "the worker refused");
                return listing;
            }
            listing.path = result.optString("path", path);
            listing.parent = result.optString("parent", null);
            JSONArray rows = result.optJSONArray("entries");
            if (rows != null) {
                for (int index = 0; index < rows.length(); index++) {
                    JSONObject row = rows.optJSONObject(index);
                    if (row == null) {
                        continue;
                    }
                    listing.items.add(new Item(
                            row.optString("name"),
                            row.optString("path"),
                            row.optBoolean("dir"),
                            row.optLong("size"),
                            row.optLong("mtime")));
                }
            }
            JSONArray shortcuts = result.optJSONArray("places");
            if (shortcuts != null) {
                for (int index = 0; index < shortcuts.length(); index++) {
                    JSONObject shortcut = shortcuts.optJSONObject(index);
                    if (shortcut != null) {
                        listing.places.add(new String[]{
                                shortcut.optString("label"),
                                shortcut.optString("path")});
                    }
                }
            }
            JSONArray problems = result.optJSONArray("errors");
            if (problems != null) {
                for (int index = 0; index < problems.length(); index++) {
                    listing.errors.add(problems.optString(index));
                }
            }
        } catch (JSONException | IOException error) {
            listing.failure = String.valueOf(error.getMessage());
        }
        return listing;
    }

    /** copy or move {@code items} into {@code destination}. */
    public static Outcome transfer(String mode, List<String> items,
                                   String destination, String conflict) {
        Outcome outcome = new Outcome();
        if (items == null || items.isEmpty()) {
            outcome.error = "nothing selected";
            return outcome;
        }
        JSONObject request = new JSONObject();
        try {
            request.put("op", "move".equals(mode) ? "move" : "copy");
            request.put("dest", destination);
            request.put("conflict", conflict == null ? "rename" : conflict);
            JSONArray list = new JSONArray();
            for (String item : items) {
                list.put(item);
            }
            request.put("items", list);
            JSONObject result = call(request);
            fillOutcome(outcome, result);
        } catch (JSONException | IOException error) {
            outcome.error = String.valueOf(error.getMessage());
        }
        return outcome;
    }

    /** Remove {@code items} (folders go recursively). */
    public static Outcome delete(List<String> items) {
        Outcome outcome = new Outcome();
        JSONObject request = new JSONObject();
        try {
            request.put("op", "delete");
            JSONArray list = new JSONArray();
            for (String item : items) {
                list.put(item);
            }
            request.put("items", list);
            fillOutcome(outcome, call(request));
        } catch (JSONException | IOException error) {
            outcome.error = String.valueOf(error.getMessage());
        }
        return outcome;
    }

    /** Create a folder inside {@code parent}. */
    public static Outcome makeFolder(String parent, String name) {
        Outcome outcome = new Outcome();
        JSONObject request = new JSONObject();
        try {
            request.put("op", "mkdir");
            request.put("path", parent);
            request.put("name", name);
            fillOutcome(outcome, call(request));
        } catch (JSONException | IOException error) {
            outcome.error = String.valueOf(error.getMessage());
        }
        return outcome;
    }

    private static void fillOutcome(Outcome outcome, JSONObject result) {
        if (result == null) {
            outcome.error = "Termux did not answer — is the worker running?";
            return;
        }
        outcome.ok = result.optBoolean("ok", false);
        outcome.error = result.optString("error", null);
        outcome.summary = result.optString("summary", "");
        outcome.files = result.optInt("files", 0);
        outcome.dirs = result.optInt("dirs", 0);
        outcome.bytes = result.optLong("bytes", 0);
        outcome.skipped = result.optInt("skipped", 0);
        JSONArray problems = result.optJSONArray("errors");
        if (problems != null) {
            for (int index = 0; index < problems.length(); index++) {
                outcome.problems.add(problems.optString(index));
            }
        }
        if (!outcome.ok && outcome.error == null) {
            outcome.error = "the worker reported a failure";
        }
    }

    // ------------------------------------------------------------------- json

    private static void writeJson(File target, JSONObject object) throws IOException {
        File folder = target.getParentFile();
        if (folder != null && !folder.isDirectory() && !folder.mkdirs()) {
            throw new IOException("cannot create " + folder);
        }
        try (OutputStream out = new FileOutputStream(target)) {
            out.write(object.toString().getBytes("UTF-8"));
        }
    }

    private static JSONObject readJson(File source) {
        if (!source.isFile()) {
            return null;
        }
        try (InputStream in = new FileInputStream(source)) {
            byte[] buffer = new byte[(int) Math.min(source.length() + 16, 1 << 20)];
            int read = 0;
            int count;
            while (read < buffer.length
                    && (count = in.read(buffer, read, buffer.length - read)) > 0) {
                read += count;
            }
            return new JSONObject(new String(buffer, 0, read, "UTF-8"));
        } catch (IOException | JSONException error) {
            return null;
        }
    }
}
