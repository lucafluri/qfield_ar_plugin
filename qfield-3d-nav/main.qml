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

  //----------------------------------
  // Properties
  //----------------------------------
  property var mainWindow: iface.mainWindow()
  property var positionSource: iface.findItemByObjectName('positionSource')
  property var testPipesLayer
  property string pipe_text: ""

  property bool initiated: false
  property var points: []

  property var positions: []
  property var currentPosition: [0, 0, 0]
  property double currentOrientation: 0
  property double currentTilt: 90

  //----------------------------------
  // Helper for toast + text fallback
  //----------------------------------
  function logMsg(msg) {
    // 1) Show toast inside QField
    iface.mainWindow().displayToast(msg, 3)

    // 2) Also store in pipe_text so it appears in the UI
    pipe_text += "\n" + msg
  }

  //----------------------------------
  // Attempt to find the layer by exact name:
  // "test_pipes.shp" in the active project
  //----------------------------------
  function findTestPipesExact() {
    let project = iface.project
    if (!project) {
      logMsg("No project found!")
      return null
    }

    let layersMap = project.mapLayers()
    let exactName = "test_pipes.shp" // The name you said your dataset has
    for (let layerId in layersMap) {
      let l = layersMap[layerId]
      // If the layer name is exactly test_pipes.shp
      if (l.name === exactName) {
        logMsg("Exact match found: " + l.name)
        return l
      }
    }
    // If exact match not found, fallback: partial match
    for (let layerId in layersMap) {
      let l = layersMap[layerId]
      if (l.name && l.name.toLowerCase().includes("test_pipes")) {
        logMsg("Found partial match: " + l.name)
        return l
      }
    }
    return null
  }

  //----------------------------------
  // On start: find the layer
  //----------------------------------
  Component.onCompleted: {
    iface.addItemToPluginsToolbar(pluginButton)

    // Show all layers in a toast (useful for debugging)
    let project = iface.project
    if (!project) {
      logMsg("Project is null!?")
    } else {
      let allLayers = project.mapLayers()
      let layerCount = Object.keys(allLayers).length
      logMsg("Project has " + layerCount + " layers:")
      for (let lid in allLayers) {
        logMsg(" - " + allLayers[lid].name)
      }
    }

    // Try to find "test_pipes.shp"
    testPipesLayer = findTestPipesExact()

    if (!testPipesLayer) {
      logMsg("ERROR: Could not find test_pipes.shp layer!")
    } else {
      logMsg("SUCCESS: We have testPipesLayer => " + testPipesLayer.name)
    }
  }

  //----------------------------------
  // Keep track of position changes
  //----------------------------------
  Connections {
    target: positionSource
    enabled: threeDNavigationPopup.visible

    function onProjectedPositionChanged() {
      if (positionSource.active &&
          positionSource.positionInformation.longitudeValid &&
          positionSource.positionInformation.latitudeValid) {

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
            [x + 5, y,     0],
            [x,     y + 5, 0],
            [x - 5, y,     0],
            [x,     y - 5, 0],
            [x,     y,     5],
            [x,     y,    -5]
          ]
        }

        gpsPositionText.text = 'GPS Position: ' + x + ', ' + y
        gpsAccuracyText.text = 'Accuracy: ' + positionSource.supportedPositioningMethods
      }
    }
  }

  //----------------------------------
  // Toolbar button to open the popup
  //----------------------------------
  QfToolButton {
    id: pluginButton
    iconSource: 'icon.svg'
    iconColor: "white"
    bgcolor: Theme.darkGray
    round: true

    onClicked: {
      threeDNavigationPopup.open()
    }
  }

  //----------------------------------
  // Main Popup with 3D
  //----------------------------------
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
          [x + 5, y,     0],
          [x,     y + 5, 0],
          [x - 5, y,     0],
          [x,     y - 5, 0],
          [x,     y,     5],
          [x,     y,    -5]
        ]

        gpsPositionText.text = 'GPS Position: ' + x + ', ' + y
        gpsAccuracyText.text = 'Accuracy: ' + positionSource.sourceError
      }
    }

    // Optional camera background
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
      anchors.fill: parent
      fillMode: VideoOutput.PreserveAspectCrop
    }

    //----------------------------------
    // 3D View
    //----------------------------------
    View3D {
      anchors.fill: parent

      environment: SceneEnvironment {
        antialiasingMode: SceneEnvironment.ProgressiveAA
      }

      PointLight {
        position: Qt.vector3d(0, 0, 0)
      }

      PerspectiveCamera {
        id: camera
        position: Qt.vector3d(0, 0, 1.25)
        rotation: Quaternion.fromAxesAndAngles(
                      Qt.vector3d(1,0,0),
                      plugin.currentTilt,
                      Qt.vector3d(0,1,0),
                      0,
                      Qt.vector3d(0,0,1),
                      -plugin.currentOrientation)
        clipNear: 0.01
      }

      Node {
        //----------------------------
        // 1) Some spheres for testing
        //----------------------------
        Repeater3D {
          model: plugin.points

          delegate: Model {
            position: Qt.vector3d(
                          modelData[0] - plugin.currentPosition[0],
                          modelData[1] - plugin.currentPosition[1],
                          modelData[2])
            source: "#Sphere"
            scale: Qt.vector3d(0.005, 0.005, 0.005)

            materials: PrincipledMaterial {
              baseColor: index == 0
                         ? Theme.accuracyTolerated
                         : index == plugin.points.length - 1
                           ? Theme.accuracyBad
                           : Theme.mainColor
              roughness: 0.5
            }
          }
        }

        //----------------------------
        // 2) Repeater for pipe lines
        //----------------------------
        Repeater3D {
          model: {
            // If the layer isn't found or empty, skip
            if (!testPipesLayer) {
              logMsg("Warning: testPipesLayer is null => no lines to display")
              return []
            }

            let featureArray = []
            let iterator = testPipesLayer.getFeatures()
            let feature
            while ((feature = iterator.nextFeature())) {
              let geometry = feature.geometry
              if (!geometry)
                continue

              // In QGIS, wkbType for 2D lines is often 2, for 2D multi-line is 5,
              // but you may also see 1002 or 1015 for 3D lines.
              let wkbType = geometry.wkbType()

              // Single 2D
              let line2d = geometry.asPolyline()
              if (line2d && line2d.length > 1) {
                for (let i = 0; i < line2d.length - 1; i++) {
                  featureArray.push({
                    start: {x: line2d[i].x,   y: line2d[i].y,   z: 0},
                    end:   {x: line2d[i+1].x, y: line2d[i+1].y, z: 0}
                  })
                }
              }

              // Single 3D
              let line3d = geometry.asPolyline3D()
              if (line3d && line3d.length > 1) {
                for (let i = 0; i < line3d.length - 1; i++) {
                  featureArray.push({
                    start: line3d[i],
                    end:   line3d[i+1]
                  })
                }
              }

              // Multi-line 2D
              if (wkbType === 5) {
                let multi2d = geometry.asMultiPolyline()
                if (multi2d) {
                  for (let subLine of multi2d) {
                    for (let i = 0; i < subLine.length - 1; i++) {
                      featureArray.push({
                        start: {x: subLine[i].x,   y: subLine[i].y,   z: 0},
                        end:   {x: subLine[i+1].x, y: subLine[i+1].y, z: 0}
                      })
                    }
                  }
                }
              }

              // Multi-line 3D
              if (wkbType === 1015) {
                let multi3d = geometry.asMultiPolyline3D()
                if (multi3d) {
                  for (let subLine3D of multi3d) {
                    for (let i = 0; i < subLine3D.length - 1; i++) {
                      featureArray.push({
                        start: subLine3D[i],
                        end:   subLine3D[i+1]
                      })
                    }
                  }
                }
              }
            }

            logMsg("Found " + featureArray.length + " line segments in test_pipes.shp")
            return featureArray
          }

          delegate: Model {
            required property var start
            required property var end

            // Calculate middle point
            property real dx: end.x - start.x
            property real dy: end.y - start.y
            property real segmentLength: Math.sqrt(dx*dx + dy*dy)

            position: {
              let midX = (start.x + end.x) / 2 - plugin.currentPosition[0]
              let midY = (start.y + end.y) / 2 - plugin.currentPosition[1]
              // For debugging, show each segment’s center & length
              logMsg("Pipe center => X:" + midX.toFixed(2) +
                     " Y:" + midY.toFixed(2) +
                     " Len:" + segmentLength.toFixed(2))
              return Qt.vector3d(midX, midY, 0)
            }

            // Rotate cylinder to line up with the segment
            rotation: {
              let angleDeg = Math.atan2(dy, dx) * 180 / Math.PI
              return Qt.quaternion.fromEulerAngles(0, 0, angleDeg)
            }

            // Scale: length in x-direction, small radius in y/z
            scale: Qt.vector3d(segmentLength, 0.002, 0.002)

            source: "#Cylinder"
            materials: PrincipledMaterial {
              baseColor: "blue"
              roughness: 0.3
            }
          }
        }
      }
    }

    //----------------------------------
    // Close button
    //----------------------------------
    QfToolButton {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: 5
      round: true
      iconSource: Theme.getThemeVectorIcon('ic_close_white_24dp')
      iconColor: "White"
      bgcolor: Theme.darkGray

      onClicked: {
        threeDNavigationPopup.close()
      }
    }

    //----------------------------------
    // Text overlays
    //----------------------------------
    Text {
      id: tiltReadingText
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      text: ''
      font: Theme.defaultFont
      color: "red"
    }

    Text {
      id: gpsPositionText
      anchors.top: tiltReadingText.bottom
      anchors.left: parent.left
      text: 'GPS Position: ' + currentPosition[0] + ', ' + currentPosition[1]
      font: Theme.defaultFont
      color: "green"
    }

    Text {
      id: gpsAccuracyText
      anchors.top: gpsPositionText.bottom
      anchors.left: parent.left
      text: 'Accuracy: ' + positionSource.sourceError
      font: Theme.defaultFont
      color: "white"
    }

    Text {
      id: pipeSegmentsText
      anchors.top: gpsAccuracyText.bottom
      anchors.left: parent.left
      text: pipe_text
      font: Theme.defaultFont
      color: "white"
    }

    //----------------------------------
    // Tilt sensor to adjust camera pitch
    //----------------------------------
    TiltSensor {
      id: tiltSensor
      active: threeDNavigationPopup.visible
      property var tilts: []
      property var stableThreshold: 0.5

      onReadingChanged: {
        let tilt = reading.xRotation
        tilts.push(tilt)
        if (tilts.length > 5) {
          tilts.shift()
        }

        let averageTilt = tilts.reduce((a, b) => a + b, 0) / tilts.length
        let isStable = Math.max(...tilts) - Math.min(...tilts) < stableThreshold

        if (isStable) {
          camera.rotation = Quaternion.fromAxesAndAngles(
              Qt.vector3d(1,0,0),
              averageTilt,
              Qt.vector3d(0,1,0),
              0,
              Qt.vector3d(0,0,1),
              -plugin.currentOrientation
          )
        }

        plugin.currentTilt = averageTilt
        tiltReadingText.text =
            'current orientation: ' + plugin.currentOrientation +
            '\ncurrent tilt: ' + plugin.currentTilt
      }
    }

    //----------------------------------
    // Compass sensor for yaw orientation
    //----------------------------------
    Compass {
      id: compass
      active: threeDNavigationPopup.visible
      property var azimuths: []

      onReadingChanged: {
        let azimuth = reading.azimuth

        // If device is flipped
        if (tiltSensor.reading.xRotation > 90) {
          azimuth += 180
        }
        if (azimuth > 180) {
          azimuth -= 360
        }

        azimuths.push(azimuth)
        if (azimuths.length > 5) {
          azimuths.shift()
        }

        let sum = 0
        let last = 0
        for (let i = 0; i < azimuths.length; i++) {
          if (i > 0 && Math.abs(last - azimuths[i]) > 100) {
            let alt = last < 0
                      ? -180 - (180 - azimuths[i])
                      : 180 + (180 + azimuths[i])
            sum += alt
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
        tiltReadingText.text =
            'current orientation: ' + plugin.currentOrientation +
            '\ncurrent tilt: ' + plugin.currentTilt
      }
    }
  }
}
