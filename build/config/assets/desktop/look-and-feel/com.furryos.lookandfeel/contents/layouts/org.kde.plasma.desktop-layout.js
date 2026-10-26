// FurryOS default desktop layout.
//
// Applied by Plasma when the FurryOS look-and-feel package is active (and by
// /etc/skel on first login). It is a stock Breeze-style layout: a top panel
// with the application launcher, menus, system tray and clock, plus an
// icons-only task manager at the bottom. Nothing here is upstream brand
// material — only Breeze's own widgets and arrangement.

var panel = new Panel
var panelScreen = panel.screen

panel.height = 2 * Math.floor(gridUnit * 2.5 / 2)
panel.location = "top"

// Restrict horizontal panel to a maximum size on ultra-wide monitors.
const maximumAspectRatio = 21 / 9;
if (panel.formFactor === "horizontal") {
    const geo = screenGeometry(panelScreen);
    const maximumWidth = Math.ceil(geo.height * maximumAspectRatio);

    if (geo.width > maximumWidth) {
        panel.alignment = "center";
        panel.minimumLength = maximumWidth;
        panel.maximumLength = maximumWidth;
    }
}

var kickoff = panel.addWidget("org.kde.plasma.kickoff")
kickoff.currentConfigGroup = ["Shortcuts"]
kickoff.writeConfig("global", "Alt+F1")

panel.addWidget("org.kde.plasma.panelspacer")
panel.addWidget("org.kde.plasma.marginsseparator")
panel.addWidget("org.kde.plasma.systemtray")
panel.addWidget("org.kde.plasma.marginsseparator")
panel.addWidget("org.kde.plasma.digitalclock")
panel.addWidget("org.kde.plasma.showdesktop")

var taskPanel = new Panel
taskPanel.location = "bottom"
taskPanel.lengthMode = "fit"
taskPanel.height = 2 * Math.floor(gridUnit * 2.5 / 2)

var tasks = taskPanel.addWidget("org.kde.plasma.icontasks")
tasks.currentConfigGroup = ["General"]
tasks.writeConfig("launchers", [
    "applications:org.kde.dolphin.desktop",
    "applications:org.kde.konsole.desktop",
    "applications:systemsettings.desktop",
])
