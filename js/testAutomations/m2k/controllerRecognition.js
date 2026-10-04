// Read-only hardware smoke test. Does not connect instruments, calibrate, or Run.
scopy.startScan(true);
msleep(5000);
var devices = scopy.getDevicesName();
var found = false;
for (var i = 0; i < devices.length; ++i) {
    var plugins = scopy.getPlugins(i);
    print("Device " + devices[i] + ": " + plugins.join(", "));
    if (plugins.indexOf("M2kPlugin") !== -1) {
        found = true;
    }
}
scopy.startScan(false);
if (!found) {
    throw new Error("No ADALM2000 recognized by device-controller");
}
print("M2K device-controller recognition passed (no instrument outputs enabled)");
scopy.exit();
