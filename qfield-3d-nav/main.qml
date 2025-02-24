import QtQuick
import QtQuick.Controls
import QtQuick3D
import QtQuick3D.Helpers
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

  property var pipeFeatures: []

  //----------------------------------
  // Helper for toast + text fallback
  //----------------------------------
  function logMsg(msg) {
    // 1) Show toast inside QField
    iface.mainWindow().displayToast(msg, 3)

    // 2) Also store in pipe_text so it appears in the UI
    pipe_text += "\n" + msg
  }

  function loadPipeFeatures() {
    if (!testPipesLayer) {
      console.error('test_pipes layer not found');
      return;
    }

    let feature0 = testPipesLayer.getFeature("0");
    if (!feature0 || !feature0.geometry) {
      console.error('Feature 0 not found or has no geometry');
      return;
    }

    let feature1 = testPipesLayer.getFeature("1");
    if (!feature1 || !feature1.geometry) {
      console.error('Feature 1 not found or has no geometry');
      return;
    }

    pipeFeatures = [{
      geometry: feature0.geometry,
      id: feature0.id
    }, {
      geometry: feature1.geometry,
      id: feature1.id
    }];

    logMsg('Loaded ' + pipeFeatures.length + ' pipe features')
  }

  function initLayer() {
    logMsg("=== initLayer() ===")
    testPipesLayer = qgisProject.mapLayersByName("test_pipes")[0]
    logMsg("Pipe Layer: " + (testPipesLayer ? testPipesLayer.name : "not found")) 

    if (testPipesLayer) {
      logMsg("Feature 0: " + testPipesLayer.getFeature("0"))
      logMsg("Geometry 0: " + testPipesLayer.getFeature("0").geometry)
      logMsg("Feature 1: " + testPipesLayer.getFeature("1"))
      logMsg("Geometry 1: " + testPipesLayer.getFeature("1").geometry)
    }

    loadPipeFeatures();

    return
  }

  Component.onCompleted: {
    iface.addItemToPluginsToolbar(pluginButton);
    Qt.callLater(initLayer);

    // Add a fake pipe for debugging
    pipeFeatures.push({
      geometry: {
        type: "LineString",
        coordinates: [
          [plugin.currentPosition[0], plugin.currentPosition[1] + 10],
          [plugin.currentPosition[0], plugin.currentPosition[1] + 20]
        ]
      },
      id: "fakePipe"
    });
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
        // Test Pipes Layer Visualization
        Repeater3D {
          model: plugin.pipeFeatures

          delegate: Model {
            required property var modelData

            // Component for creating geometry wrappers
            Component {
              id: geometryWrapperComponent
              QgsGeometryWrapper {
                qgsGeometry: modelData.geometry
                crs: plugin.testPipesLayer.crs
              }
            }

            geometry: ProceduralMesh {
              property real segments: 16
              property real tubeRadius: 0.05
              property var meshArrays: generateTube(segments, tubeRadius)

              positions: meshArrays.verts
              normals: meshArrays.normals
              indexes: meshArrays.indices

              function generateTube(segments: real, tubeRadius: real) {
                let verts = []
                let normals = []
                let indices = []
                let uvs = []

                // Get the geometry points from the pipe feature
                let pos = []
                
                // Create a geometry wrapper instance
                let wrapper = geometryWrapperComponent.createObject(null);
                if (wrapper) {
                  let pointList = wrapper.pointList();
                    if (pointList && pointList.length > 0) {
                    // Compute distance from plugin.currentPosition to the first point
                    let dx = pointList[0].x() - plugin.currentPosition[0];
                    let dy = pointList[0].y() - plugin.currentPosition[1];
                    let dz = (pointList[0].z() || 0) - plugin.currentPosition[2];
                    let dist = Math.sqrt(dx * dx + dy * dy + dz * dz);
                    plugin.logMsg("Distance for feature " + modelData.id + ": " + dist.toFixed(2));
                    // Populate pos array from all geometry points
                    for (let i = 0; i < pointList.length; ++i) {
                    pos.push([
                      pointList[i].x() - plugin.currentPosition[0],
                      pointList[i].y() - plugin.currentPosition[1],
                      pointList[i].z() || 0
                    ]);
                    }
                  } else {
                    console.error("Failed to get valid pointList for feature", modelData.id);
                  }
                  wrapper.destroy();
                } else {
                  console.error("Failed to create geometry wrapper for feature", modelData.id);
                }

                // Generate vertices and normals
                for (let i = 0; i < pos.length; ++i) {
                  for (let j = 0; j <= segments; ++j) {
                    let v = j / segments * Math.PI * 2

                    let centerX = pos[i][0]
                    let centerY = pos[i][1]
                    let centerZ = pos[i][2]

                    let posX = centerX + tubeRadius * Math.sin(v)
                    let posY = centerY + tubeRadius * Math.cos(v)
                    let posZ = centerZ + tubeRadius * Math.cos(v)

                    verts.push(Qt.vector3d(posX, posY, posZ))

                    let normal = Qt.vector3d(posX - centerX, posY - centerY, posZ - centerZ).normalized()
                    normals.push(normal)

                    uvs.push(Qt.vector2d(i / pos.length, j / segments))
                  }
                }

                // Generate indices for triangles
                for (let i = 0; i < pos.length - 1; ++i) {
                  for (let j = 0; j < segments; ++j) {
                    let a = (segments + 1) * i + j
                    let b = (segments + 1) * (i + 1) + j
                    let c = (segments + 1) * (i + 1) + j + 1
                    let d = (segments + 1) * i + j + 1

                    indices.push(a, d, b)
                    indices.push(b, d, c)
                  }
                }

                return { verts: verts, normals: normals, uvs: uvs, indices: indices }
              }
            }

            materials: PrincipledMaterial {
              baseColor: "#0066ff"  // Blue color for actual pipe data
              roughness: 0.3
              metalness: 0.1
            }
          }
        }

        // Pipe visualization using Repeater3D
        Repeater3D {
          model: plugin.fakePipeStart && plugin.fakePipeEnd ? 1 : 0  // Only create one pipe when we have start/end

          delegate: Model {
            position: Qt.vector3d(0, 0, 0)  // Position is handled in the mesh

            geometry: ProceduralMesh {
              property real segments: 16
              property real tubeRadius: 0.05
              property var meshArrays: generateTube(segments, tubeRadius)

              positions: meshArrays.verts
              normals: meshArrays.normals
              indexes: meshArrays.indices

              function generateTube(segments: real, tubeRadius: real) {
                let verts = []
                let normals = []
                let indices = []
                let uvs = []

                // Create position array from start to end point
                let pos = []
                if (plugin.fakePipeStart && plugin.fakePipeEnd) {
                  pos = [
                    [
                      plugin.fakePipeStart[0] - plugin.currentPosition[0],
                      plugin.fakePipeStart[1] - plugin.currentPosition[1],
                      plugin.fakePipeStart[2] || 0
                    ],
                    [
                      plugin.fakePipeEnd[0] - plugin.currentPosition[0],
                      plugin.fakePipeEnd[1] - plugin.currentPosition[1],
                      plugin.fakePipeEnd[2] || 0
                    ]
                  ]
                }

                // Generate vertices and normals
                for (let i = 0; i < pos.length; ++i) {
                  for (let j = 0; j <= segments; ++j) {
                    let v = j / segments * Math.PI * 2

                    let centerX = pos[i][0]
                    let centerY = pos[i][1]
                    let centerZ = pos[i][2]

                    let posX = centerX + tubeRadius * Math.sin(v)
                    let posY = centerY + tubeRadius * Math.cos(v)
                    let posZ = centerZ + tubeRadius * Math.cos(v)

                    verts.push(Qt.vector3d(posX, posY, posZ))

                    let normal = Qt.vector3d(posX - centerX, posY - centerY, posZ - centerZ).normalized()
                    normals.push(normal)

                    uvs.push(Qt.vector2d(i / pos.length, j / segments))
                  }
                }

                // Generate indices for triangles
                for (let i = 0; i < pos.length - 1; ++i) {
                  for (let j = 0; j < segments; ++j) {
                    let a = (segments + 1) * i + j
                    let b = (segments + 1) * (i + 1) + j
                    let c = (segments + 1) * (i + 1) + j + 1
                    let d = (segments + 1) * i + j + 1

                    indices.push(a, d, b)
                    indices.push(b, d, c)
                  }
                }

                return { verts: verts, normals: normals, uvs: uvs, indices: indices }
              }
            }

            materials: PrincipledMaterial {
              baseColor: "#ff0000"
              roughness: 0.3
              metalness: 0.1
            }
          }
        }

        // Points visualization
        Repeater3D {
          model: plugin.points

          delegate: Model {
            position: Qt.vector3d(
                          modelData[0] - plugin.currentPosition[0],
                          modelData[1] - plugin.currentPosition[1],
                          modelData[2] || 0)
            source: "#Sphere"
            scale: Qt.vector3d(0.01, 0.01, 0.01)

            materials: PrincipledMaterial {
              baseColor: index === 0 ? "#00ff00" : "#0000ff"  // Green for start, blue for others
              roughness: 0.3
              metalness: 0.1
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
              -plugin.currentOrientation)
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
