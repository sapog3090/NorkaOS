// Первый вход: обои, Норка на рабочем столе и плавающая панель-док по центру
var wallpaper = "file:///usr/share/wallpapers/NorkaOS/contents/images/3840x2160.png";

desktops().forEach(function (desktop) {
    desktop.wallpaperPlugin = "org.kde.image";
    desktop.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    desktop.writeConfig("Image", wallpaper);
    desktop.writeConfig("FillMode", 2);
});

// Норка только на главном экране, в правом нижнем углу над панелью
var main = desktops()[0];
var screen = screenGeometry(main.screen);
var norkaWidth = gridUnit * 10;
var norkaHeight = gridUnit * 22;
var norka = main.addWidget("org.norkaos.mascot",
    screen.width - norkaWidth - gridUnit * 2,
    screen.height - norkaHeight - gridUnit * 6,
    norkaWidth, norkaHeight);
norka.globalShortcut = "Meta+N";

var panel = new Panel;
panel.location = "bottom";
panel.height = 2 * Math.floor(gridUnit * 1.4);
panel.floating = true;
panel.alignment = "center";
panel.lengthMode = "fit";

var launcher = panel.addWidget("org.norkaos.menu");
launcher.globalShortcut = "Alt+F1";

var tasks = panel.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", [
    "preferred://browser",
    "applications:org.kde.dolphin.desktop",
    "applications:kitty.desktop",
    "applications:systemsettings.desktop"
]);

panel.addWidget("org.kde.plasma.marginsseparator");
panel.addWidget("org.kde.plasma.systemtray");
panel.addWidget("org.kde.plasma.digitalclock");
