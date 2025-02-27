import QtQuick

QtObject {
  id: logger
  
  property bool debug: true
  
  /**
   * Log a message with timestamp
   */
  function logMsg(message) {
    if (debug) {
      const timestamp = new Date().toISOString().replace('T', ' ').substring(0, 19);
      console.log("[" + timestamp + "] " + message);
    }
  }
}
