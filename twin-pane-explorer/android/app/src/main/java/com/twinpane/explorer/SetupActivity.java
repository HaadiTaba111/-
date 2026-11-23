// Handles the "allow this app to run commands in Termux" request.
//
// Android shows the permission dialog itself; this activity only exists so the
// request has an Activity to come back to. On success we immediately hand over
// to the terminal.
package com.twinpane.explorer;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.widget.Toast;

public class SetupActivity extends Activity {

    private static final int REQUEST_RUN_COMMAND = 7;
    private String termuxPackage = "com.termux";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        String extra = getIntent().getStringExtra("termux");
        if (extra != null) {
            termuxPackage = extra;
        }
        requestPermissions(new String[]{"com.termux.permission.RUN_COMMAND"},
                REQUEST_RUN_COMMAND);
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions,
                                           int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQUEST_RUN_COMMAND) {
            boolean granted = grantResults.length > 0
                    && grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED;
            Toast.makeText(this,
                    granted ? "Ready - opening Twin-Pane"
                            : "Permission denied - open Termux and enable allow-external-apps",
                    Toast.LENGTH_LONG).show();
            Intent next = new Intent(this, MainActivity.class);
            next.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
            startActivity(next);
            finish();
        }
    }
}
