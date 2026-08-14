"""jtagx — core library shared by the CLI tools and the GUI.

Centralizes reusable logic that was previously duplicated across tools/*.py and gui-spike/*.py.
First module: `jtagx.posture` (read a security posture from an enumeration capture — the field
mapping that unlock-engine.py and the GUI's Dashboard both need). More to fold in over time
(unlock strategy KB, cve DB, bsdl parse).
"""
__all__ = ["posture"]
