import QtQuick
import "js/ControlReader.js" as ControlReader

// The cohesion captures' reader, built by each cohesionControls call so no first frame compiles ControlReader.js.
QtObject {
    function read(quick, top, kinds, alias): string { return ControlReader.read(quick, top, kinds, alias) }
}
