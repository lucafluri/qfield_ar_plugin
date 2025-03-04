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

  property bool initiated: false
  property var points: []
  property var fakePipeStart: [0, 0, 0]
  property var fakePipeEnd: [0, 0, 0]

  property var positions: []
  property var currentPosition: [0, 0, 0]
  property double currentOrientation: 0
  property double currentTilt: 90
  property string debugLogText: ""  // Debug Text
  
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
                else if (wkt.startsWith("MULTILINESTRING") || wkt.startsWith("MultiLineString")) {
                  logMsg("- Detected MultiLineString in WKT");
                  
                  // Extract all linestrings from the MultiLineString
                  try {
                    // Extract content between the outer parentheses
                    const startIdx = wkt.indexOf("((");
                    const endIdx = wkt.lastIndexOf("))");
                    
                    if (startIdx === -1 || endIdx === -1) { 
                      logMsg("Invalid MultiLineString format: missing (( or )) or so");
                      throw new Error("Invalid MultiLineString format");
                    }
                    
                    const multiLineContent = wkt.substring(startIdx + 2, endIdx);
                    logMsg("Extracted MultiLineString content: " + multiLineContent);
                    
                    // Parse individual linestrings - direct coordinate pair extraction
                    // Based on the log, the format appears to be a series of coordinate pairs
                    // without explicit linestring separators
                    const coordPairs = multiLineContent.split(',');
                    logMsg("Found " + coordPairs.length + " coordinate pairs in MultiLineString");
                    
                    // Process all coordinate pairs
                    let allPoints = [];
                    
                    for (let i = 0; i < coordPairs.length; i++) {
                      const coordPair = coordPairs[i].trim();
                      // The format appears to be "x y" for each coordinate pair
                      const coords = coordPair.split(' ');
                      
                      if (coords.length >= 2) {
                        const x = parseFloat(coords[0]);
                        const y = parseFloat(coords[1]);
                        const z = coords.length > 2 ? parseFloat(coords[2]) : 0;
                        
                        if (!isNaN(x) && !isNaN(y)) {
                          // Add to our points array
                          allPoints.push({
                            x: x,
                            y: y,
                            z: z
                          });
                        } else {
                          logMsg("Warning: Invalid coordinate pair: " + coordPair);
                        }
                      } else {
                        logMsg("Warning: Insufficient coordinates in pair: " + coordPair);
                      }
                    }
                    
                    logMsg("Total vertices extracted: " + allPoints.length);
                    
                    if (allPoints.length > 0) {
                      return allPoints;
                    }
                  } catch (e) {
                    logMsg("- Error parsing MultiLineString: " + e.toString());
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
  // Keep track of position changes
  //----------------------------------
  Connections {
    target: positionSource
    enabled: threeDNavigationPopup.visible

    function onProjectedPositionChanged() {
      if (positionSource.active &&
          positionSource.positionInformation.longitudeValid &&
          positionSource.positionInformation.latitudeValid) {

        // Log the coordinate system information
        if (plugin.positions.length === 0) {
          logMsg("Position source CRS: " + (positionSource.crs ? positionSource.crs.authid : "unknown"));
          logMsg("Raw position: " + positionSource.positionInformation.longitude + ", " + 
                positionSource.positionInformation.latitude);
          logMsg("Projected position: " + positionSource.projectedPosition.x + ", " + 
                positionSource.projectedPosition.y);
        }

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

        gpsPositionText.text = 'GPS Projected: ' + x.toFixed(2) + ', ' + y.toFixed(2);
        
        // Update raw GPS coordinates display
        if (positionSource.positionInformation.longitudeValid && positionSource.positionInformation.latitudeValid) {
          gpsRawText.text = 'GPS Raw: ' + positionSource.positionInformation.longitude.toFixed(6) + 
                          ', ' + positionSource.positionInformation.latitude.toFixed(6);
        }

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

        // Update distances to pipe features when position changes
        if (threeDNavigationPopup.visible && testPipesLayer && pipeFeatures.length > 0) {
          logPipeDistances();
        }
      }
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
        // Create a fake pipe that is north of the user, 2m below, and 20m long
        plugin.fakePipeStart = [x, y-5, -2]  // North of user, 2m below
        plugin.fakePipeEnd = [x, y + 30, -2]    // 20m further north, 2m below
        plugin.points = [
          [x + 5, y,     0],
          [x,     y + 5, 0],
          [x - 5, y,     0],
          [x,     y - 5, 0],
          [x,     y,     5],
          [x,     y,    -5]
        ]

        gpsPositionText.text = 'GPS Projected: ' + plugin.currentPosition[0].toFixed(2) + ', ' + plugin.currentPosition[1].toFixed(2);
        
        // Update raw GPS coordinates display
        if (positionSource.positionInformation.longitudeValid && positionSource.positionInformation.latitudeValid) {
          gpsRawText.text = 'GPS Raw: ' + positionSource.positionInformation.longitude.toFixed(6) + 
                          ', ' + positionSource.positionInformation.latitude.toFixed(6);
        }
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
        clearColor: "transparent"  // Make sure the background is transparent
      }

      // Main light at camera position
      PointLight {
        position: Qt.vector3d(0, 0, 0)
        brightness: 0.8
        color: "white"
        ambientColor: "white"
      }
      
      // Additional lights to illuminate the top of the pipe
      PointLight {
        position: Qt.vector3d(0, 0, 5)  // Light above the scene
        brightness: 0.6
        color: "white"
        ambientColor: "white"
      }
      
      PointLight {
        position: Qt.vector3d(5, 5, 3)  // Light from top-right
        brightness: 0.5
        color: "#ffffee"  // Slightly warm light
        ambientColor: "#ffffee"
      }
      
      PointLight {
        position: Qt.vector3d(-5, 5, 3)  // Light from top-left
        brightness: 0.5
        color: "#eeffff"  // Slightly cool light
        ambientColor: "#eeffff"
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
            
            // Add color property to the model data when loading features
            property color pipeColor: modelData.color || Qt.rgba(0.2, 0.6, 1.0, 1.0)

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
                
                // Get position CRS
                const posCrs = getPositionCrs();
                
                // Create a geometry wrapper instance
                let wrapper = geometryWrapperComponentGlobal.createObject(null, {
                  "qgsGeometry": transformGeometryToProjectedCRS(modelData.geometry, plugin.testPipesLayer.crs),
                  "crs": posCrs
                });
                
                if (wrapper) {
                  try {
                    let vertices = wrapper.getVerticesAsArray();
                    
                    if (vertices && vertices.length >= 2) {
                      // Successfully got vertices, use them
                      logMsg("Successfully extracted " + vertices.length + " vertices for 3D pipe");
                      
                      // Compute distance from plugin.currentPosition to the first point
                      let dx = vertices[0].x - plugin.currentPosition[0];
                      let dy = vertices[0].y - plugin.currentPosition[1];
                      let dz = (vertices[0].z || 0) - plugin.currentPosition[2];
                      let dist = Math.sqrt(dx * dx + dy * dy + dz * dz);
                      
                      // Populate pos array from all geometry points
                      for (let i = 0; i < vertices.length; ++i) {
                        pos.push([
                          vertices[i].x - plugin.currentPosition[0],
                          vertices[i].y - plugin.currentPosition[1],
                          vertices[i].z || 0
                        ]);
                      }
                      
                      // If there are too few points or we want to ensure we get all parts of a MultiLineString
                      // Let's try to get the WKT and parse it manually if needed
                      if ((vertices.length < 2 || modelData.geometry.asWkt && modelData.geometry.asWkt().startsWith("MULTILINESTRING")) && modelData.geometry.asWkt) {
                        try {
                          const wkt = modelData.geometry.asWkt();
                          
                          // Check if it's a MultiLineString
                          if (wkt.startsWith("MULTILINESTRING") || wkt.startsWith("MultiLineString")) {
                            logMsg("Attempting manual MultiLineString parsing for feature " + modelData.id);
                            
                            // Try to extract content between the outer parentheses
                            try {
                              // Fix: Make sure we're correctly extracting the content
                              // The format is MULTILINESTRING((x1 y1, x2 y2), (x3 y3, x4 y4))
                              const startIdx = wkt.indexOf("((");
                              const endIdx = wkt.lastIndexOf("))");
                              
                              if (startIdx === -1 || endIdx === -1) {
                                logMsg("Invalid MultiLineString format: missing (( or ))");
                                throw new Error("Invalid MultiLineString format");
                              }
                              
                              const multiLineContent = wkt.substring(startIdx + 2, endIdx);
                              logMsg("Extracted MultiLineString content: " + multiLineContent);
                              
                              // Parse individual linestrings - direct coordinate pair extraction
                              // Based on the log, the format appears to be a series of coordinate pairs
                              // without explicit linestring separators
                              const coordPairs = multiLineContent.split(',');
                              logMsg("Found " + coordPairs.length + " coordinate pairs in MultiLineString");
                              
                              // Process all coordinate pairs
                              let allPoints = [];
                              
                              for (let i = 0; i < coordPairs.length; i++) {
                                const coordPair = coordPairs[i].trim();
                                // The format appears to be "x y" for each coordinate pair
                                const coords = coordPair.split(' ');
                                
                                if (coords.length >= 2) {
                                  const x = parseFloat(coords[0]);
                                  const y = parseFloat(coords[1]);
                                  const z = coords.length > 2 ? parseFloat(coords[2]) : 0;
                                  
                                  if (!isNaN(x) && !isNaN(y)) {
                                    // Add to our points array, relative to current position
                                    allPoints.push([
                                      x - plugin.currentPosition[0],
                                      y - plugin.currentPosition[1],
                                      z
                                    ]);
                                  } else {
                                    logMsg("Warning: Invalid coordinate pair: " + coordPair);
                                  }
                                } else {
                                  logMsg("Warning: Insufficient coordinates in pair: " + coordPair);
                                }
                              }
                              
                              if (allPoints.length > 0) {
                                logMsg("Extracted " + allPoints.length + " points from MultiLineString WKT");
                                pos = allPoints; // Replace the pos array with our manually extracted points
                              }
                            } catch (e) {
                              logMsg("Error in advanced MultiLineString parsing: " + e.toString());
                              
                              // Fallback to regex method if the advanced parsing fails
                              logMsg("Using regex fallback method for MultiLineString parsing");
                              const regex = /(-?\d+\.?\d*)\s+(-?\d+\.?\d*)/g;
                              let match;
                              let allPoints = [];
                              
                              // Log the WKT for debugging
                              logMsg("WKT for regex parsing: " + wkt.substring(0, Math.min(100, wkt.length)) + (wkt.length > 100 ? "..." : ""));
                              
                              while ((match = regex.exec(wkt)) !== null) {
                                const x = parseFloat(match[1]);
                                const y = parseFloat(match[2]);
                                
                                if (!isNaN(x) && !isNaN(y)) {
                                  // Add to our points array, relative to current position
                                  allPoints.push([
                                    x - plugin.currentPosition[0],
                                    y - plugin.currentPosition[1],
                                    0 // No Z value in WKT
                                  ]);
                                } else {
                                  logMsg("Warning: Invalid coordinate pair from regex: " + match[0]);
                                }
                              }
                              
                              if (allPoints.length > 0) {
                                logMsg("Extracted " + allPoints.length + " points using regex fallback");
                                pos = allPoints; // Replace the pos array with our manually extracted points
                              }
                            }
                          }
                        } catch (e) {
                          logMsg("Error parsing WKT for feature " + modelData.id + ": " + e.toString());
                        }
                      }
                    } else {
                      console.error("Failed to get valid vertices for feature " + modelData.id);
                    }
                  } catch (e) {
                    console.error("Error processing vertices for feature " + modelData.id + ": " + e);
                  }
                  
                  wrapper.destroy();
                } else {
                  console.error("Failed to create geometry wrapper for feature " + modelData.id);
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

            materials: [
              DefaultMaterial {
                diffuseColor: pipeColor
                specularAmount: 0.5
              }
            ]
          }
        }

        // Pipe visualization using Repeater3D
        Repeater3D {
          model: 1
          
          delegate: Model {
            position: Qt.vector3d(0, 0, 0)  // Position is handled in the mesh

            geometry: ProceduralMesh {
              property real segments: 10
              property real tubeRadius: 0.15
              property var meshArrays: generateTube(segments, tubeRadius)

              positions: meshArrays.verts
              normals: meshArrays.normals
              indexes: meshArrays.indices

              function generateTube(segments: real, tubeRadius: real) {
                let verts = []
                let normals = []
                let indices = []
                let uvs = [] // not used here

                // Create position array from start to end point
                let pos = []
                if (plugin.fakePipeStart && plugin.fakePipeEnd) {
                  // Get the start and end points relative to current position
                  const startX = plugin.fakePipeStart[0] - plugin.currentPosition[0]
                  const startY = plugin.fakePipeStart[1] - plugin.currentPosition[1]
                  const startZ = plugin.fakePipeStart[2] || 0
                  
                  const endX = plugin.fakePipeEnd[0] - plugin.currentPosition[0]
                  const endY = plugin.fakePipeEnd[1] - plugin.currentPosition[1]
                  const endZ = plugin.fakePipeEnd[2] || 0
                  
                  // Create a path with multiple points for a more complex pipe
                  pos = [
                    [startX, startY, startZ],
                    [startX + (endX - startX) * 0.33, startY + (endY - startY) * 0.33, startZ + (endZ - startZ) * 0.33],
                    [startX + (endX - startX) * 0.66, startY + (endY - startY) * 0.66, startZ + (endZ - startZ) * 0.66],
                    [endX, endY, endZ]
                  ]
                } else {
                  // Default pipe if no coordinates are available
                  pos = [[0,0,0],[0,3,0],[-3,3,0],[-3,2,0]]
                }

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

                for (let i = 0; i < pos.length - 1; ++i) {
                  for (let j = 0; j < segments; ++j) {
                    let a = (segments + 1) * i + j
                    let b = (segments + 1) * (i + 1) + j
                    let c = (segments + 1) * (i + 1) + j + 1
                    let d = (segments + 1) * i + j + 1

                    // Generate two triangles for each quad in the mesh
                    // Adjust order to be counter-clockwise
                    indices.push(a, d, b)
                    indices.push(b, d, c)
                  }
                }

                return { verts: verts, normals: normals, uvs: uvs, indices: indices }
              }
            }

            materials: [
              DefaultMaterial {
                diffuseColor: "purple"  // Changed from "red" to "purple"
                specularAmount: 0.5     // Increased from 0.25 to 0.5
              }
            ]
          }
        }

        // Points visualization
        // Repeater3D {
        //   model: plugin.points

        //   delegate: Model {
        //     position: Qt.vector3d(
        //                   modelData[0] - plugin.currentPosition[0],
        //                   modelData[1] - plugin.currentPosition[1],
        //                   modelData[2] || 0)
        //     source: "#Sphere"
        //     scale: Qt.vector3d(0.01, 0.01, 0.01)

        //     materials: [
        //       DefaultMaterial {
        //         diffuseColor: index === 0 ? "green" : "blue"
        //         specularAmount: 0.5
        //       }
        //     ]
        //   }
        // }
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
        logMsg("===== DEBUG BUTTON PRESSED =====");
        
        // Clear previous log
        plugin.debugLogText = "";
        
        // Initialize layer if needed
        if (!testPipesLayer) {
          initLayer();
        }
        
        // Load pipe features
        loadPipeFeatures();
        
        // Calculate distances
        if (pipeFeatures && pipeFeatures.length > 0) {
          logPipeDistances();
        } else {
          logMsg("No pipe features loaded to analyze");
        }
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
      text: 'GPS Projected: ' + plugin.currentPosition[0].toFixed(2) + ', ' + plugin.currentPosition[1].toFixed(2)
      font: Theme.defaultFont
      color: "green"
    }

    Text {
      id: gpsRawText
      anchors.top: gpsPositionText.bottom
      anchors.left: parent.left
      text: 'GPS Raw: ' + positionSource.positionInformation.longitude.toFixed(6) + ', ' + positionSource.positionInformation.latitude.toFixed(6)
      font: Theme.defaultFont
      color: "yellow"
    }

    Text {
      id: debugLogText
      anchors.top: gpsRawText.bottom
      anchors.left: parent.left
      text: plugin.debugLogText  // Use the new property
      font: Theme.defaultFont
      color: "yellow"  // Make debug logs stand out with a different color
      wrapMode: Text.Wrap
      width: parent.width - 10  // Allow some margin
      height: parent.height - y - 10  // Set height to allow scrolling
      clip: true  // Prevent text from overflowing
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

  // New property for CoordinateTransformer
  property CoordinateTransformer ct: CoordinateTransformer {
    id: _ct
    sourceCrs: geometryWrapper.crs
    sourcePosition: modelData
    destinationCrs: mapCanvas.mapSettings.destinationCrs
    transformContext: qgisProject.transformContext
  }

  // Initialize when plugin loads
  Component.onCompleted: {
    logMsg("QField 3D Navigation Plugin loaded");
    logMsg("Enhanced coordinate system handling with geometry wrapper CRS");
    
    // Log CRS information
    try {
      // Get position CRS using our helper
      const posCrs = getPositionCrs();
      logMsg("Position CRS from helper: " + (posCrs ? posCrs.authid : "Not available"));
      
      if (positionSource) {
        logMsg("Position source available: " + (positionSource ? "yes" : "no"));
      } else {
        logMsg("Position source not available");
      }
    } catch (e) {
      logMsg("Error getting CRS information: " + e.toString());
    }
    
    // Add plugin button to toolbar
    iface.addItemToPluginsToolbar(pluginButton);
    
    // Try to initialize the test_pipes layer
    initLayer();
  }

//==========================================
// All functions
//==========================================

  // Initialize the test_pipes layer
  function initLayer() {
    logMsg("Initializing test_pipes layer");
    testPipesLayer = qgisProject.mapLayersByName("test_pipes")[0];
    
    if (!testPipesLayer) {
      logMsg("WARNING: test_pipes layer not found in project");
      return;
    }
    
    logMsg("Found test_pipes layer: " + testPipesLayer.name);
    
    // Display CRS information
    if (testPipesLayer.crs) {
      logMsg("Layer CRS: " + testPipesLayer.crs.authid);
    } else {
      logMsg("Layer has no CRS information");
    }
  }

  //----------------------------------
  // Enhanced logging system
  //----------------------------------
  function logMsg(msg) {
    let timestamp = new Date().toLocaleTimeString();
    if (iface && iface.logMessage) {
      iface.logMessage("[3D Nav] " + msg);
    }
    
    // Also log to console for QField development builds
    console.log("[3D Nav] " + msg);
    
    // Also display in the overlay
    plugin.debugLogText += timestamp + ": " + msg + "\n";
    
    // Keep log at a manageable size - trim if too long
    if (plugin.debugLogText.length > 10000) {
      let lines = plugin.debugLogText.split('\n');
      if (lines.length > 100) {
        lines = lines.slice(lines.length - 100);
        plugin.debugLogText = lines.join('\n');
      }
    }
  }
  
  // Advanced geometry analysis function for debugging
  function analyzeGeometry(geometry) {
    if (!geometry) {
      logMsg("ERROR: Null geometry provided to analyzeGeometry");
      return;
    }
    
    // Log basic geometry properties
    logMsg("Geometry analysis:");
    logMsg("- Type: " + geometry.type);
    
    // Try different methods to extract geometry data
    if (geometry.asWkt) {
      try {
        const wkt = geometry.asWkt();
        logMsg("- WKT available: " + (wkt ? "Yes" : "No"));
        if (wkt) {
          logMsg("- WKT length: " + wkt.length);
          const wktType = wkt.substring(0, wkt.indexOf('('));
          logMsg("- WKT type: " + wktType.trim());
          
          // Advanced WKT analysis based on type
          if (wkt.startsWith("MULTILINESTRING") || wkt.startsWith("MultiLineString")) {
            logMsg("- Detected MultiLineString in WKT");
            
            // Extract all linestrings from the MultiLineString
            try {
              // Extract content between the outer parentheses
              const startIdx = wkt.indexOf("((");
              const endIdx = wkt.lastIndexOf("))");
              
              if (startIdx === -1 || endIdx === -1) {
                logMsg("Invalid MultiLineString format: missing (( or ))");
                throw new Error("Invalid MultiLineString format");
              }
              
              const multiLineContent = wkt.substring(startIdx + 2, endIdx);
              logMsg("Extracted MultiLineString content: " + multiLineContent);
              
              // Parse individual linestrings
              let lineStrings = [];
              let openParenCount = 0;
              let currentLine = "";
              
              for (let i = 0; i < multiLineContent.length; i++) {
                const c = multiLineContent.charAt(i);
                
                if (c === "(") {
                  openParenCount++;
                  if (openParenCount === 1) {
                    // Start of a new linestring
                    currentLine = "";
                  } else {
                    currentLine += c;
                  }
                } 
                else if (c === ")") {
                  openParenCount--;
                  if (openParenCount === 0) {
                    // End of a linestring
                    lineStrings.push(currentLine);
                  } else {
                    currentLine += c;
                  }
                }
                else {
                  currentLine += c;
                }
              }
              
              logMsg("Parsed " + lineStrings.length + " linestrings from MultiLineString");
              
              // If no linestrings were found using the parentheses method,
              // try direct coordinate pair extraction
              if (lineStrings.length === 0) {
                logMsg("No linestrings found with parentheses method, trying direct coordinate extraction");
                // Direct coordinate pair extraction
                const coordPairs = multiLineContent.split(',');
                logMsg("Found " + coordPairs.length + " coordinate pairs in MultiLineString");
                
                // Process all coordinate pairs directly
                let allPoints = [];
                
                for (let i = 0; i < coordPairs.length; i++) {
                  const coordPair = coordPairs[i].trim();
                  const coords = coordPair.split(' ');
                  
                  if (coords.length >= 2) {
                    const x = parseFloat(coords[0]);
                    const y = parseFloat(coords[1]);
                    const z = coords.length > 2 ? parseFloat(coords[2]) : 0;
                    
                    if (!isNaN(x) && !isNaN(y)) {
                      allPoints.push({
                        x: x,
                        y: y,
                        z: z
                      });
                    }
                  }
                }
                
                if (allPoints.length > 0) {
                  logMsg("Successfully extracted " + allPoints.length + " points directly from MultiLineString");
                  return allPoints;
                }
              }
              
              // Count total vertices across all linestrings
              let totalVertices = 0;
              for (let i = 0; i < lineStrings.length; i++) {
                const coordPairs = lineStrings[i].split(',');
                totalVertices += coordPairs.length;
              }
              logMsg("Total vertices across all linestrings: " + totalVertices);
              
              // Process all linestrings to get all points
              let allPoints = [];
              
              for (let i = 0; i < lineStrings.length; i++) {
                const coordPairs = lineStrings[i].split(',');
                
                for (let j = 0; j < coordPairs.length; j++) {
                  const coordPair = coordPairs[j].trim();
                  const coords = coordPair.split(' ');
                  
                  if (coords.length >= 2) {
                    const x = parseFloat(coords[0]);
                    const y = parseFloat(coords[1]);
                    const z = coords.length > 2 ? parseFloat(coords[2]) : 0;
                    
                    if (!isNaN(x) && !isNaN(y)) {
                      // Add to our points array
                      allPoints.push({
                        x: x,
                        y: y,
                        z: z
                      });
                    } else {
                      logMsg("Warning: Invalid coordinate pair: " + coordPair);
                    }
                  } else {
                    logMsg("Warning: Insufficient coordinates in pair: " + coordPair);
                  }
                }
              }
              
              if (allPoints.length > 0) {
                logMsg("Successfully extracted " + allPoints.length + " points from MultiLineString");
                return allPoints;
              }
            } catch (e) {
              logMsg("- Error parsing MultiLineString: " + e.toString());
            }
          } else if (wkt.startsWith("LINESTRING")) {
            logMsg("- Detected LineString in WKT");
            // Count vertices in LineString
            const coordPairs = wkt.substring(wkt.indexOf('(') + 1, wkt.lastIndexOf(')')).split(',');
            logMsg("- Contains approximately " + coordPairs.length + " vertices");
            
            // Log first coordinate for debugging
            if (coordPairs.length > 0) {
              logMsg("- First coordinate: " + coordPairs[0].trim());
            }
          }
        }
      } catch (e) {
        logMsg("- Error getting WKT: " + e.toString());
      }
    } else {
      logMsg("- WKT method not available");
    }
    
    // Try to create a wrapper and get vertices
    try {
      let wrapper = geometryWrapperComponentGlobal.createObject(null, {
        "qgsGeometry": geometry,
        "crs": testPipesLayer ? testPipesLayer.crs : null
      });
      
      if (wrapper) {
        logMsg("- Wrapper created successfully");
        try {
          const vertices = wrapper.getVerticesAsArray();
          logMsg("- Vertices array available: " + (vertices ? "Yes" : "No"));
          if (vertices) {
            logMsg("- Vertex count: " + vertices.length);
            if (vertices.length > 0) {
              // Log first vertex
              logMsg("- First vertex: [" + vertices[0].x + ", " + vertices[0].y + 
                    (vertices[0].z ? ", " + vertices[0].z : ", NULL") + "]");
              
              // Log last vertex if more than one
              if (vertices.length > 1) {
                const last = vertices[vertices.length - 1];
                logMsg("- Last vertex: [" + last.x + ", " + last.y + 
                      (last.z ? ", " + last.z : ", NULL") + "]");
              }
            }
          }
        } catch (e) {
          logMsg("- Error getting vertices: " + e.toString());
        }
        wrapper.destroy();
      } else {
        logMsg("- Failed to create geometry wrapper");
      }
    } catch (e) {
      logMsg("- Exception during wrapper creation: " + e.toString());
    }
    
    logMsg("Geometry analysis complete");
  }

  function loadPipeFeatures() {
    if (!testPipesLayer) {
      console.error('test_pipes layer not found');
      return;
    }

    // Reset pipe features array
    pipeFeatures = [];
    
    // We'll only load 2-3 features as requested
    const maxFeaturesToLoad = 3;
    let featuresFound = 0;
    logMsg("Attempting to load up to " + maxFeaturesToLoad + " features from layer: " + testPipesLayer.name);
    
    for (let i = 0; i < 10 && featuresFound < maxFeaturesToLoad; i++) {
      const featureId = i.toString();
      const feature = testPipesLayer.getFeature(featureId);
      
      if (!feature) {
        continue; // Skip if feature doesn't exist
      }
      
      if (feature.geometry) {
        logMsg("Found feature " + featureId + " with geometry");
        
        // Perform detailed geometry analysis
        analyzeGeometry(feature.geometry);
        
        // Add color property to the feature - use distinct colors for each pipe
        const pipeColors = [
          Qt.rgba(0.2, 0.6, 1.0, 1.0),  // Blue
          Qt.rgba(0.8, 0.2, 0.2, 1.0),  // Red
          Qt.rgba(0.2, 0.8, 0.2, 1.0)   // Green
        ];
        const featureColor = pipeColors[featuresFound % pipeColors.length];
        
        pipeFeatures.push({
          geometry: feature.geometry,
          id: feature.id,
          color: featureColor
        });
        
        featuresFound++;
        logMsg("Loaded feature " + feature.id + " successfully (" + featuresFound + " of " + maxFeaturesToLoad + ")");
        
        if (featuresFound >= maxFeaturesToLoad) {
          logMsg("Reached maximum number of features to load (" + maxFeaturesToLoad + ")");
          break;
        }
      } else {
        logMsg("Feature " + featureId + " exists but has no geometry");
      }
    }
    
    if (featuresFound === 0) {
      logMsg('No valid features found with geometry');
    } else {
      logMsg("Loaded " + featuresFound + " pipe features");
    }
  }

  function calculateDistance(pointA, pointB) {
    try {
      // Calculate distance in projected space (2D or 3D depending on available coordinates)
      let dx = pointA[0] - pointB[0];
      let dy = pointA[1] - pointB[1];
      
      // If we have z coordinates, use them for a 3D distance calculation
      if (pointA.length > 2 && pointB.length > 2) {
        let dz = pointA[2] - pointB[2];
        return Math.sqrt(dx * dx + dy * dy + dz * dz);
      }
      
      // Otherwise use 2D distance
      return Math.sqrt(dx * dx + dy * dy);
    } catch (e) {
      logMsg("Error in calculateDistance: " + e.toString());
      return -1;
    }
  }

  // Helper function to find closest point on a line segment
  function closestPointOnLineSegment(point, lineStart, lineEnd) {
    try {
      // Line segment vector
      const vx = lineEnd[0] - lineStart[0];
      const vy = lineEnd[1] - lineStart[1];
      
      // Vector from line start to point
      const wx = point[0] - lineStart[0];
      const wy = point[1] - lineStart[1];
      
      // Squared length of line segment (2D for now)
      const c1 = vx * vx + vy * vy;
      
      // If segment is a point, just return the start point
      if (c1 < 0.0000001) {
        // Return with Z coordinate if available
        if (lineStart.length > 2) {
          return [lineStart[0], lineStart[1], lineStart[2]];
        }
        return [lineStart[0], lineStart[1]];
      }
      
      // Projection of w onto v, normalized by length of v
      const b = (wx * vx + wy * vy) / c1;
      
      // Clamp to segment
      const pb = Math.max(0, Math.min(1, b));
      
      // Calculate closest point on line
      const result = [
        lineStart[0] + pb * vx,
        lineStart[1] + pb * vy
      ];
      
      // If we have Z coordinates, interpolate Z as well
      if (lineStart.length > 2 && lineEnd.length > 2) {
        const vz = lineEnd[2] - lineStart[2];
        result.push(lineStart[2] + pb * vz);
      }
      
      return result;
    } catch (e) {
      logMsg("Error in closestPointOnLineSegment: " + e.toString());
      return null;
    }
  }

  function logPipeDistances() {
    if (!plugin.currentPosition || !pipeFeatures.length) return;
    
    logMsg("===== Starting distance calculation =====");
    
    // Get CRS information
    const posCrs = getPositionCrs();
    const layerCrs = plugin.testPipesLayer ? plugin.testPipesLayer.crs : null;
    
    logMsg("Current position system: " + (posCrs ? posCrs.authid : "unknown"));
    logMsg("Layer coordinate system: " + (layerCrs ? layerCrs.authid : "unknown"));
    
    const currentPos = plugin.currentPosition;
    logMsg("Current projected position: " + currentPos[0].toFixed(2) + ", " + currentPos[1].toFixed(2) + 
           (currentPos.length > 2 ? ", " + currentPos[2].toFixed(2) : ""));
    
    // Add raw position info
    if (positionSource.positionInformation.longitudeValid && positionSource.positionInformation.latitudeValid) {
      logMsg("Current raw position: " + positionSource.positionInformation.longitude.toFixed(6) + 
            ", " + positionSource.positionInformation.latitude.toFixed(6));
    }
    
    pipeFeatures.forEach(function(feature, idx) {
      try {
        logMsg("Processing pipe feature #" + idx);

        // Get position CRS
        const posCrs = getPositionCrs();
        
        // Transform the feature geometry to the same CRS as the position
        const transformedGeometry = transformGeometryToProjectedCRS(feature.geometry, plugin.testPipesLayer.crs);
        
        // Create a geometry wrapper for the transformed geometry
        let wrapper = geometryWrapperComponentGlobal.createObject(null, {
          "qgsGeometry": transformedGeometry,
          "crs": posCrs
        });
          
        if (wrapper) {
          // Calculate distance manually using vertices
          try {
            const vertices = wrapper.getVerticesAsArray();
            if (vertices && vertices.length > 0) {
              // Find the closest vertex
              let minDist = Number.MAX_VALUE;
              let closestPoint = null;
              
              for (let i = 0; i < vertices.length; i++) {
                const vertex = vertices[i];
                // Use all available coordinates (including Z if available)
                const vertexPoint = vertex.z !== undefined ? 
                                   [vertex.x, vertex.y, vertex.z] : 
                                   [vertex.x, vertex.y];
                const dist = calculateDistance(currentPos, vertexPoint);
                if (dist < minDist) {
                  minDist = dist;
                  closestPoint = vertexPoint;
                }
              }
              
              // Also check distances to line segments for more accuracy
              for (let i = 0; i < vertices.length - 1; i++) {
                const p1 = vertices[i];
                const p2 = vertices[i + 1];
                
                // Find closest point on line segment
                const segmentPoint = closestPointOnLineSegment(
                  currentPos, 
                  [p1.x, p1.y, p1.z || 0], 
                  [p2.x, p2.y, p2.z || 0]
                );
                
                if (segmentPoint) {
                  const dist = calculateDistance(currentPos, segmentPoint);
                  if (dist < minDist) {
                    minDist = dist;
                    closestPoint = segmentPoint;
                  }
                }
              }
              
              if (closestPoint) {
                let distance = calculateDistance(currentPos, closestPoint);
                logMsg("Distance to pipe #" + idx + ": " + distance.toFixed(2) + " meters");
                
                // Update the feature's distance property
                feature.distance = distance;
              } else {
                logMsg("Failed to find closest point on pipe #" + idx);
              }
            } else {
              logMsg("No vertices found for pipe #" + idx);
            }
          } catch (e) {
            logMsg("Error calculating distance for pipe #" + idx + ": " + e.toString());
          }
          wrapper.destroy();
        } else {
          logMsg("Failed to create geometry wrapper for pipe #" + idx);
        }
      } catch (e) {
        logMsg("Error calculating distance for pipe #" + idx + ": " + e.toString());
      }
    });
  }
  
  //----------------------------------
  // Helper to transform coordinates
  //----------------------------------
  function transformGeometryToProjectedCRS(geometry, layerCRS) {
    try {
      // Check if we need coordinate transformation
      if (!geometry) {
        logMsg("Error: Cannot transform null geometry");
        return null;
      }

      const srcCrs = layerCRS;
      const destCrs = getPositionCrs();

      logMsg("Transforming from: " + (srcCrs ? srcCrs.authid : "Unknown") + 
             " to: " + (destCrs ? destCrs.authid : "Unknown"));
      
      if (srcCrs && destCrs && srcCrs.authid === destCrs.authid) {
        logMsg("Layer and position use the same CRS, no transformation needed");
        return geometry;
      }
      
      // Create a new geometry in the projected CRS
      if (srcCrs && destCrs) {
        let transformedGeometry = null;
        if (geometry) {
          try {
            // Use the CoordinateTransformer property to transform the geometry
            let transformedGeometry = ct.transformPosition(geometry);
            if (transformedGeometry) {
              logMsg("Successfully transformed geometry using CoordinateTransformer");
            } else {
              logMsg("CoordinateTransformer failed to transform geometry");
            }
            return transformedGeometry;
          } catch (error) {
            logMsg("Error transforming geometry: " + error.toString());
            transformedGeometry = geometry; // Fallback to original geometry
          }
        }
        
        if (transformedGeometry) {
          logMsg("Successfully transformed geometry from " + srcCrs.authid + " to " + destCrs.authid);
          return transformedGeometry;
        } else {
          logMsg("Warning: Transformation failed, using original geometry");
          return geometry;
        }
      } else {
        logMsg("Warning: Cannot transform, missing CRS information");
        return geometry;
      }
    } catch (e) {
      logMsg("Error in transformGeometryToProjectedCRS: " + e.toString());
      return geometry;
    }
  }
  
  //----------------------------------
  // Helper function to get position CRS
  //----------------------------------
  function getPositionCrs() {
    try {
      // Try to create a CRS directly
      if (typeof QgsCoordinateReferenceSystem !== 'undefined') {
        // Create a standard WGS84 CRS (EPSG:4326)
        let crs = QgsCoordinateReferenceSystem.fromEpsgId(4326);
        if (crs) {
          logMsg("Created WGS84 CRS: " + crs.authid);
          return crs;
        }
      } else {
        logMsg("QgsCoordinateReferenceSystem is not defined");
      }
      
      // Try to get CRS from map canvas as fallback
      if (typeof iface !== 'undefined' && iface && iface.mapCanvas && iface.mapCanvas.mapSettings) {
        let crs = iface.mapCanvas.mapSettings.destinationCrs;
        if (crs) {
          logMsg("Using map canvas CRS: " + crs.authid);
          return crs;
        }
      }
      
      // If we're in QField context, try to get the project CRS
      if (typeof qgisProject !== 'undefined' && qgisProject) {
        try {
          let crs = qgisProject.crs;
          if (crs) {
            logMsg("Using project CRS: " + crs.authid);
            return crs;
          }
        } catch (e) {
          logMsg("Error getting project CRS: " + e.toString());
        }
      }
      
      // Create a temporary geometry wrapper to access its CRS
      let tempWrapper = geometryWrapperComponentGlobal.createObject(null);
      if (tempWrapper) {
        let crs = tempWrapper.crs;
        logMsg("Retrieved CRS from geometry wrapper: " + (crs ? crs.authid : "null"));
        
        // Clean up
        tempWrapper.destroy();
        return crs;
      }
      
      logMsg("Failed to create CRS - all methods failed");
      return null;
    } catch (e) {
      logMsg("Error getting CRS: " + e.toString());
      return null;
    }
  }
  
  
}
