import QtQuick

import org.qfield
import org.qgis

import "../utils"

QtObject {
  id: layerUtils
  
  property var logger: null
  
  /**
   * Initialize the test_pipes layer and return it
   */
  function initLayer() {
    if (logger) logger.logMsg("Initializing test_pipes layer");
    
    let testPipesLayer = null;
    
    // Find the test_pipes layer
    if (QgsProject && QgsProject.instance()) {
      const layers = QgsProject.instance().mapLayers();
      for (const layerId in layers) {
        const layer = layers[layerId];
        if (layer && layer.name === "test_pipes") {
          testPipesLayer = layer;
          if (logger) logger.logMsg("Found test_pipes layer");
          break;
        }
      }
    }
    
    return testPipesLayer;
  }
  
  /**
   * Load features from the pipe layer
   */
  function loadPipeFeatures(layer) {
    if (!layer) {
      console.error('test_pipes layer not found');
      return [];
    }
    
    if (logger) logger.logMsg("Loading pipe features");
    
    const features = [];
    try {
      // Get the features from the layer
      const featureIterator = layer.getFeatures();
      
      // Iterate through the features
      while (featureIterator.nextFeature()) {
        const feature = featureIterator.feature();
        
        if (feature && feature.valid()) {
          const geometry = feature.geometry();
          if (geometry && !geometry.isEmpty()) {
            // Get feature ID
            const id = feature.id();
            
            // Get feature attributes
            const attributes = {};
            const fields = layer.fields();
            for (let i = 0; i < fields.count(); i++) {
              const field = fields.at(i);
              const value = feature.attribute(field.name());
              attributes[field.name()] = value;
            }
            
            // Add to features array
            features.push({
              id: id,
              geometry: geometry,
              attributes: attributes,
              color: Qt.rgba(0.2, 0.6, 1.0, 1.0), // Default color
              distanceToUser: -1
            });
          }
        }
      }
      
      // Clean up the iterator
      featureIterator.close();
      
      if (logger) logger.logMsg("Loaded " + features.length + " pipe features");
    } catch (e) {
      console.error("Error loading pipe features:", e);
    }
    
    return features;
  }
}
