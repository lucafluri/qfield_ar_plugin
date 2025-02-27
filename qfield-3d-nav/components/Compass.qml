import QtQuick
import QtQuick.Controls
import QtSensors

Item {
  id: compass
  
  property bool active: false
  property var azimuths: []
  property real currentAzimuth: 0
  property int updateInterval: 100  // ms
  
  width: 100
  height: 100
  
  // Compass sensor
  Compass {
    id: compassSensor
    active: compass.active
    dataRate: 1000 / compass.updateInterval
    
    onReadingChanged: {
      if (reading !== null) {
        const azimuth = reading.azimuth;
        compass.currentAzimuth = azimuth;
        
        // Accumulate readings for averaging
        compass.azimuths.push(azimuth);
        if (compass.azimuths.length > 10) {
          compass.azimuths.shift();
        }
      }
    }
  }
  
  // Get smoothed azimuth reading
  function getSmoothedAzimuth() {
    if (azimuths.length === 0) return 0;
    
    // Calculate average azimuth
    let sum = 0;
    for (let i = 0; i < azimuths.length; i++) {
      sum += azimuths[i];
    }
    return sum / azimuths.length;
  }
  
  // Visual representation
  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: "#80FFFFFF"
    border.color: "#333333"
    border.width: 2
    
    // North indicator
    Rectangle {
      width: 4
      height: parent.height * 0.4
      color: "red"
      anchors.centerIn: parent
      anchors.verticalCenterOffset: -height / 2
      rotation: -compass.getSmoothedAzimuth()
      
      Rectangle {
        width: 12
        height: 12
        radius: 6
        color: "red"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
      }
    }
    
    // Direction text
    Text {
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 5
      anchors.horizontalCenter: parent.horizontalCenter
      text: Math.round(compass.getSmoothedAzimuth()) + "°"
      font.pixelSize: 12
      font.bold: true
    }
  }
}
