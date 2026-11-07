/*
 * Норка на рабочем столе. Дышит, на клик подпрыгивает и что-нибудь говорит,
 * ночью спит, при сильной нагрузке на процессор потеет.
 * Сочетание клавиш виджета (по умолчанию Meta+N) открывает чат с Норкой-помощником.
 * Спрятать Норку можно правым кликом или в Норка Центре, это помнится после перезагрузки
 */
import QtQuick
import QtMultimedia
import org.kde.kirigami as Kirigami
import org.kde.ksysguard.sensors as Sensors
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    readonly property bool shown: !Plasmoid.configuration.hidden
    property int hour: new Date().getHours()
    readonly property bool sleepy: hour >= 23 || hour < 7
    readonly property bool hot: cpu.value > 80

    readonly property var phrases: [
        i18n("Hi! I'm Norka."),
        i18n("Press Meta+N to talk to me."),
        i18n("Is it snack time yet?"),
        i18n("Your files are safe in my burrow."),
        i18n("I like it when you click me."),
        i18n("Try a right click on the desktop."),
    ]

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: fullRepresentation

    Connections {
        target: Plasmoid
        function onActivated() {
            launcher.connectSource("norka-chat")
        }
    }

    // Запуск окна чата: скрипт norka-chat сам следит, чтобы окно было одно
    P5Support.DataSource {
        id: launcher
        engine: "executable"
        onNewData: (sourceName) => disconnectSource(sourceName)
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Talk to Norka")
            icon.name: "dialog-messages"
            onTriggered: launcher.connectSource("norka-chat")
        },
        PlasmaCore.Action {
            text: i18n("Hide Norka")
            icon.name: "view-hidden"
            onTriggered: Plasmoid.configuration.hidden = true
        }
    ]

    // Место на рабочем столе хранится в пикселях от левого верхнего угла, поэтому при смене разрешения
    // (полный экран, другой монитор) Норка уезжала. Прижимаем её к правому нижнему углу свободной области,
    // пока её не перетащили руками
    property Item container: null
    readonly property rect freeArea: Plasmoid.containment ? Plasmoid.containment.availableScreenRect : Qt.rect(0, 0, 0, 0)

    function findContainer() {
        for (let item = root.parent; item; item = item.parent) {
            if (item.layout !== undefined && item.dragActive !== undefined) {
                return item
            }
        }
        return null
    }

    function snapToCorner() {
        if (!container) {
            container = findContainer()
        }
        if (!container || !Plasmoid.configuration.stickToCorner || freeArea.width <= 0) {
            return
        }
        const margin = Kirigami.Units.gridUnit
        const x = Math.round(freeArea.x + freeArea.width - container.width - margin)
        const y = Math.round(freeArea.y + freeArea.height - container.height - margin)
        // Рабочий стол округляет позицию до своей сетки, поэтому мелкую разницу не трогаем
        const tolerance = Kirigami.Units.gridUnit * 2
        if (Math.abs(container.x - x) > tolerance || Math.abs(container.y - y) > tolerance) {
            // Контейнер переезжает с анимацией, а рабочий стол запоминает позицию для каждого разрешения
            container.x = x
            container.y = y
            container.layout.save()
        }
    }

    onFreeAreaChanged: snapTimer.restart()

    // Рабочий стол раскладывает виджеты после смены разрешения с задержкой, поэтому прижимаемся дважды
    Timer {
        id: snapTimer
        interval: 300
        onTriggered: {
            root.snapToCorner()
            snapAgain.restart()
        }
    }
    Timer {
        id: snapAgain
        interval: 1500
        onTriggered: root.snapToCorner()
    }

    Component.onCompleted: {
        container = findContainer()
        snapTimer.restart()
    }

    Connections {
        target: root.container
        function onDragActiveChanged() {
            // Перетащили мышью: дальше стоит там, куда поставили
            if (!root.container.dragActive) {
                Plasmoid.configuration.stickToCorner = false
            }
        }
        function onWidthChanged() { snapTimer.restart() }
        function onHeightChanged() { snapTimer.restart() }
        // Рабочий стол сам переставил виджет (новое разрешение): возвращаем в угол
        function onXChanged() { if (!root.container.dragActive) snapTimer.restart() }
        function onYChanged() { if (!root.container.dragActive) snapTimer.restart() }
    }

    // Писк из звуковой темы NorkaOS, тихо: Норка стесняется
    MediaPlayer {
        id: squeakSound
        source: "file:///usr/share/sounds/norkaos/stereo/norka-squeak.oga"
        audioOutput: AudioOutput { volume: 0.5 }
    }

    Sensors.Sensor {
        id: cpu
        sensorId: "cpu/all/usage"
        updateRateLimit: 3000
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.hour = new Date().getHours()
    }

    fullRepresentation: Item {
        id: stage

        implicitWidth: Kirigami.Units.gridUnit * 10
        implicitHeight: Kirigami.Units.gridUnit * 22

        Image {
            id: norka

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            height: parent.height - bubble.height - Kirigami.Units.largeSpacing
            width: parent.width
            source: Qt.resolvedUrl("../images/shy.png")
            fillMode: Image.PreserveAspectFit
            verticalAlignment: Image.AlignBottom
            smooth: true
            mipmap: true
            opacity: root.shown ? (root.sleepy ? 0.85 : 1) : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation { duration: Kirigami.Units.longDuration * 2 }
            }

            transform: [
                Scale {
                    id: breath
                    origin.x: norka.width / 2
                    origin.y: norka.height
                },
                Translate {
                    id: hop
                }
            ]

            // Дыхание: во сне медленнее и глубже
            SequentialAnimation {
                running: norka.visible
                loops: Animation.Infinite
                NumberAnimation {
                    target: breath; property: "yScale"; from: 1; to: root.sleepy ? 1.025 : 1.012
                    duration: root.sleepy ? 2600 : 1700; easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    target: breath; property: "yScale"; to: 1
                    duration: root.sleepy ? 2600 : 1700; easing.type: Easing.InOutSine
                }
            }

            // Перегрев: мелкая дрожь
            SequentialAnimation {
                running: root.hot && norka.visible
                loops: Animation.Infinite
                NumberAnimation { target: hop; property: "x"; to: 2; duration: 60 }
                NumberAnimation { target: hop; property: "x"; to: -2; duration: 120 }
                NumberAnimation { target: hop; property: "x"; to: 0; duration: 60 }
                PauseAnimation { duration: 900 }
            }

            SequentialAnimation {
                id: jump
                ParallelAnimation {
                    NumberAnimation { target: hop; property: "y"; to: -Kirigami.Units.gridUnit * 1.5; duration: 180; easing.type: Easing.OutQuad }
                    NumberAnimation { target: breath; property: "xScale"; to: 0.96; duration: 180 }
                }
                ParallelAnimation {
                    NumberAnimation { target: hop; property: "y"; to: 0; duration: 260; easing.type: Easing.OutBounce }
                    NumberAnimation { target: breath; property: "xScale"; to: 1; duration: 260 }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.sleepy) {
                        bubble.say(i18n("Zzz… five more minutes…"))
                        return
                    }
                    jump.restart()
                    squeakSound.stop()
                    squeakSound.play()
                    bubble.say(root.hot ? i18n("It's so hot in here! Your computer is working hard.")
                                        : root.phrases[Math.floor(Math.random() * root.phrases.length)])
                }
            }
        }

        // Значки состояния над головой
        Text {
            id: status
            anchors.horizontalCenter: norka.horizontalCenter
            anchors.horizontalCenterOffset: norka.paintedWidth * 0.3
            y: norka.y + norka.height - norka.paintedHeight - height * 0.3
            visible: norka.visible && (root.sleepy || root.hot)
            text: root.sleepy ? "💤" : "💦"
            font.pixelSize: Kirigami.Units.gridUnit * 1.6

            transform: Translate { id: drift }

            SequentialAnimation {
                loops: Animation.Infinite
                running: status.visible
                NumberAnimation { target: drift; property: "y"; from: 0; to: -8; duration: 1200; easing.type: Easing.InOutSine }
                NumberAnimation { target: drift; property: "y"; from: -8; to: 0; duration: 1200; easing.type: Easing.InOutSine }
            }
        }

        Rectangle {
            id: bubble

            function say(text) {
                label.text = text
                opacity = 1
                hide.restart()
            }

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: Math.min(parent.width, label.implicitWidth + Kirigami.Units.largeSpacing * 2)
            height: label.implicitHeight + Kirigami.Units.largeSpacing * 2
            radius: Kirigami.Units.cornerRadius * 2
            color: Kirigami.Theme.backgroundColor
            border.color: Kirigami.Theme.highlightColor
            border.width: 1
            opacity: 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation { duration: Kirigami.Units.longDuration }
            }

            Text {
                id: label
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                color: Kirigami.Theme.textColor
                font: Kirigami.Theme.defaultFont
            }

            Timer {
                id: hide
                interval: 4000
                onTriggered: bubble.opacity = 0
            }
        }
    }
}
