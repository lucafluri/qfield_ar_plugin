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
  // Properties & references
  //----------------------------------
  property var mainWindow: iface.mainWindow()
  property var positionSource: iface.findItemByObjectName('positionSource')
  property var testPipesLayer
  property string pipe_text: ""
  property string currentLayerName: ""

  property bool initiated: false
  property var points: []

  property var positions: []
  property var currentPosition: [0, 0, 0]
  property double currentOrientation: 0
  property double currentTilt: 90

  //----------------------------------
  // Helper to show debug toasts
  //----------------------------------
  function debugToast(msg) {
    // Show for 3 seconds (adjust to preference).
    iface.mainWindow().displayToast(msg, 3)
  }

  //----------------------------------
  // Access layer by name
  //----------------------------------
  function accessLayer(layerName) {
    try {
      var project = iface.project
      if (project) {
        var layer = project.mapLayer(layerName)
        if (layer) {
          debugToast("Layer " + layerName + " found!")
          currentLayerName = layerName
          return layer
        } else {
          debugToast("Layer " + layerName + " not found")
          return null
        }
      } else {
        debugToast("Project not available")
        return null
      }
    } catch (error) {
      debugToast("Error accessing layer: " + error)
      return null
    }
  }

  //----------------------------------
  // Startup logic
  //----------------------------------
  Component.onCompleted: {
    // Add the plugin button to the QField toolbar
    iface.addItemToPluginsToolbar(pluginButton)

    // Debug: see what layers we have
    let layers = iface.project.mapLayers()
    for (let layerId in layers) {
      let layer = layers[layerId]
      // We'll do a toast for each found layer
      debugToast("Found layer: " + layer.name)
    }

    // 1) Attempt to find 'test_pipes' by name in mapLayers()
    testPipesLayer = findTestPipesLayerByName()

    // 2) Fallback: if not found, search in layer tree
    if (!testPipesLayer) {
      testPipesLayer = findTestPipesLayerInTree()
    }

    // If still not found, show error toast
    if (!testPipesLayer) {
      debugToast("Error: test_pipes layer not found anywhere")
      pipe_text = "Error: test_pipes layer not found."
    } else {
      debugToast("testPipesLayer acquired: " + testPipesLayer.name)
      pipe_text = "testPipesLayer found: " + testPipesLayer.name
    }
  }

  //----------------------------------
  // Utility to find 'test_pipes' in mapLayers()
  //----------------------------------
  function findTestPipesLayerByName() {
    let layers = iface.project.mapLayers()
    for (let layerId in layers) {
      let layer = layers[layerId]
      // Check for "test_pipes" substring
      if (layer.name && layer.name.toLowerCase().includes("test_pipes")) {
        debugToast("test_pipes found by mapLayers() => " + layer.name)
        return layer
      }
    }
    return null
  }

  //----------------------------------
  // Utility to find 'test_pipes' in layer tree
  //----------------------------------
  function findTestPipesLayerInTree() {
    let root = iface.project.layerTreeRoot()
    let layerNodes = root.findLayers()
    for (let node of layerNodes) {
      let layer = node.layer
      if (layer && layer.name && layer.name.toLowerCase().includes("test_pipes")) {
        debugToast("test_pipes found by layerTreeRoot => " + layer.name)
        return layer
      }
    }
    return null
  }

  //----------------------------------
  // Monitor position changes to update
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
          // Just arbitrary points around the GPS position for testing
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
  // Button on QField toolbar
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
  // Main Popup with 3D View
  //----------------------------------
  Popup {
    id: threeDNavigationPopup

    parent: mainWindow.contentItem
    width: Math.min(mainWindow.width, mainWindow.height) - 40
    height: width
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2

    // Reset some states when closing
    onAboutToHide: {
      plugin.initiated = false
      plugin.points = []
      plugin.positions = []
    }

    // Initialize 3D points when opening
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

    // (Optional) Camera pass-through background
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
    // 3D Scene
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
        //----------------------------------------
        // 1) Visualize reference spheres
        //----------------------------------------
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

        //----------------------------------------
        // 2) Visualize pipes as 3D cylinders
        //----------------------------------------
        Repeater3D {
          model: {
            if (!testPipesLayer) {
              debugToast("No testPipesLayer => returning empty array")
              return []
            }

            let featureArray = []
            let iterator = testPipesLayer.getFeatures()
            let feature
            while ((feature = iterator.nextFeature())) {
              let geometry = feature.geometry
              if (!geometry) continue

              // Check the WKB type to see if 2D/3D single or multi
              let wkbType = geometry.wkbType()

              // Single 2D or 2.5D
              let single2D = geometry.asPolyline()
              let single3D = geometry.asPolyline3D()
              if (single2D && single2D.length > 1) {
                for (let i = 0; i < single2D.length - 1; i++) {
                  featureArray.push({
                    start: {x: single2D[i].x,   y: single2D[i].y,   z: 0},
                    end:   {x: single2D[i+1].x, y: single2D[i+1].y, z: 0}
                  })
                }
              } else if (single3D && single3D.length > 1) {
                for (let i = 0; i < single3D.length - 1; i++) {
                  featureArray.push({
                    start: single3D[i],
                    end:   single3D[i+1]
                  })
                }
              }

              // Multi-line
              if (wkbType === 5 /* wkbMultiLineString */ ||
                  wkbType === 1015 /* wkbMultiLineStringZ */) {
                let multi2D = geometry.asMultiPolyline()
                let multi3D = geometry.asMultiPolyline3D()

                // 2D multi
                if (multi2D && multi2D.length > 0) {
                  for (let line of multi2D) {
                    for (let i = 0; i < line.length - 1; i++) {
                      featureArray.push({
                        start: {x: line[i].x,   y: line[i].y,   z: 0},
                        end:   {x: line[i+1].x, y: line[i+1].y, z: 0}
                      })
                    }
                  }
                }
                // 3D multi
                else if (multi3D && multi3D.length > 0) {
                  for (let line3D of multi3D) {
                    for (let i = 0; i < line3D.length - 1; i++) {
                      featureArray.push({
                        start: line3D[i],
                        end:   line3D[i+1]
                      })
                    }
                  }
                }
              }
            }

            // Show the total number of line segments
            debugToast("Found " + featureArray.length + " segments in test_pipes")

            return featureArray
          }

          delegate: Model {
            required property var start
            required property var end

            // Helper properties
            property real dx: end.x - start.x
            property real dy: end.y - start.y
            property real segmentLength: Math.sqrt(dx*dx + dy*dy)

            // Compute the midpoint
            position: {
              let midX = (start.x + end.x) / 2 - plugin.currentPosition[0]
              let midY = (start.y + end.y) / 2 - plugin.currentPosition[1]

              // For debug, toast each segment. Careful if you have many lines.
              debugToast("Mid => " + midX.toFixed(2) + "," +
                         midY.toFixed(2) + " Len => " +
                         segmentLength.toFixed(2))

              return Qt.vector3d(midX, midY, 0)
            }

            // Align the cylinder with the line
            rotation: {
              let angleDeg = Math.atan2(dy, dx) * 180 / Math.PI
              return Qt.quaternion.fromEulerAngles(0, 0, angleDeg)
            }

            // Scale: length in X, small diameter in Y/Z
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
    // Close Button
    //----------------------------------
    QfToolButton {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: 5

      round: true
      iconSource: Theme.getThemeVectorIcon('ic_close_white_24dp')
      iconColor: "White"
      bgcolor: Theme.darkGray

      onClicked: threeDNavigationPopup.close()
    }

    //----------------------------------
    // Tilt / Orientation Debug Text
    //----------------------------------
    Text {
      id: tiltReadingText
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      text: ''
      font: Theme.defaultFont
      color: "red"
    }

    // Show GPS position
    Text {
      id: gpsPositionText
      anchors.top: tiltReadingText.bottom
      anchors.left: parent.left
      text: 'GPS Position: ' + currentPosition[0] + ', ' + currentPosition[1]
      font: Theme.defaultFont
      color: "green"
    }

    // Show GPS accuracy
    Text {
      id: gpsAccuracyText
      anchors.top: gpsPositionText.bottom
      anchors.left: parent.left
      text: 'Accuracy: ' + positionSource.sourceError
      font: Theme.defaultFont
      color: "white"
    }

    // Show pipe layer text
    Text {
      id: pipeSegmentsText
      anchors.top: gpsAccuracyText.bottom
      anchors.left: parent.left
      text: pipe_text
      font: Theme.defaultFont
      color: "white"
    }

    //----------------------------------
    // TiltSensor logic
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
    // Compass logic
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
