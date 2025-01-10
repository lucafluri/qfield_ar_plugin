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

  property bool initiated: false
  property var points: []

  property var positions: []
  property var currentPosition: [0,0,0]
  property double currentOrientation: 0
  property double currentTilt: 90

  Component.onCompleted: {
    iface.addItemToPluginsToolbar(pluginButton)
    
    // Try both approaches to find the layer
    // First try: Using project's mapLayers
    let layers = iface.project.mapLayers()
    for (let layerId in layers) {
        let layer = layers[layerId]
        console.log("Found layer:", layer.name)  // Debug log
        if (layer.name.toLowerCase().includes("test_pipes")) {
            testPipesLayer = layer
            console.log("testPipesLayer loaded successfully from mapLayers:", layer.name)
            pipe_text = "testPipesLayer loaded successfully from mapLayers: " + layer.name
            break
        }
    }
    
    // Second try: Using layer tree if first approach failed
    if (!testPipesLayer) {
        let root = iface.project.layerTreeRoot()
        let layerNodes = root.findLayers()
        for (let node of layerNodes) {
            let layer = node.layer
            console.log("Found layer in tree:", layer.name)  // Debug log
            if (layer.name.toLowerCase().includes("test_pipes")) {
                testPipesLayer = layer
                console.log("testPipesLayer loaded successfully from layer tree:", layer.name)
                pipe_text = "testPipesLayer loaded successfully from layer tree: " + layer.name
                break
            }
        }
    }
    
    if (!testPipesLayer) {
        console.log("Error: testPipesLayer not found in either mapLayers or layer tree")
        pipe_text = "Error: testPipesLayer not found in either mapLayers or layer tree"
    }
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
        rotation: Quaternion.fromAxesAndAngles(Qt.vector3d(1,0,0), plugin.currentTilt, Qt.vector3d(0,1,0), 0, Qt.vector3d(0,0,1), -plugin.currentOrientation)
        clipNear: 0.01
      }

      Node {
        // Original points for reference
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
          }
        }

        // Pipes layer visualization
        Repeater3D {
          model: {
            if (!testPipesLayer) return [];
            let features = [];
            let iterator = testPipesLayer.getFeatures();
            let feature;
            while ((feature = iterator.nextFeature())) {
              let geometry = feature.geometry;
              if (geometry.type() === QgsWkbTypes.LineString) {
                let points = geometry.asPolyline();
                for (let i = 0; i < points.length - 1; i++) {
                  features.push({
                    start: points[i],
                    end: points[i + 1]
                  });
                }
              }
            }
            return features;
          }

          delegate: Model {
            required property var start
            required property var end

            // Calculate position and rotation for the cylinder
            position: {
              let midX = (start.x + end.x) / 2 - plugin.currentPosition[0];
              let midY = (start.y + end.y) / 2 - plugin.currentPosition[1];
              return Qt.vector3d(midX, midY, 0);
            }

            // Calculate rotation to align cylinder with line segment
            rotation: {
              let dx = end.x - start.x;
              let dy = end.y - start.y;
              let angle = Math.atan2(dy, dx) * 180 / Math.PI;
              return Qt.quaternion.fromEulerAngles(0, 0, angle);
            }

            // Calculate scale based on line length
            scale: {
              let dx = end.x - start.x;
              let dy = end.y - start.y;
              let length = Math.sqrt(dx * dx + dy * dy);
              return Qt.vector3d(length, 0.002, 0.002); // Adjust cylinder thickness with y and z scale
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
      // {
      //   if (!testPipesLayer) return 'No pipe layer found';
      //   let count = 0;
      //   let iterator = testPipesLayer.getFeatures();
      //   let feature;
      //   while ((feature = iterator.nextFeature())) {
      //     count += 1;  // Count each feature as one pipe
      //   }
      //   return 'Number of pipes: ' + count;
      // }
      font: Theme.defaultFont
      color: "white"
    }

    TiltSensor {
      id: tiltSensor
      active: threeDNavigationPopup.visible
      property var tilts: []
      property var stableThreshold: 0.5 // Define a threshold for stability
      onReadingChanged: {
        let tilt = reading.xRotation
        tilts.push(tilt)
        if (tilts.length > 5) {
          tilts.shift()
        }
        
        // Calculate average tilt
        let averageTilt = tilts.reduce((a, b) => a + b, 0) / tilts.length
        
        // Check if the device is stable
        let isStable = Math.max(...tilts) - Math.min(...tilts) < stableThreshold
        
        if (isStable) {
          // Adjust the 3D view based on the average tilt
          camera.rotation = Quaternion.fromAxesAndAngles(Qt.vector3d(1,0,0), averageTilt, Qt.vector3d(0,1,0), 0, Qt.vector3d(0,0,1), -plugin.currentOrientation)
        }
        
        plugin.currentTilt = averageTilt
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
