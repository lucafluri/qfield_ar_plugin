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
  property var testPipesLayer
  property string pipe_text: ""
  property string currentLayerName: ""

  property bool initiated: false
  property var points: []

  property var positions: []
  property var currentPosition: [0,0,0]
  property double currentOrientation: 0
  property double currentTilt: 90

  // Function to access the layer
  function accessLayer(layerName) {
    try {
      var project = iface.project
      if (project) {
        var layer = project.mapLayer(layerName)
        if (layer) {
          iface.mainWindow().displayToast("Layer " + layerName + " found!")
          currentLayerName = layerName
          return layer
        } else {
          iface.mainWindow().displayToast("Layer " + layerName + " not found")
          return null
        }
      } else {
        iface.mainWindow().displayToast("Project not available")
        return null
      }
    } catch (error) {
      iface.mainWindow().displayToast("Error accessing layer: " + error)
      return null
    }
  }

  Component.onCompleted: {
    iface.addItemToPluginsToolbar(pluginButton)
    
    // Debug message: see what layers are actually present by name
    let layers = iface.project.mapLayers()
    for (let layerId in layers) {
        let layer = layers[layerId]
        console.log("Found layer in mapLayers():", layer.name)
    }

    // Attempt #1: Find the layer in project.mapLayers()
    testPipesLayer = findTestPipesLayerByName()
    
    // Attempt #2 (fallback): Find the layer in the layer tree if not found above
    if (!testPipesLayer) {
        testPipesLayer = findTestPipesLayerInTree()
    }
    
    // If still not found, log an error
    if (!testPipesLayer) {
        console.log("Error: test_pipes layer not found in project or layer tree")
        pipe_text = "Error: test_pipes layer not found."
    } else {
        console.log("testPipesLayer successfully acquired:", testPipesLayer.name)
        pipe_text = "testPipesLayer found: " + testPipesLayer.name
    }
  }

  function findTestPipesLayerByName() {
      let layers = iface.project.mapLayers()
      for (let layerId in layers) {
          let layer = layers[layerId]
          // You may want to compare exactly or with includes:
          if (layer.name && layer.name.toLowerCase().includes("test_pipes")) {
              console.log("test_pipes layer found by mapLayers() =>", layer.name)
              return layer
          }
      }
      return null
  }

  function findTestPipesLayerInTree() {
      let root = iface.project.layerTreeRoot()
      let layerNodes = root.findLayers()
      for (let node of layerNodes) {
          let layer = node.layer
          if (layer && layer.name && layer.name.toLowerCase().includes("test_pipes")) {
              console.log("test_pipes layer found by layerTreeRoot =>", layer.name)
              return layer
          }
      }
      return null
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
        gpsAccuracyText.text = 'Accuracy: ' + positionSource.supportedPositioningMethods 
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
      threeDNavigationPopup.open()
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
        gpsAccuracyText.text = 'Accuracy: ' + positionSource.sourceError  
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
        id: camera
        position: Qt.vector3d(0, 0, 1.25)
        rotation: Quaternion.fromAxesAndAngles(Qt.vector3d(1,0,0),
                                              plugin.currentTilt,
                                              Qt.vector3d(0,1,0),
                                              0,
                                              Qt.vector3d(0,0,1),
                                              -plugin.currentOrientation)
        clipNear: 0.01
      }

      Node {
        // Show the test points for debugging
        Repeater3D {
          model: plugin.points

          delegate: Model {
            position: Qt.vector3d(modelData[0] - plugin.currentPosition[0],
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

        // Pipes layer visualization
        Repeater3D {
          model: {
            if (!testPipesLayer) return []

            let featureArray = []
            let iterator = testPipesLayer.getFeatures()
            let feature
            while ((feature = iterator.nextFeature())) {
              let geometry = feature.geometry
              if (!geometry) continue

              // In many cases a lines layer may have multiLineString geometry
              let wkbType = geometry.wkbType()

              // Single lines
              if (wkbType === 2 /* wkbLineString */) {
                let singleLine = geometry.asPolyline()
                for (let i = 0; i < singleLine.length - 1; i++) {
                  featureArray.push({
                    start: singleLine[i],
                    end: singleLine[i+1]
                  })
                }
              }
              // Multi lines
              else if (wkbType === 5 /* wkbMultiLineString */) {
                let multiLine = geometry.asMultiPolyline()
                for (let line of multiLine) {
                  for (let i = 0; i < line.length - 1; i++) {
                    featureArray.push({
                      start: line[i],
                      end: line[i+1]
                    })
                  }
                }
              }
            }
            return featureArray
          }

          delegate: Model {
            required property var start
            required property var end

            // Middle of the line segment
            position: {
              let midX = (start.x + end.x) / 2 - plugin.currentPosition[0]
              let midY = (start.y + end.y) / 2 - plugin.currentPosition[1]
              return Qt.vector3d(midX, midY, 0)
            }

            // Rotation to align cylinder with line segment
            rotation: {
              let dx = end.x - start.x
              let dy = end.y - start.y
              let angleDeg = Math.atan2(dy, dx) * 180 / Math.PI
              // Rotate around Z by angleDeg
              return Qt.quaternion.fromEulerAngles(0, 0, angleDeg)
            }

            // Scale based on the distance of the segment
            scale: {
              let dx = end.x - start.x
              let dy = end.y - start.y
              let length = Math.sqrt(dx*dx + dy*dy)
              // x-scale = length, small radius in y and z
              return Qt.vector3d(length, 0.002, 0.002)
            }

            source: "#Cylinder"
            materials: PrincipledMaterial {
              baseColor: "blue"
              roughness: 0.3
            }
          }
        }
      }
    }

    // Close button in top-right corner
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
