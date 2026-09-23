"""Device handler registry.

To add a new device type:
1. Create a new module in this directory
2. Implement a class that extends BleDeviceHandler
3. Import and add it to DEVICE_HANDLERS below
"""
from .microair import MicroAirHandler
from .hughes import HughesHandler

# Alpha builds replace the Hughes handler with its protocol probe, which lives
# only in ha-addons-alpha.
try:
    from .hughes_probe import HughesProbeHandler as HughesHandler
except ModuleNotFoundError as exc:
    if exc.name != f"{__name__}.hughes_probe":
        raise

# All registered device handlers — bridge iterates this for discovery matching
DEVICE_HANDLERS = [
    MicroAirHandler,
    HughesHandler,
]
