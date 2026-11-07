// Первый вход: обои и временная панель, своя панель появится на этапе 4
var wallpaper = "file:///usr/share/wallpapers/NorkaOS/contents/images/3840x2160.png";

desktops().forEach(function (desktop) {
    desktop.wallpaperPlugin = "org.kde.image";
    desktop.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    desktop.writeConfig("Image", wallpaper);
    desktop.writeConfig("FillMode", 2);
});

var panel = new Panel;
panel.location = "bottom";
panel.height = 2 * Math.floor(gridUnit * 1.4);

var launcher = panel.addWidget("org.kde.plasma.kickoff");
launcher.currentConfigGroup = ["General"];
launcher.writeConfig("icon", "norkaos-symbolic");

panel.addWidget("org.kde.plasma.icontasks");
panel.addWidget("org.kde.plasma.marginsseparator");
panel.addWidget("org.kde.plasma.systemtray");
panel.addWidget("org.kde.plasma.digitalclock");
