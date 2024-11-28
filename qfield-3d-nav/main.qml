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

  property bool initiated: false
  property var points: []

  property var positions: []
  property var currentPosition: [0,0,0]
  property double currentOrientation: 0
  property double currentTilt: 90

  Component.onCompleted: {
    iface.addItemToPluginsToolbar(pluginButton)
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
          x += p.x
          y += p.y
        }
        x = x / plugin.positions.length
        y = y / plugin.positions.length
        plugin.currentPosition = [x, y, 0]

        if (!plugin.initiated) {
          plugin.initiated = true
          plugin.points = [
                [x + 5, y, 0],
                [x, y + 5, 0],
                [x - 5, y, 0],
                [x, y - 5, 0],
                [x, y, 5],
                [x, y, -5]
              ]
        }

        gpsPositionText.text = 'GPS Position: ' + x + ', ' + y
        gpsAccuracyText.text = 'Accuracy: ' + positionSource.positionInformation.horizontalAccuracy
      }
    }
  }

  QfToolButton {
    id: pluginButton
    iconSource: 'icon.svg'
    iconColor: "white"
    bgcolor: Theme.darkGray
    round: true

    onClicked: {
      threeDNavigationPopup.open();
    }
  }

  Popup {
    id: threeDNavigationPopup

    parent: mainWindow.contentItem
    width: Math.min(mainWindow.width, mainWindow.height) - 40
    height: width
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2

    onAboutToHide: {
      plugin.initiated = false
      plugin.points = []
      plugin.positions = []
    }

    onAboutToShow: {
      if (positionSource.active) {
        let x = positionSource.projectedPosition.x
        let y = positionSource.projectedPosition.y

        plugin.currentPosition = [x, y, 0]
        plugin.points = [
              [x + 5, y, 0],
              [x, y + 5, 0],
              [x - 5, y, 0],
              [x, y - 5, 0],
              [x, y, 5],
              [x, y, -5]
            ]

        gpsPositionText.text = 'GPS Position: ' + x + ', ' + y
        gpsAccuracyText.text = 'Accuracy: ' + positionSource.positionInformation.horizontalAccuracy
      }
    }

    CaptureSession {
      id: captureSession
      camera: Camera {
        active: threeDNavigationPopup.visible
        flashMode: Camera.FlashOff
      }
      videoOutput: videoOutput
    }

    VideoOutput {
      id: videoOutput
      width: 100
      height: 100
      anchors.fill: parent
      fillMode: VideoOutput.PreserveAspectCrop
    }

    View3D {
      anchors.fill: parent

      environment: SceneEnvironment {
              antialiasingMode: SceneEnvironment.ProgressiveAA
      }

      PointLight {
        position: Qt.vector3d(0, 0, 0)
      }

      PerspectiveCamera {
        position: Qt.vector3d(0, 0, 1.25)
        rotation: Quaternion.fromAxesAndAngles(Qt.vector3d(1,0,0), plugin.currentTilt, Qt.vector3d(0,1,0), 0, Qt.vector3d(0,0,1), -plugin.currentOrientation)
        clipNear: 0.01
      }

      Repeater3D {
        model: plugin.points

        delegate: Model {
          position: Qt.vector3d(modelData[0] - plugin.currentPosition[0], modelData[1] - plugin.currentPosition[1], modelData[2])
          source: "#Sphere"
          scale: Qt.vector3d(0.005, 0.005, 0.005)

          materials: PrincipledMaterial {
            baseColor: index == 0 ? Theme.accuracyTolerated : index == plugin.points.length - 1 ? Theme.accuracyBad : Theme.mainColor
            roughness: 0.5
          }

          Component.onCompleted: {
            console.log(position)
          }
        }
      }
    }

    QfToolButton {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: 5

      round: true
      iconSource: Theme.getThemeVectorIcon('ic_close_white_24dp')
      iconColor: "White"
      bgcolor: Theme.darkGray

      onClicked: {
        threeDNavigationPopup.close();
      }
    }

    Text {
      id: tiltReadingText
      anchors.bottom: parent.bottom
      anchors.left: parent.left

      text: ''
      font: Theme.defaultFont
      color: "red"// "white"
    }

    Text {
      id: gpsPositionText
      anchors.top: tiltReadingText.bottom
      anchors.left: parent.left
      text: 'GPS Position: ' + plugin.currentPosition[0] + ', ' + plugin.currentPosition[1]
      font: Theme.defaultFont
      color: "white"
    }

    Text {
      id: gpsAccuracyText
      anchors.top: gpsPositionText.bottom
      anchors.left: parent.left
      text: 'Accuracy: ' + positionSource.positionInformation.horizontalAccuracy
      font: Theme.defaultFont
      color: "white"
    }

    TiltSensor {
      id: tiltSensor
      active: threeDNavigationPopup.visible
      property var tilts: []
      onReadingChanged: {
        let tilt = reading.xRotation
        tilts.push(tilt)
        if (tilts.length > 5) {
          tilts.shift()
        }
        let sum = 0
        for (const t of tilts) {
          sum += t
        }
        plugin.currentTilt = sum / tilts.length
        tiltReadingText.text = 'current orientation: ' + plugin.currentOrientation + '\ncurrent tilt: ' + plugin.currentTilt
      }
    }

    Compass {
      id: compass
      active: threeDNavigationPopup.visible
      property var azimuths: []
      onReadingChanged: {
        let azimuth = reading.azimuth

        // Account for device pointing in the opposite direction to that of the camera
        if (tiltSensor.reading.xRotation > 90) {
          azimuth += 180
        }
        if (azimuth > 180) {
          azimuth -= 360;
        }

        azimuths.push(azimuth)
        if (azimuths.length > 5) {
          azimuths.shift()
        }
        let sum = 0
        let last = 0
        for (let i = 0; i < azimuths.length; i++) {
          if (i > 0 && Math.abs(last - azimuths[i]) > 100) {
            let alt = last < 0 ? -180 - (180 - azimuths[i]) : (180 + (180 + azimuths[i]))
            sum += (last < 0 ? -180 - (180 - azimuths[i]) : 180 + (180 + azimuths[i]))
            last = alt
          } else {
            sum += azimuths[i]
            last = azimuths[i]
          }
        }
        azimuth = sum / azimuths.length
        if (azimuth < 0) {
          azimuth += 360
        }
        plugin.currentOrientation = azimuth
        tiltReadingText.text = 'current orientation: ' + plugin.currentOrientation + '\ncurrent tilt: ' + plugin.currentTilt
      }
    }
  }
}
