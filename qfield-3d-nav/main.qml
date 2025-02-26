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
  
  // Global component for QgsGeometryWrapper
  property Component geometryWrapperComponentGlobal: Component {
    QgsGeometryWrapper {
      // Add a method to try to get vertices as an array
      function getVerticesAsArray() {
        try {
          // Try accessing asJsonObject which might include the full geometry
          if (typeof this.asJsonObject === 'function') {
            try {
              const geoObj = this.asJsonObject();
              if (geoObj && geoObj.coordinates) {
                if (Array.isArray(geoObj.coordinates)) {
                  // Handle different geometry types
                  if (geoObj.type === 'LineString') {
                    // Direct array of coordinates for LineString
                    return geoObj.coordinates.map(c => ({ 
                      x: c[0], 
                      y: c[1], 
                      z: c.length > 2 ? c[2] : 0 
                    }));
                  } else if (geoObj.type === 'MultiLineString') {
                    // Take first line for MultiLineString
                    if (geoObj.coordinates.length > 0) {
                      return geoObj.coordinates[0].map(c => ({ 
                        x: c[0], 
                        y: c[1], 
                        z: c.length > 2 ? c[2] : 0 
                      }));
                    }
                  }
                }
              }
            } catch (e) {
              console.error("Error processing asJsonObject:", e);
            }
          }
          
          // First try to use pointList - this might only work for point geometries
          const points = pointList();
          if (points && points.length > 0) {
            return points.map(p => ({ x: p.x(), y: p.y(), z: p.z() || 0 }));
          }
          
          // Try to get as GeoJSON string
          if (typeof this.asGeoJson === 'function') {
            const geojson = this.asGeoJson();
            if (geojson) {
              try {
                const geo = JSON.parse(geojson);
                if (geo && geo.coordinates) {
                  if (geo.type === 'LineString') {
                    return geo.coordinates.map(c => ({ x: c[0], y: c[1], z: c[2] || 0 }));
                  } else if (geo.type === 'MultiLineString' && geo.coordinates.length > 0) {
                    return geo.coordinates[0].map(c => ({ x: c[0], y: c[1], z: c[2] || 0 }));
                  }
                }
              } catch (e) {
                console.error("Error parsing GeoJSON:", e);
              }
            }
          }
          
          // Fall back to checking if there's a vertices() method
          if (typeof this.vertices === 'function') {
            const vertices = this.vertices();
            if (vertices && vertices.length > 0) {
              return vertices.map(v => ({ x: v.x(), y: v.y(), z: v.z() || 0 }));
            }
          }
          
          // Try to get it as a polyline
          if (typeof this.asPolyline === 'function') {
            const polyline = this.asPolyline();
            if (polyline && polyline.length > 0) {
              return polyline.map(p => ({ x: p.x(), y: p.y(), z: p.z() || 0 }));
            }
          }
        } catch (e) {
          console.error("Error in getVerticesAsArray:", e);
        }
        
        // If all else fails, return empty array
        return [];
      }
    }
  }

  //----------------------------------
  // Helper for toast + text fallback
  //----------------------------------
  function logMsg(msg) {
    // 1) Show toast inside QField
    iface.mainWindow().displayToast(msg, 3)

    // 2) Also store in pipe_text so it appears in the UI
    pipe_text += "\n" + msg
    
    // 3) Prevent pipe_text from growing too large
    // Keep only the last ~10000 characters (roughly 200 lines)
    const maxLength = 10000;
    if (pipe_text.length > maxLength) {
      // Find the position after the first newline in the second half of the text
      const startPos = pipe_text.indexOf("\n", pipe_text.length - maxLength);
      if (startPos >= 0) {
        pipe_text = "...\n[Older logs trimmed]\n..." + pipe_text.substring(startPos);
      } else {
        // Fallback - just cut at maxLength
        pipe_text = "...\n[Older logs trimmed]\n..." + pipe_text.substring(pipe_text.length - maxLength);
      }
    }
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

  function logPipeDistances() {
    if (!testPipesLayer || !pipeFeatures || pipeFeatures.length === 0) {
      logMsg("Cannot calculate distances - pipe features not loaded");
      return;
    }
    
    for (let i = 0; i < pipeFeatures.length; i++) {
      try {
        const feature = pipeFeatures[i];
        
        // Use the same approach as in the Repeater3D delegate
        logMsg("Processing feature: " + feature.id);
        
        // Create a geometry wrapper instance
        let wrapper = geometryWrapperComponentGlobal.createObject(null, {
          "qgsGeometry": feature.geometry,
          "crs": testPipesLayer.crs
        });
        
        if (wrapper) {
          logMsg("Created wrapper for feature: " + feature.id);
          try {
            const vertices = wrapper.getVerticesAsArray();
            if (vertices && vertices.length > 0) {
              // Calculate distance to first point of the feature
              const dx = vertices[0].x - currentPosition[0];
              const dy = vertices[0].y - currentPosition[1];
              const dz = (vertices[0].z || 0) - currentPosition[2];
              const dist = Math.sqrt(dx * dx + dy * dy + dz * dz);
              
              logMsg("Distance to feature " + feature.id + " (first point): " + dist.toFixed(2) + " m");
              
              // If there are multiple points, also calculate distance to last point
              if (vertices.length > 1) {
                const lastPoint = vertices[vertices.length - 1];
                const dx2 = lastPoint.x - currentPosition[0];
                const dy2 = lastPoint.y - currentPosition[1];
                const dz2 = (lastPoint.z || 0) - currentPosition[2];
                const dist2 = Math.sqrt(dx2 * dx2 + dy2 * dy2 + dz2 * dz2);
                
                logMsg("Distance to feature " + feature.id + " (last point): " + dist2.toFixed(2) + " m");
              }
            } else {
              logMsg("No points found for feature " + feature.id);
            }
          } catch (e) {
            logMsg("Error getting pointList: " + e);
          }
          
          wrapper.destroy();
        } else {
          logMsg("Failed to create geometry wrapper for feature " + feature.id);
        }
      } catch (e) {
        logMsg("Error in feature processing loop: " + e);
      }
    }
  }

  function initLayer() {
    // logMsg("=== initLayer() ===")
    testPipesLayer = qgisProject.mapLayersByName("test_pipes")[0]
    // logMsg("Pipe Layer: " + (testPipesLayer ? testPipesLayer.name : "not found")) 

    if (testPipesLayer) {
      // logMsg("Feature 0: " + testPipesLayer.getFeature("0"))
      logMsg("Geometry 0: " + testPipesLayer.getFeature("0").geometry)
      // logMsg("Feature 1: " + testPipesLayer.getFeature("1"))
      logMsg("Geometry 1: " + testPipesLayer.getFeature("1").geometry)
      
      // Debug geometry properties
      debugGeometryProperties();
    }

    loadPipeFeatures();
    logPipeDistances();

    return
  }
  
  // Function to debug geometry properties
  function debugGeometryProperties() {
    if (!testPipesLayer) return;
    
    const feature0 = testPipesLayer.getFeature("0");
    if (!feature0 || !feature0.geometry) {
      logMsg("No feature 0 or geometry");
      return;
    }
    
    // Log some information about the geometry
    logMsg("Feature 0 geometry type: " + feature0.geometry.type);
    logMsg("Feature 0 geometry wkbType: " + feature0.geometry.wkbType);
    
    // List all properties and methods on the geometry object
    logMsg("Geometry properties and methods:");
    for (let prop in feature0.geometry) {
      const propType = typeof feature0.geometry[prop];
      logMsg("- " + prop + ": " + propType);
      
      // If it's a function, try to call it and see what happens
      if (propType === 'function' && 
          prop !== 'constructor' && 
          prop !== 'toString' && 
          prop !== 'valueOf') {
        try {
          const result = feature0.geometry[prop]();
          logMsg("  -> " + prop + "() returned: " + (result !== null ? "value" : "null"));
        } catch (e) {
          logMsg("  -> " + prop + "() error: " + e);
        }
      }
    }
    
    // Check if we can directly access vertices
    try {
      if (feature0.geometry.vertices) {
        logMsg("Feature 0 has vertices property: " + feature0.geometry.vertices.length + " vertices");
      } else {
        logMsg("Feature 0 has no vertices property");
      }
    } catch (e) {
      logMsg("Error accessing vertices: " + e);
    }
    
    // Create QgsGeometryWrapper to debug its properties
    const wrapper = geometryWrapperComponentGlobal.createObject(null, {
      "qgsGeometry": feature0.geometry,
      "crs": testPipesLayer.crs
    });
    
    if (wrapper) {
      logMsg("Wrapper created successfully");
      
      // Log available methods on wrapper
      logMsg("Wrapper properties and methods:");
      for (let prop in wrapper) {
        const propType = typeof wrapper[prop];
        logMsg("- " + prop + ": " + propType);
        
        // Try calling the method if it's a function
        if (propType === 'function' && 
            prop !== 'constructor' && 
            prop !== 'toString' && 
            prop !== 'destroy' && 
            prop !== 'getVerticesAsArray' && 
            prop !== 'valueOf') {
          try {
            const result = wrapper[prop]();
            logMsg("  -> " + prop + "() returned: " + (result !== null ? "value" : "null"));
          } catch (e) {
            logMsg("  -> " + prop + "() error: " + e);
          }
        }
      }
      
      // Try our custom method
      try {
        const vertices = wrapper.getVerticesAsArray();
        logMsg("getVerticesAsArray() returns: " + (vertices.length ? vertices.length + " points" : "0 points"));
        
        if (vertices.length > 0) {
          logMsg("First point: " + vertices[0].x + ", " + vertices[0].y);
          logMsg("Vertex array: " + JSON.stringify(vertices.slice(0, 2))); // Show first two vertices
        }
      } catch (e) {
        logMsg("Error with getVerticesAsArray(): " + e);
      }
      
      wrapper.destroy();
    } else {
      logMsg("Failed to create wrapper for debugging");
    }
  }

  Component.onCompleted: {
    iface.addItemToPluginsToolbar(pluginButton);
    Qt.callLater(initLayer);
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
        
        // Update distances to pipe features when position changes
        if (threeDNavigationPopup.visible && testPipesLayer && pipeFeatures.length > 0) {
          logPipeDistances();
        }
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

            geometry: ProceduralMesh {
              property real segments: 16
              property real tubeRadius: 0.05
              property var meshArrays: null  // Initialize to null instead of binding

              positions: meshArrays ? meshArrays.verts : []
              normals: meshArrays ? meshArrays.normals : []
              indexes: meshArrays ? meshArrays.indices : []

              Component.onCompleted: {
                meshArrays = generateTube(segments, tubeRadius)
              }

              function generateTube(segments: real, tubeRadius: real) {
                let verts = []
                let normals = []
                let indices = []
                let uvs = []

                // Get the geometry points from the pipe feature
                let pos = []
                
                // Create a geometry wrapper instance
                let wrapper = geometryWrapperComponentGlobal.createObject(null, {
                  "qgsGeometry": modelData.geometry,
                  "crs": plugin.testPipesLayer.crs
                });
                if (wrapper) {
                  let vertices = wrapper.getVerticesAsArray();
                  if (vertices && vertices.length > 0) {
                    // Compute distance from plugin.currentPosition to the first point
                    let dx = vertices[0].x - plugin.currentPosition[0];
                    let dy = vertices[0].y - plugin.currentPosition[1];
                    let dz = (vertices[0].z || 0) - plugin.currentPosition[2];
                    let dist = Math.sqrt(dx * dx + dy * dy + dz * dz);
                    logMsg("Distance for feature " + modelData.id + ": " + dist.toFixed(2));
                    // Populate pos array from all geometry points
                    for (let i = 0; i < vertices.length; ++i) {
                      pos.push([
                        vertices[i].x - plugin.currentPosition[0],
                        vertices[i].y - plugin.currentPosition[1],
                        vertices[i].z || 0
                      ]);
                    }
                  } else {
                    console.error("Failed to get valid vertices for feature", modelData.id);
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
              property var meshArrays: null  // Initialize to null instead of binding

              positions: meshArrays ? meshArrays.verts : []
              normals: meshArrays ? meshArrays.normals : []
              indexes: meshArrays ? meshArrays.indices : []

              Component.onCompleted: {
                meshArrays = generateTube(segments, tubeRadius)
              }

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
      text: 'Accuracy: ' + positionSource.supportedPositioningMethods
      font: Theme.defaultFont
      color: "white"
    }

    Rectangle {
      id: debugContainer
      anchors.top: gpsAccuracyText.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      // Use bottom of parent with margin to avoid covering other elements
      anchors.bottom: tiltReadingText.top
      anchors.margins: 5
      height: parent.height / 3  // Take 1/3 of the screen height
      color: "black"
      opacity: 0.5
      radius: 5
      z: 100  // Ensure it's on top of other elements
      
      ScrollView {
        id: debugScrollView
        anchors.fill: parent
        anchors.margins: 2
        clip: true
        
        TextArea { 
          id: debugTextArea
          text: pipe_text
          font: Theme.defaultFont
          color: "white"
          readOnly: true
          wrapMode: TextEdit.Wrap
          background: Rectangle {
            color: "transparent"
          }
          
          // Auto-scroll to bottom when new content is added
          onTextChanged: {
            cursorPosition = text.length
            // Ensure the cursor/newest text is visible
            Qt.callLater(function() {
              debugScrollView.ScrollBar.vertical.position = 1.0
            })
          }
        }
      }
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
