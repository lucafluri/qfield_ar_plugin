import QtQuick

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
            // Try to identify geometry type
            if (wkt.startsWith("LINESTRING") || wkt.startsWith("LineString")) {
              // Parse LineString
              const coordsText = wkt.substring(wkt.indexOf('(') + 1, wkt.lastIndexOf(')'));
              const coordPairs = coordsText.split(',');
              let vertices = [];
              
              for (let i = 0; i < coordPairs.length; i++) {
                const pair = coordPairs[i].trim().split(' ');
                if (pair.length >= 2) {
                  const x = parseFloat(pair[0]);
                  const y = parseFloat(pair[1]);
                  const z = pair.length > 2 ? parseFloat(pair[2]) : 0;
                  
                  if (!isNaN(x) && !isNaN(y)) {
                    vertices.push([x, y, z]);
                  }
                }
              }
              
              return vertices;
            } else if (wkt.startsWith("MULTILINESTRING") || wkt.startsWith("MultiLineString")) {
              // Parse MultiLineString
              try {
                const startIdx = wkt.indexOf("((");
                const endIdx = wkt.lastIndexOf("))");
                
                if (startIdx >= 0 && endIdx > startIdx) {
                  const content = wkt.substring(startIdx + 2, endIdx);
                  const lineStrings = content.split('),(');
                  
                  // Use only the first linestring for now
                  if (lineStrings.length > 0) {
                    const coordPairs = lineStrings[0].split(',');
                    let vertices = [];
                    
                    for (let i = 0; i < coordPairs.length; i++) {
                      const pair = coordPairs[i].trim().split(' ');
                      if (pair.length >= 2) {
                        const x = parseFloat(pair[0]);
                        const y = parseFloat(pair[1]);
                        const z = pair.length > 2 ? parseFloat(pair[2]) : 0;
                        
                        if (!isNaN(x) && !isNaN(y)) {
                          vertices.push([x, y, z]);
                        }
                      }
                    }
                    
                    return vertices;
                  }
                }
              } catch (e) {
                console.error("Error parsing MultiLineString WKT:", e);
              }
            }
          }
        } catch (e) {
          console.error("Error parsing WKT:", e);
        }
      }
      
      // Try GeoJSON parsing if WKT failed
      if (typeof qgsGeometry.asGeoJson === 'function') {
        const geojson = qgsGeometry.asGeoJson();
        if (geojson) {
          try {
            const geo = JSON.parse(geojson);
            
            if (geo && geo.coordinates) {
              // Handle different geometry types
              if (geo.type === "LineString") {
                return geo.coordinates.map(coord => [coord[0], coord[1], coord.length > 2 ? coord[2] : 0]);
              } else if (geo.type === "MultiLineString" && geo.coordinates.length > 0) {
                // Use the first linestring from the multilinestring
                return geo.coordinates[0].map(coord => [coord[0], coord[1], coord.length > 2 ? coord[2] : 0]);
              }
            }
          } catch (e) {
            console.error("Error parsing GeoJSON:", e);
          }
        }
      }
    } catch (e) {
      console.error("Error in getVerticesAsArray:", e);
    }
    
    // If all else fails, return empty array
    return [];
  }
}
