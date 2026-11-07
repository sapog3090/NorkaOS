/*
 * Меню NorkaOS: шапка с аватаром и поиском, закреплённые программы плиткой,
 * все программы списком, кнопки выключения. Данные берёт у Kicker, как штатное меню
 */
import QtQuick
import QtQuick.Layouts
import org.kde.coreaddons as KCoreAddons
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid
import org.kde.plasma.private.kicker as Kicker
import org.kde.plasma.private.sessions as Sessions

PlasmoidItem {
    id: root

    property Kicker.RootModel rootModel: Kicker.RootModel {
        autoPopulate: false
        appletInterface: root
        flat: true
        sorted: true
        showSeparators: false
        showTopLevelItems: true
        showAllApps: true
        showAllAppsCategorized: false
        showRecentApps: false
        showRecentDocs: false
        showPowerSession: false
        showFavoritesPlaceholder: false

        Component.onCompleted: {
            favoritesModel.initForClient("org.norkaos.menu.favorites.instance-" + Plasmoid.id)
            // Первый запуск: закреплённые программы по умолчанию из настроек виджета
            if (!Plasmoid.configuration.favoritesPortedToKAstats) {
                if (favoritesModel.count < 1) {
                    favoritesModel.portOldFavorites(Plasmoid.configuration.favorites)
                }
                Plasmoid.configuration.favoritesPortedToKAstats = true
            }
        }
    }

    // Все программы: строка корня с описанием KICKER_ALL_MODEL
    property var allAppsModel: null
    property string query: ""

    signal resetMenu

    function findAllApps() {
        for (let i = 0; i < rootModel.count; ++i) {
            const model = rootModel.modelForRow(i)
            if (model && model.description === "KICKER_ALL_MODEL") {
                allAppsModel = model
                return
            }
        }
    }

    function launch(model, row) {
        model.trigger(row, "", null)
        root.expanded = false
    }

    Plasmoid.icon: Plasmoid.configuration.icon

    onExpandedChanged: {
        if (root.expanded) {
            rootModel.refresh()
            findAllApps()
        } else {
            root.resetMenu()
        }
    }

    Kicker.RunnerModel {
        id: runnerModel
        appletInterface: root
        favoritesModel: root.rootModel.favoritesModel
        mergeResults: true
        query: root.query
    }

    Sessions.SessionManagement {
        id: session
    }

    KCoreAddons.KUser {
        id: user
    }

    fullRepresentation: FocusScope {
        id: menu

        property bool showAll: false

        Connections {
            target: root
            function onResetMenu() {
                search.text = ""
                menu.showAll = false
            }
        }

        Layout.preferredWidth: Kirigami.Units.gridUnit * 26
        Layout.preferredHeight: Kirigami.Units.gridUnit * 30
        focus: true

        Keys.onEscapePressed: root.expanded = false

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Kirigami.ShadowedImage {
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                    source: user.faceIconUrl.toString() !== "" ? user.faceIconUrl : Qt.resolvedUrl("../images/face.png")
                    fillMode: Image.PreserveAspectCrop
                    radius: width / 2
                    border.color: Kirigami.Theme.highlightColor
                    border.width: 2
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Kirigami.Heading {
                        Layout.fillWidth: true
                        level: 2
                        text: i18n("Hi, %1!", user.fullName || user.loginName)
                        elide: Text.ElideRight
                    }
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: i18n("What shall we do?")
                        opacity: 0.7
                    }
                }
            }

            PlasmaComponents.TextField {
                id: search
                Layout.fillWidth: true
                focus: true
                placeholderText: i18n("Search apps, files, settings…")
                clearButtonShown: true
                onTextChanged: {
                    root.query = text
                    results.currentIndex = 0
                }

                Keys.onReturnPressed: results.launchFirst()
                Keys.onEnterPressed: results.launchFirst()
                Keys.onDownPressed: results.focusList()
            }

            // Закреплённые программы
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: search.text === "" && !menu.showAll
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    Kirigami.Heading {
                        Layout.fillWidth: true
                        level: 4
                        text: i18n("Pinned")
                    }
                    PlasmaComponents.ToolButton {
                        text: i18n("All apps")
                        icon.name: "go-next"
                        LayoutMirroring.enabled: true
                        onClicked: menu.showAll = true
                    }
                }

                GridView {
                    id: pinned
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    cellWidth: Math.floor(width / 4)
                    cellHeight: Kirigami.Units.gridUnit * 5.5
                    model: root.rootModel.favoritesModel
                    delegate: Tile {
                        id: pinnedTile
                        width: pinned.cellWidth
                        height: pinned.cellHeight
                        onActivated: root.launch(pinned.model, pinnedTile.index)
                    }

                    // Норка выглядывает из-за правого края, пока плитки не заняли низ меню
                    Image {
                        parent: pinned
                        z: -1
                        anchors.right: parent.right
                        anchors.rightMargin: -Kirigami.Units.smallSpacing
                        anchors.bottom: parent.bottom
                        height: Math.min(Kirigami.Units.gridUnit * 11, parent.height - Math.ceil(pinned.count / 4) * pinned.cellHeight)
                        visible: height > Kirigami.Units.gridUnit * 5
                        source: Qt.resolvedUrl("../images/peek.png")
                        fillMode: Image.PreserveAspectFit
                        horizontalAlignment: Image.AlignRight
                        smooth: true
                        mipmap: true
                    }
                }
            }

            // Все программы или результаты поиска
            ListView {
                id: results

                function launchFirst() {
                    if (count > 0) {
                        root.launch(model, currentIndex >= 0 ? currentIndex : 0)
                    }
                }
                function focusList() {
                    forceActiveFocus()
                    currentIndex = 0
                }

                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: search.text !== "" || menu.showAll
                clip: true
                keyNavigationEnabled: true
                highlightMoveDuration: 0
                model: search.text !== "" ? (runnerModel.count > 0 ? runnerModel.modelForRow(0) : null) : root.allAppsModel
                highlight: Rectangle {
                    radius: Kirigami.Units.cornerRadius
                    color: Kirigami.Theme.highlightColor
                    opacity: 0.35
                }
                delegate: Item {
                    id: row

                    required property var model
                    required property int index

                    width: results.width
                    height: Kirigami.Units.gridUnit * 2.4

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Kirigami.Units.largeSpacing
                        anchors.rightMargin: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.largeSpacing

                        Kirigami.Icon {
                            Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                            source: row.model.decoration
                        }
                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: row.model.display
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: results.currentIndex = row.index
                        onClicked: root.launch(results.model, row.index)
                    }
                }

                Keys.onReturnPressed: launchFirst()
                Keys.onEnterPressed: launchFirst()

                PlasmaComponents.Label {
                    anchors.centerIn: parent
                    visible: search.text !== "" && results.count === 0 && !runnerModel.querying
                    text: i18n("Norka couldn't find anything")
                    opacity: 0.7
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.ToolButton {
                    visible: menu.showAll && search.text === ""
                    text: i18n("Back")
                    icon.name: "go-previous"
                    onClicked: menu.showAll = false
                }
                Item {
                    Layout.fillWidth: true
                }
                PlasmaComponents.ToolButton {
                    icon.name: "system-lock-screen"
                    visible: session.canLock
                    onClicked: { root.expanded = false; session.lock() }
                    PlasmaComponents.ToolTip.text: i18n("Lock")
                    PlasmaComponents.ToolTip.visible: hovered
                }
                PlasmaComponents.ToolButton {
                    icon.name: "system-log-out"
                    visible: session.canLogout
                    onClicked: { root.expanded = false; session.requestLogout() }
                    PlasmaComponents.ToolTip.text: i18n("Log out")
                    PlasmaComponents.ToolTip.visible: hovered
                }
                PlasmaComponents.ToolButton {
                    icon.name: "system-reboot"
                    visible: session.canReboot
                    onClicked: { root.expanded = false; session.requestReboot() }
                    PlasmaComponents.ToolTip.text: i18n("Restart")
                    PlasmaComponents.ToolTip.visible: hovered
                }
                PlasmaComponents.ToolButton {
                    icon.name: "system-shutdown"
                    visible: session.canShutdown
                    onClicked: { root.expanded = false; session.requestShutdown() }
                    PlasmaComponents.ToolTip.text: i18n("Shut down")
                    PlasmaComponents.ToolTip.visible: hovered
                }
            }
        }
    }

    // Плитка закреплённой программы: значок и подпись, при наведении подсветка
    component Tile: Item {
        id: tile

        required property var model
        required property int index

        signal activated

        Rectangle {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            radius: Kirigami.Units.cornerRadius * 2
            color: Kirigami.Theme.highlightColor
            opacity: tileArea.containsMouse ? 0.3 : 0

            Behavior on opacity {
                NumberAnimation { duration: Kirigami.Units.shortDuration }
            }
        }

        ColumnLayout {
            anchors.centerIn: parent
            width: parent.width - Kirigami.Units.largeSpacing * 2
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Kirigami.Units.iconSizes.large
                Layout.preferredHeight: Kirigami.Units.iconSizes.large
                source: tile.model.decoration
            }
            PlasmaComponents.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: tile.model.display
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
                font: Kirigami.Theme.smallFont
            }
        }

        MouseArea {
            id: tileArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.activated()
        }
    }
}
