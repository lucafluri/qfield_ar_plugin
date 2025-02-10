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
  property var projectUtils: ProjectUtils


  property var testPipesLayer
  property string pipe_text: ""

  property bool initiated: false
  property var points: []
  property var fakePipeStart: [0, 0, 0]
  property var fakePipeEnd: [0, 0, 0]

  property var positions: []
  property var currentPosition: [0, 0, 0]
  property double currentOrientation: 0
  property double currentTilt: 90

  property var pipeFeatures: {
    if (!testPipesLayer) {
      return []
    }
    let featureArray = []
    let iterator = testPipesLayer.getFeatures()
    let feature
    while ((feature = iterator.nextFeature())) {
      let geometry = feature.geometry
      if (geometry) {
        featureArray.push({
          geometry: geometry,
          id: feature.id
        })
      }
    }
    return featureArray
  }

  //----------------------------------
  // Helper for toast + text fallback
  //----------------------------------
  function logMsg(msg) {
    // 1) Show toast inside QField
    iface.mainWindow().displayToast(msg, 3)

    // 2) Also store in pipe_text so it appears in the UI
    pipe_text += "\n" + msg
  }

  function getAllLayers() {
        // If no project is specified, it uses the current project
        let layers = ProjectUtils.mapLayers()
        return layers
    }

  // Function to find specific layer by name
  function findLayerByName(layerName) {
      let layers = getAllLayers()
      for (let layerId in layers) {
          let layer = layers[layerId]
          if (layer.name === layerName) {
              return layer
          }
      }
      return null
  }

  
Timer {
    id: timer
    interval: 1000
    repeat: true
    triggeredOnStart: true
    onTriggered: initLayer()
}

Connections {
    target: iface.project
    function onProjectRead() {
        logMsg("Project fully loaded!")
        timer.stop()
        initLayer()
    }
}

property int initRetryCount: 0
property int maxRetries: 10

function initLayer() {
    logMsg("=== initLayer() ===")
    testPipesLayer = qgisProject.mapLayersByName("test_pipes")[0]
    logMsg("Pipe Layer: " + (testPipesLayer ? testPipesLayer.name : "not found")) 

    if (testPipesLayer) {
        try {
            let iterator = LayerUtils.createFeatureIteratorFromExpression(testPipesLayer, "")
            while (iterator.hasNext()) {
                let feature = iterator.next()
                logMsg("Found feature with ID: " + feature.id)
            }
        } catch (e) {
            logMsg("Error accessing features: " + e)
        }
    } else {
        logMsg("Layer 'test_pipes' not found")
    }

    return
}

  //----------------------------------
  // On start: find the layer
  //----------------------------------
  Component.onCompleted: {
    iface.addItemToPluginsToolbar(pluginButton)
    // timer.running = true // Start retry timer
    
    Qt.callLater(initLayer)
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
        plugin.fakePipeStart = [x - 5, y, 0]  // 5m west
        plugin.fakePipeEnd = [x + 5, y, 0]    // 5m east
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

        // West-East pipe visualization
        Model {
            position: Qt.vector3d(0, 0, 0)  // Centered on user
            rotation: Qt.quaternion(0, 0, 0, 1)  // No rotation needed for west-east
            scale: Qt.vector3d(10, 0.2, 0.2)  // 10m long, 0.2m diameter
            source: "#Cylinder"
            materials: PrincipledMaterial {
              baseColor: "red"
              roughness: 0.3
            }
        }

        //----------------------------
        // 2) Repeater for pipe lines
        //----------------------------
        Repeater3D {
          model: pipeFeatures

          delegate: Model {
            required property var geometry
            required property var id

            // Calculate middle point
            property real dx: geometry.asPolyline()[1].x - geometry.asPolyline()[0].x
            property real dy: geometry.asPolyline()[1].y - geometry.asPolyline()[0].y
            property real segmentLength: Math.sqrt(dx*dx + dy*dy)

            position: {
              let midX = (geometry.asPolyline()[0].x + geometry.asPolyline()[1].x) / 2 - plugin.currentPosition[0]
              let midY = (geometry.asPolyline()[0].y + geometry.asPolyline()[1].y) / 2 - plugin.currentPosition[1]
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

        //----------------------------
        // 3) Fake pipe visualization
        //----------------------------
        Model {
            // Calculate pipe properties
            property real dx: fakePipeEnd[0] - fakePipeStart[0]
            property real dy: fakePipeEnd[1] - fakePipeStart[1]
            property real pipeLength: Math.sqrt(dx*dx + dy*dy)

            position: {
              let midX = (fakePipeStart[0] + fakePipeEnd[0]) / 2 - plugin.currentPosition[0]
              let midY = (fakePipeStart[1] + fakePipeEnd[1]) / 2 - plugin.currentPosition[1]
              return Qt.vector3d(midX, midY, 0)
            }

            rotation: {
              let angleDeg = Math.atan2(dy, dx) * 180 / Math.PI
              return Qt.quaternion(angleDeg, 0, 0, 1)
            }

            scale: Qt.vector3d(pipeLength, 0.2, 0.2)  // Made the pipe a bit thicker for visibility
            source: "#Cylinder"
            
            materials: PrincipledMaterial {
              baseColor: "red"  // Made it red to distinguish from other pipes
              roughness: 0.3
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
