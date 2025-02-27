import QtQuick
import QtQuick.Controls
import QtQuick3D
import QtQuick3D.Helpers

import "../utils"

View3D {
  id: threeDView
  
  property var pipeFeatures: []
  property alias logger: loggerInstance
  property var fakePipeStart: null
  property var fakePipeEnd: null
  property var currentPosition: null
  
  Logger {
    id: loggerInstance
  }
  
  environment: SceneEnvironment {
    antialiasingMode: SceneEnvironment.ProgressiveAA
    antialiasingQuality: SceneEnvironment.High
    temporalAAEnabled: true
    temporalAAStrength: 2.0
    
    backgroundMode: SceneEnvironment.SkyBox
    lightProbe: Image {
      source: "qrc:///qt/qml/Quick3DAssets/NeutralStudio/neutral_hdr.ktx"
    }
    
    tonemapMode: SceneEnvironment.Filmic
  }
  
  // Add a camera
  PerspectiveCamera {
    id: camera
    fieldOfView: 60
    clipNear: 0.1
    clipFar: 10000
    position: Qt.vector3d(0, 2, 5)
    eulerRotation: Qt.vector3d(-15, 0, 0)
  }
  
  // Light source
  DirectionalLight {
    eulerRotation.x: -30
    eulerRotation.y: -70
    ambientColor: Qt.rgba(0.5, 0.5, 0.5, 1.0)
    brightness: 1.0
  }
  
  Node {
    // Test Pipes Layer Visualization
    Repeater3D {
      model: threeDView.pipeFeatures

      delegate: Model {
        required property var modelData
        
        // Add color property to the model data when loading features
        property color pipeColor: modelData.color || Qt.rgba(0.2, 0.6, 1.0, 1.0)
        property real distanceToUser: modelData.distanceToUser || -1
        
        geometry: ProceduralMesh {
          property real segments: 16
          property real tubeRadius: 0.05
          property var meshArrays: null  // Initialize to null instead of binding

          Component.onCompleted: {
            meshArrays = generateTube(segments, tubeRadius);
            
            if (meshArrays) {
              vertexData = meshArrays.vertexData;
              indexData = meshArrays.indexData;
              normalData = meshArrays.normalData;
              uv0Data = meshArrays.uv0Data;
              
              primitiveType = PrimitiveType.Triangles;
              topology = Topology.TriangleList;
              winding = Winding.CounterClockwise;
            }
          }

          function generateTube(segments: real, tubeRadius: real) {
            let verts = []
            let normals = []
            let indices = []
            let uvs = []

            // Get the geometry points from the pipe feature
            let pos = []
            
            // Get position CRS
            const posCrs = threeDView.logger.logMsg ? geometryUtils.getPositionCrs() : null;
            
            // Create a geometry wrapper instance
            let wrapper = Qt.createQmlObject('import QtQuick; import "../models"; GeometryWrapper { qgsGeometry: modelData.geometry; crs: posCrs }', this);
            
            if (wrapper) {
              try {
                let vertices = wrapper.getVerticesAsArray();
                
                if (vertices && vertices.length >= 2) {
                  // Successfully got vertices, use them
                  threeDView.logger.logMsg("Successfully extracted " + vertices.length + " vertices for 3D pipe");
                  
                  // Use vertices to generate tube mesh
                  // ... (rest of the implementation)
                  
                  if (vertices.length >= 2) {
                    // Create tube mesh from vertices
                    // ... (implementation of tube mesh generation)
                  }
                }
              } catch (e) {
                console.error("Error processing vertices for feature " + modelData.id + ": " + e);
              }
              
              wrapper.destroy();
            } else {
              console.error("Failed to create geometry wrapper for feature " + modelData.id);
            }

            return {
              vertexData: new Float32Array(verts),
              normalData: new Float32Array(normals),
              indexData: new Uint16Array(indices),
              uv0Data: new Float32Array(uvs)
            };
          }
        }

        materials: [
          DefaultMaterial {
            diffuseColor: pipeColor
            specularAmount: 0.25
            specularRoughness: 0.2
          }
        ]
      }
    }

    // Fake pipe visualization
    Repeater3D {
      model: threeDView.fakePipeStart && threeDView.fakePipeEnd ? 1 : 0
      
      Model {
        // ... (implementation of fake pipe visualization)
      }
    }
  }
}
