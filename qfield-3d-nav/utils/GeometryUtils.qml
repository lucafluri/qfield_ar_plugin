import QtQuick

import org.qfield
import org.qgis

QtObject {
  id: geometryUtils
  
  /**
   * Transform geometry from layer CRS to projected CRS
   */
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
            // Create QgsQuickCoordinateTransformer
            let transformer = new QgsQuick.CoordinateTransformer();
            
            // Configure the transformer
            transformer.sourceCrs = srcCrs;
            transformer.destinationCrs = destCrs;
            transformer.transformContext = QgsProject.instance().transformContext();

            // Clone the geometry and transform each vertex
            transformedGeometry = geometry.clone();
            let vertices = [];
            
            // Get vertices from WKT
            const wkt = geometry.asWkt();
            if (wkt) {
              const coords = wkt.match(/[-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?/g);
              if (coords) {
                for (let i = 0; i < coords.length; i += 2) {
                  const x = parseFloat(coords[i]);
                  const y = parseFloat(coords[i + 1]);
                  
                  // Set source position and get projected position
                  transformer.sourcePosition = Qt.point(x, y);
                  const projectedPos = transformer.projectedPosition;
                  
                  vertices.push([projectedPos.x, projectedPos.y]);
                }
                
                // Create new geometry from transformed vertices
                transformedGeometry = QgsGeometry.fromPolylineXY(vertices);
              }
            }
            
            // Clean up the transformer
            transformer.destroy();
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
  
  /**
   * Get the position CRS
   */
  function getPositionCrs() {
    try {
      // Try to create a CRS directly
      if (typeof QgsCoordinateReferenceSystem !== 'undefined') {
        // Create a standard WGS84 CRS (EPSG:4326)
        const crs = QgsCoordinateReferenceSystem.fromEpsgId(4326);
        if (crs) {
          return crs;
        }
      }
      
      // Try to get the CRS from the project
      if (QgsProject && QgsProject.instance()) {
        const projectCrs = QgsProject.instance().crs();
        if (projectCrs) {
          return projectCrs;
        }
      }
      
      // Fallback: return null and let caller handle it
      return null;
    } catch (e) {
      console.error("Error in getPositionCrs: " + e);
      return null;
    }
  }
  
  /**
   * Analyze geometry details for debugging
   */
  function analyzeGeometry(geometry) {
    if (!geometry) {
      logMsg("ERROR: Null geometry provided to analyzeGeometry");
      return;
    }
    
    logMsg("===== Analyzing Geometry =====");
    
    if (geometry.asWkt) {
      try {
        const wkt = geometry.asWkt();
        logMsg("- WKT available: " + (wkt ? "Yes" : "No"));
        if (wkt) {
          logMsg("- WKT length: " + wkt.length);
          const wktType = wkt.substring(0, wkt.indexOf('('));
          logMsg("- WKT type: " + wktType.trim());
          
          // Analyze based on geometry type
          if (wkt.startsWith("MULTILINESTRING") || wkt.startsWith("MultiLineString")) {
            logMsg("- Detected MultiLineString in WKT");
            
            // Extract all linestrings from the MultiLineString
            try {
              // Extract content between the outer parentheses
              const startIdx = wkt.indexOf("((");
              const endIdx = wkt.lastIndexOf("))");
              
              if (startIdx >= 0 && endIdx > startIdx) {
                const content = wkt.substring(startIdx + 2, endIdx);
                
                // Split into individual linestrings
                const lineStrings = content.split('),(');
                logMsg("- Contains " + lineStrings.length + " linestrings");
                
                // Count total vertices
                let totalVertices = 0;
                for (let i = 0; i < lineStrings.length; i++) {
                  const coordPairs = lineStrings[i].split(',');
                  totalVertices += coordPairs.length;
                }
                
                logMsg("- Contains approximately " + totalVertices + " vertices in total");
              }
            } catch (e) {
              logMsg("- Error parsing MultiLineString: " + e.toString());
            }
          } else if (wkt.startsWith("LINESTRING")) {
            logMsg("- Detected LineString in WKT");
            // Count vertices in LineString
            const coordPairs = wkt.substring(wkt.indexOf('(') + 1, wkt.lastIndexOf(')')).split(',');
            logMsg("- Contains approximately " + coordPairs.length + " vertices");
          }
        }
      } catch (e) {
        logMsg("- Error getting WKT: " + e.toString());
      }
    } else {
      logMsg("- WKT method not available");
    }
  }
}
