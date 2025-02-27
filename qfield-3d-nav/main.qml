import QtQuick
import QtQuick.Controls
import QtQuick3D
import QtQuick3D.Helpers
import QtMultimedia
import QtSensors

import org.qfield
import org.qgis
import Theme

import "utils"
import "components"
import "models"

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
  property var pipeFeatures: []
  property var currentPosition: null
  
  property var geometryUtils: GeometryUtils {}
  property var layerUtils: LayerUtils { logger: logger }
  
  // Create logger
  Logger {
    id: logger
    debug: true
  }
  
  //----------------------------------
  // QField connection
  //----------------------------------
  Connections {
    target: positionSource
    enabled: true

    function onProjectedPositionChanged() {
      if (positionSource) {
        plugin.currentPosition = positionSource.projectedPosition;
      }
      
      // Update distances when position changes
      calculatePipeDistances();
    }
  }
  
  //----------------------------------
  // Public interface
  //----------------------------------
  // Main action to open 3D navigation
  Q.Button {
    id: threeDNavigationButton
    
    visible: true
    round: true
    bgcolor: Theme.mainColor
    iconSource: 'qrc:/icons/3d.svg'
    iconColor: 'white'
    
    onClicked: {
      if (!plugin.initiated) {
        plugin.initLayer();
        plugin.initiated = true;
      }
      
      threeDNavigationPopup.open();
    }
  }
  
  // 3D Navigation popup component
  NavigationPopup {
    id: threeDNavigationPopup
    mainWindow: plugin.mainWindow
    positionSource: plugin.positionSource
    pipeFeatures: plugin.pipeFeatures
    currentPosition: plugin.currentPosition
    fakePipeStart: plugin.fakePipeStart
    fakePipeEnd: plugin.fakePipeEnd
    debug: logger.debug
    
    onOpened: {
      // Make sure we have the latest data
      if (plugin.pipeFeatures.length === 0) {
        loadPipeFeatures();
      }
      
      calculatePipeDistances();
    }
  }
  
  //----------------------------------
  // Helper functions
  //----------------------------------
  function calculatePipeDistances() {
    if (!plugin.currentPosition || !plugin.pipeFeatures.length) return;
    
    logger.logMsg("Calculating distances to pipes...");
    
    for (let idx = 0; idx < plugin.pipeFeatures.length; idx++) {
      try {
        const feature = plugin.pipeFeatures[idx];
        
        // Calculate distance to this feature
        if (feature && feature.geometry) {
          const distanceResult = feature.geometry.distance(
            QgsGeometry.fromPointXY(
              plugin.currentPosition.x,
              plugin.currentPosition.y
            )
          );
          
          if (distanceResult >= 0) {
            feature.distanceToUser = distanceResult;
            // Color based on distance - closer = red, farther = blue
            const normalizedDist = Math.min(distanceResult / 100, 1);
            feature.color = Qt.rgba(1.0 - normalizedDist, 0.5, normalizedDist, 1.0);
          }
        }
      } catch (e) {
        logger.logMsg("Error calculating distance for pipe #" + idx + ": " + e.toString());
      }
    }
    
    // Sort features by distance
    plugin.pipeFeatures.sort((a, b) => a.distanceToUser - b.distanceToUser);
    
    // Log the closest pipe
    if (plugin.pipeFeatures.length > 0) {
      const closest = plugin.pipeFeatures[0];
      logger.logMsg("Closest pipe is feature ID " + closest.id + " at " + 
                    closest.distanceToUser.toFixed(2) + " meters");
    }
  }
  
  // Initialize the test_pipes layer
  function initLayer() {
    plugin.testPipesLayer = layerUtils.initLayer();
    if (plugin.testPipesLayer) {
      loadPipeFeatures();
    }
  }
  
  // Load features from the pipe layer
  function loadPipeFeatures() {
    plugin.pipeFeatures = layerUtils.loadPipeFeatures(plugin.testPipesLayer);
    
    // If we have the current position, calculate distances
    if (plugin.currentPosition) {
      calculatePipeDistances();
    }
  }
  
  Component.onCompleted: {
    logger.logMsg("QField 3D Navigation Plugin initialized");
  }
}
