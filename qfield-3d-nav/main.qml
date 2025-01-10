import QtQuick
import QtQuick.Controls

import QtQuick3D
import QtMultimedia
import QtSensors

import org.qfield
import org.qgis
import Theme

Item {
    id: plugin

    property var mainWindow: iface.mainWindow()
    property var positionSource: iface.findItemByObjectName('positionSource')
    property var testPipesLayer: null
    property var testPipesFeatures: []

    property bool initiated: false
    property var points: []

    property var positions: []
    property var currentPosition: [0,0,0]
    property double currentOrientation: 0
    property double currentTilt: 90

    Component.onCompleted: {
        iface.addItemToPluginsToolbar(pluginButton)
        
        // Get the layer by name
        testPipesLayer = iface.layerUtils.layerById("test_pipes")
        
        if (testPipesLayer) {
            console.log("testPipesLayer loaded successfully:", testPipesLayer.name)
            loadPipeFeatures()
        } else {
            console.log("Error: testPipesLayer not found.")
        }
    }

    function loadPipeFeatures() {
        if (!testPipesLayer) return
        
        // Clear existing features
        testPipesFeatures = []
        
        // Get all features from the layer
        const features = testPipesLayer.getFeatures()
        for (let feature of features) {
            const geometry = feature.geometry()
            const attributes = feature.attributes()
            
            // Store feature data as needed
            testPipesFeatures.push({
                geometry: geometry,
                attributes: attributes
            })
            
            console.log("Loaded pipe feature:", attributes)
        }
    }

    function findNearestPipe(position) {
        if (!testPipesLayer || testPipesFeatures.length === 0) return null
        
        let nearestPipe = null
        let minDistance = Infinity
        
        for (let feature of testPipesFeatures) {
            const distance = calculateDistance(position, feature.geometry)
            if (distance < minDistance) {
                minDistance = distance
                nearestPipe = feature
            }
        }
        
        return nearestPipe
    }

    Connections {
        target: positionSource
        enabled: threeDNavigationPopup.visible

        function onProjectedPositionChanged() {
            if (positionSource.active && positionSource.positionInformation.longitudeValid && positionSource.positionInformation.latitudeValid) {
                plugin.positions.push(positionSource.projectedPosition)
                if (plugin.positions.length > 5) {
                    plugin.positions.shift()
                }

                let x = 0
                let y = 0
                for (const p of plugin.positions) {
                    x += p[0]
                    y += p[1]
                }
                x /= plugin.positions.length
                y /= plugin.positions.length

                plugin.currentPosition = [x, y, 0]

                // Find nearest pipe when position updates
                const nearestPipe = findNearestPipe(plugin.currentPosition)
                if (nearestPipe) {
                    console.log("Nearest pipe found:", nearestPipe.attributes)
                }
            }
        }
    }

    Button {
        id: pluginButton
        text: "3D Navigation"
        onClicked: {
            threeDNavigationPopup.visible = !threeDNavigationPopup.visible
        }
    }

    Popup {
        id: threeDNavigationPopup

        parent: mainWindow.contentItem
        width: Math.min(mainWindow.width, mainWindow.height) - 40
        height: width
        anchors.centerIn: parent
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        View3D {
            id: view3D
            anchors.fill: parent

            environment: SceneEnvironment {
                clearColor: "skyblue"
                backgroundMode: SceneEnvironment.Color
            }

            PerspectiveCamera {
                id: camera
                position: Qt.vector3d(0, 0, 600)
            }

            DirectionalLight {
                position: Qt.vector3d(-500, 500, -100)
                color: Qt.rgba(0.4, 0.2, 0.6, 1.0)
                ambientColor: Qt.rgba(0.1, 0.1, 0.1, 1.0)
            }
        }

        Text {
            id: orientationReadingText
            anchors.top: parent.top
            anchors.left: parent.left
            text: 'Orientation: ' + currentOrientation.toFixed(2)
        }

        Text {
            id: tiltReadingText
            anchors.top: orientationReadingText.bottom
            anchors.left: parent.left
            text: 'Tilt: ' + currentTilt.toFixed(2)
        }

        Text {
            id: gpsPositionText
            anchors.top: tiltReadingText.bottom
            anchors.left: parent.left
            text: 'GPS Position: ' + currentPosition[0] + ', ' + currentPosition[1]
        }
    }
}
