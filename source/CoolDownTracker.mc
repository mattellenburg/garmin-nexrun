import Toybox.Lang;

class CoolDownTracker {
    private var _view as NexRunView;

    function initialize(view as NexRunView) {
        _view = view;
    }

    function reset() as Void {}

    function getDisplayData(info, lapDistM as Float) as Dictionary {
        // Guard against null info during mode transitions before GPS updates
        if (info == null) {
            return {
                :valueL => "--:--",
                :labelL => "MIN/MILE",
                :valueR => "0.00",
                :labelR => "MILES",
            };
        }
        return _view.getRunningUnits(info, lapDistM);
    }
}
