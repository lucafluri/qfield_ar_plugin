import QtQuick
import QtQuick.Controls
import QtQuick3D
import QtQuick3D.Helpers

import "../utils"
import "../models"

Popup {
  id: navigationPopup
  
  property var mainWindow
  property var positionSource
  property var pipeFeatures: []
  property var currentPosition: null
  property var fakePipeStart: null
  property var fakePipeEnd: null
  property bool debug: true
  
  Logger {
    id: logger
    debug: navigationPopup.debug
  }
  
  parent: mainWindow ? mainWindow.contentItem : null
  width: mainWindow ? Math.min(mainWindow.width, mainWindow.height) - 40 : 400
  height: mainWindow ? Math.min(mainWindow.width, mainWindow.height) - 40 : 400
  x: mainWindow ? (mainWindow.width - width) / 2 : 0
  y: mainWindow ? (mainWindow.height - height) / 2 : 0
  modal: true
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
  
  // Connection to position source
  Connections {
    target: positionSource
    enabled: navigationPopup.visible

    function onProjectedPositionChanged() {
      if (positionSource) {
        navigationPopup.currentPosition = positionSource.projectedPosition;
        logger.logMsg("Position updated: " + 
                      navigationPopup.currentPosition.x.toFixed(6) + ", " + 
                      navigationPopup.currentPosition.y.toFixed(6));
      }
    }
  }
  
  // 3D View for AR navigation
  ThreeDView {
    id: threeDView
    anchors.fill: parent
    pipeFeatures: navigationPopup.pipeFeatures
    fakePipeStart: navigationPopup.fakePipeStart
    fakePipeEnd: navigationPopup.fakePipeEnd
    currentPosition: navigationPopup.currentPosition
    logger.debug: navigationPopup.debug
  }
  
  // Compass for orientation
  Compass {
    id: compass
    width: 100
    height: 100
    active: navigationPopup.visible
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: 10
  }
  
  // Close button
  Button {
    text: "Close"
    anchors.bottom: parent.bottom
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottomMargin: 10
    onClicked: navigationPopup.close()
  }
}
