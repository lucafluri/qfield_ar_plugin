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
  
  // Global component for geometry handling
  property Component geometryWrapperComponentGlobal: Component {
    QtObject {
      property var qgsGeometry
      property var crs
      
      // Add a method to try to get vertices as an array
      function getVerticesAsArray() {
        try {
          // Try direct WKT parsing first
          if (typeof qgsGeometry.asWkt === 'function') {
            try {
              const wkt = qgsGeometry.asWkt();
              if (wkt) {
                logMsg("WKT available, trying to parse");
                
                // Parse LineString WKT: LINESTRING(x1 y1, x2 y2)
                if (wkt.startsWith("LINESTRING")) {
                  const coordsText = wkt.substring(wkt.indexOf("(") + 1, wkt.lastIndexOf(")"));
                  const coordPairs = coordsText.split(",");
                  
                  if (coordPairs.length > 0) {
                    logMsg("WKT parser found " + coordPairs.length + " points in LineString");
                    
                    return coordPairs.map(function(pair) {
                      const coords = pair.trim().split(" ");
                      return {
                        x: parseFloat(coords[0]),
                        y: parseFloat(coords[1]),
                        z: coords.length > 2 ? parseFloat(coords[2]) : 0
                      };
                    });
                  }
                }
                // Parse MultiLineString WKT: MULTILINESTRING((x1 y1, x2 y2), (x3 y3, x4 y4))
                else if (wkt.startsWith("MULTILINESTRING")) {
                  logMsg("Processing MultiLineString WKT");
                  
                  try {
                    // Get the content between the outer parentheses: ((x1 y1, x2 y2), (x3 y3, x4 y4))
                    const multiLineContent = wkt.substring(wkt.indexOf("(") + 1, wkt.lastIndexOf(")"));
                    
                    // Find all individual linestrings (content between inner parentheses)
                    let lineStrings = [];
                    let openParenCount = 0;
                    let currentLine = "";
                    
                    for (let i = 0; i < multiLineContent.length; i++) {
                      const char = multiLineContent.charAt(i);
                      
                      if (char === '(') {
                        openParenCount++;
                        if (openParenCount === 1) {
                          // Start of a new linestring
                          currentLine = "";
                        } else {
                          currentLine += char;
                        }
                      } 
                      else if (char === ')') {
                        openParenCount--;
                        if (openParenCount === 0) {
                          // End of a linestring
                          lineStrings.push(currentLine);
                        } else {
                          currentLine += char;
                        }
                      }
                      else {
                        currentLine += char;
                      }
                    }
                    
                    logMsg("Found " + lineStrings.length + " linestrings in MultiLineString");
                    
                    // If we have at least one linestring, parse the first one
                    if (lineStrings.length > 0) {
                      const firstLine = lineStrings[0];
                      const coordPairs = firstLine.split(",");
                      
                      logMsg("First linestring has " + coordPairs.length + " points");
                      
                      if (coordPairs.length > 0) {
                        return coordPairs.map(function(pair) {
                          const coords = pair.trim().split(" ");
                          return {
                            x: parseFloat(coords[0]),
                            y: parseFloat(coords[1]),
                            z: coords.length > 2 ? parseFloat(coords[2]) : 0
                          };
                        });
                      }
                    }
                  } catch (e) {
                    logMsg("Advanced MultiLineString parsing error: " + e);
                    
                    // Fallback to simpler parsing method
                    try {
                      // Find position of first inner opening parenthesis
                      const firstOpenParen = multiLineContent.indexOf("(");
                      if (firstOpenParen >= 0) {
                        // Find matching closing parenthesis
                        let openCount = 1;
                        let closePos = -1;
                        
                        for (let i = firstOpenParen + 1; i < multiLineContent.length; i++) {
                          if (multiLineContent.charAt(i) === '(') openCount++;
                          if (multiLineContent.charAt(i) === ')') openCount--;
                          
                          if (openCount === 0) {
                            closePos = i;
                            break;
                          }
                        }
                        
                        if (closePos > 0) {
                          const firstLineString = multiLineContent.substring(firstOpenParen + 1, closePos);
                          const coordPairs = firstLineString.split(",");
                          
                          logMsg("Fallback method found " + coordPairs.length + " points");
                          
                          if (coordPairs.length > 0) {
                            return coordPairs.map(function(pair) {
                              const coords = pair.trim().split(" ");
                              return {
                                x: parseFloat(coords[0]),
                                y: parseFloat(coords[1]),
                                z: coords.length > 2 ? parseFloat(coords[2]) : 0
                              };
                            });
                          }
                        }
                      }
                    } catch (e2) {
                      logMsg("Fallback MultiLineString parsing also failed: " + e2);
                    }
                  }
                }
              }
            } catch (e) {
              logMsg("Error parsing WKT: " + e);
            }
          }
          
          // First try to use pointList - this might only work for point geometries
          const points = qgsGeometry.pointList();
          if (points && points.length > 0) {
            return points.map(p => ({ x: p.x(), y: p.y(), z: p.z() || 0 }));
          }
          
          // Try to get as GeoJSON string
          if (typeof qgsGeometry.asGeoJson === 'function') {
            const geojson = qgsGeometry.asGeoJson();
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
          if (typeof qgsGeometry.vertices === 'function') {
            const vertices = qgsGeometry.vertices();
            if (vertices && vertices.length > 0) {
              return vertices.map(v => ({ x: v.x(), y: v.y(), z: v.z() || 0 }));
            }
          }
          
          // Try to get it as a polyline
          if (typeof qgsGeometry.asPolyline === 'function') {
            const polyline = qgsGeometry.asPolyline();
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
  // Enhanced logging system
  //----------------------------------
  function logMsg(msg) {
    // Log to QField's message log
    iface.logMessage("[QField 3D Nav] " + msg);
    
    // Also log to console for developer debugging
    console.log("[QField 3D Nav] " + msg);
    
    // Show toast with shorter duration for immediate feedback
    iface.mainWindow().displayToast(msg, 3);
    
    // Also add to the debug text overlay for persistent visibility
    if (pipe_text === "") {
      pipe_text = msg;
    } else {
      // Add the new message to the end
      pipe_text = pipe_text + "\n" + msg;
      
      // Keep only the last 15 messages to ensure it doesn't get too long
      const messages = pipe_text.split("\n");
      if (messages.length > 15) {
        pipe_text = messages.slice(-15).join("\n");
      }
    }
  }

  function loadPipeFeatures() {
    if (!testPipesLayer) {
      console.error('test_pipes layer not found');
      return;
    }

    // Reset pipe features array
    pipeFeatures = [];
    
    // Try to get features by ID, starting from 0
    // Since we don't know how many features there are, we'll try a reasonable number
    let featuresFound = 0;
    for (let i = 0; i < 3; i++) {
      const featureId = i.toString();
      const feature = testPipesLayer.getFeature(featureId);
      
      if (!feature) {
        continue; // Skip if feature doesn't exist
      }
      
      if (feature.geometry) {
        pipeFeatures.push({
          geometry: feature.geometry,
          id: feature.id
        });
        featuresFound++;
        logMsg("Loaded feature " + feature.id);
      }
    }
    
    if (featuresFound === 0) {
      logMsg('No valid features found with geometry');
    } else {
      logMsg("Loaded " + featuresFound + " pipe features");
    }
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
              logMsg("No vertices found for feature: " + feature.id);
            }
          } catch (e) {
            logMsg("Error calculating distance for feature " + feature.id + ": " + e);
          }
          
          wrapper.destroy();
        } else {
          logMsg("Failed to create geometry wrapper for feature: " + feature.id);
        }
      } catch (e) {
        logMsg("Error processing feature: " + e);
      }
    }
  }

  function initLayer() {
    // Log QML version info for debugging
    if (typeof Qt !== 'undefined') {
      logMsg("Qt: " + Qt.version + " | QML running in QField");
    }
    
    logMsg("Initializing test_pipes layer");
    testPipesLayer = qgisProject.mapLayersByName("test_pipes")[0];
    
    if (!testPipesLayer) {
      logMsg("Warning: test_pipes layer not found");
      return;
    }
    
    logMsg("Found test_pipes layer: " + testPipesLayer.name);
    
    // Display CRS information to help with debugging
    logMsg("Layer CRS: " + testPipesLayer.crs.authid);
    
    // Debug geometry properties to provide more information
    debugGeometryProperties();
    
    // Load all pipe features
    loadPipeFeatures();
    
    // Calculate and log distances to pipe features
    if (pipeFeatures && pipeFeatures.length > 0) {
      logMsg("Calculating distances to pipe features...");
      logPipeDistances();
    }
  }
  
  // Function to debug geometry properties
  function debugGeometryProperties() {
    if (!testPipesLayer) return;
    
    logMsg("=====================================================");
    logMsg("STARTING COMPREHENSIVE FEATURE ANALYSIS");
    logMsg("QField Version: " + iface.version);
    logMsg("Layer name: " + testPipesLayer.name);
    logMsg("CRS: " + testPipesLayer.crs);
    logMsg("Feature count: " + testPipesLayer.featureCount);
    logMsg("=====================================================");
    
    logMsg("Analyzing features in test_pipes layer");
    
    // Try features with IDs 0-9
    let featuresFound = 0;
    for (let i = 0; i < 10; i++) {
      const featureId = i.toString();
      const feature = testPipesLayer.getFeature(featureId);
      
      if (!feature) continue;
      if (!feature.geometry) continue;
      
      featuresFound++;
      logMsg("Found feature " + featureId + ", analyzing geometry...");
      
      // Log geometry type and properties
      const geomType = feature.geometry.type;
      logMsg("Geometry type: " + geomType);
      
      // Check if this is a valid geometry for a pipe (should be LineString)
      if (geomType !== 'LineString') {
        logMsg("WARNING: Feature " + featureId + " is not a LineString! It's a " + geomType);
      }
      
      // Create a manual WKT parser to extract vertices
      if (feature.geometry.asWkt) {
        try {
          const wkt = feature.geometry.asWkt();
          logMsg("WKT: " + wkt);
          
          // If it's a LINESTRING, try to parse it manually
          if (wkt.startsWith("LINESTRING")) {
            // Extract points from WKT: LINESTRING(x1 y1, x2 y2)
            const coordsText = wkt.substring(wkt.indexOf("(") + 1, wkt.lastIndexOf(")"));
            const coordPairs = coordsText.split(",");
            
            logMsg("Found " + coordPairs.length + " coordinate pairs in WKT");
            
            if (coordPairs.length > 0) {
              // Log the first and last points
              const firstPair = coordPairs[0].trim().split(" ");
              logMsg("First WKT point: (" + firstPair[0] + ", " + firstPair[1] + ")");
              
              if (coordPairs.length > 1) {
                const lastPair = coordPairs[coordPairs.length-1].trim().split(" ");
                logMsg("Last WKT point: (" + lastPair[0] + ", " + lastPair[1] + ")");
              }
            }
          }
        } catch (e) {
          logMsg("Error parsing WKT: " + e);
        }
      } else {
        logMsg("No asWkt method available on geometry");
      }
      
      // Create a geometry wrapper instance
      let wrapper = geometryWrapperComponentGlobal.createObject(null, {
        "qgsGeometry": feature.geometry,
        "crs": testPipesLayer.crs
      });
      if (!wrapper) {
        logMsg("Failed to create geometry wrapper");
        continue;
      }
      
      // Try different ways to access vertices
      if (wrapper.qgsGeometry.asGeoJson) {
        try {
          const geoJson = wrapper.qgsGeometry.asGeoJson();
          logMsg("GeoJSON: " + geoJson);
        } catch (e) {
          logMsg("Error getting GeoJSON: " + e);
        }
      }
      
      // Get the vertices from the geometry
      const vertices = wrapper.getVerticesAsArray();
      if (!vertices || vertices.length === 0) {
        logMsg("No vertices found using wrapper.getVerticesAsArray()");
        wrapper.destroy();
        continue;
      }
      
      // Log information about the vertices
      logMsg("Feature " + featureId + " has " + vertices.length + " vertices");
      
      // Log the first vertex
      const firstPoint = vertices[0];
      logMsg("First vertex: (" + firstPoint.x.toFixed(2) + ", " + firstPoint.y.toFixed(2) + ", " + (firstPoint.z || 0).toFixed(2) + ")");
      
      // Log the last vertex if there is more than one
      if (vertices.length > 1) {
        const lastPoint = vertices[vertices.length - 1];
        logMsg("Last vertex: (" + lastPoint.x.toFixed(2) + ", " + lastPoint.y.toFixed(2) + ", " + (lastPoint.z || 0).toFixed(2) + ")");
      }
      
      // Clean up the wrapper
      wrapper.destroy();
    }
    
    if (featuresFound === 0) {
      logMsg("No features found for analysis");
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
    // Debug button
    //----------------------------------
    Button {
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: 10
      text: "Debug"
      onClicked: {
        logMsg("Debug button pressed");
        debugGeometryProperties();
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

    Text {
      id: debugLogText
      anchors.top: gpsAccuracyText.bottom
      anchors.left: parent.left
      text: pipe_text
      font: Theme.defaultFont
      color: "yellow"  // Make debug logs stand out with a different color
      wrapMode: Text.Wrap
      width: parent.width - 10  // Allow some margin
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

  Component.onCompleted: {
    iface.addItemToPluginsToolbar(pluginButton);
    Qt.callLater(initLayer);
  }

}
