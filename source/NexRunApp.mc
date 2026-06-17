import Toybox.Application;
import Toybox.WatchUi;
import Toybox.Position;
import Toybox.Lang; // Add this import for type definitions

class NexRunApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    // state must be typed as a nullable Dictionary
    function onStart(state as Lang.Dictionary?) as Void {
        Position.enableLocationEvents(
            Position.LOCATION_CONTINUOUS,
            method(:onPosition)
        );
    }

    function onStop(state as Lang.Dictionary?) as Void {
        Position.enableLocationEvents(
            Position.LOCATION_DISABLE,
            method(:onPosition)
        );
    }

    function onPosition(info as Position.Info) as Void {
        // Keeps GPS active so Distance/Pace/Map data flows
    }

    function getInitialView() {
        var view = new NexRunView();
        var delegate = new NexRunDelegate(view);
        return [view, delegate];
    }
}
