import Toybox.WatchUi;
import Toybox.System;

class SaveMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _session;

    function initialize(session) {
        Menu2InputDelegate.initialize();
        _session = session;
    }

    function onSelect(item) {
        var id = item.getId();

        if (id.equals("resume")) {
            _session.start();
            WatchUi.popView(WatchUi.SLIDE_DOWN); // Go back to the app
        } else if (id.equals("save")) {
            _session.save();
            System.exit(); // Closes the app and returns to the watch face
        } else if (id.equals("discard")) {
            _session.discard();
            System.exit(); // Closes the app and returns to the watch face
        }
    }
}
