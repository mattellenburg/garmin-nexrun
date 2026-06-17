import Toybox.Lang;

class WarmUpTracker {
    private var _view as NexRunView;

    function initialize(view as NexRunView) {
        _view = view;
    }

    function reset() as Void {
        // No per-lap state to reset for warmup
    }

    // Returns pace + distance for the lap display.
    // The view passes lapDistM and info in; the tracker formats the output.
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
