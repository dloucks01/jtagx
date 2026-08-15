#!/usr/bin/env bash
# gui-smoketest.sh — offscreen end-to-end check of the PySide6 GUI shell (gui-spike/).
# Constructs the whole app, cycles every page, and exercises the safe (non-executing) handlers to
# catch dead-ends / crashes without touching hardware. SKIPs cleanly if PySide6 isn't importable
# (CI boxes without Qt), like build-vxboot-smoketest.sh does for mkbootimage.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! python3 -c "import PySide6.QtWidgets" 2>/dev/null; then
    echo "SKIP: gui-smoketest (PySide6 not installed)"
    exit 0
fi

python3 -m py_compile gui-spike/*.py || { echo "FAIL(gui): a page does not compile"; exit 1; }

# point the unlock levers/verify at the stateful locked-board mock so the guided flow is safe+real
export OPENOCD="$PWD/tools/mock-openocd.py"
export JTAGX_MOCK_STATE="$(mktemp)"; rm -f "$JTAGX_MOCK_STATE"
export JTAGX_MOCK_LOCK="register-gated"
trap 'rm -f "$JTAGX_MOCK_STATE"' EXIT

QT_QPA_PLATFORM=offscreen python3 - <<'PY' || exit 1
import sys
sys.path.insert(0, "gui-spike")
from PySide6.QtWidgets import QApplication, QTabWidget
app = QApplication([])
import qt_spike, unlock_panel, jtagx_app
app.setStyleSheet(qt_spike.QSS + unlock_panel.QSS)

def bad(m): print("FAIL(gui):", m); sys.exit(1)

w = jtagx_app.App(); w.resize(1200, 800)

# 1. all six pages present and switchable, no crash
if w.stack.count() != 6: bad(f"expected 6 pages, got {w.stack.count()}")
for i in range(6):
    w._go(i)
    if w.stack.currentIndex() != i: bad(f"nav to page {i} failed")

# 2. dashboard hero counters are REAL (not the old hardcoded 13/4/7)
d = w.dash
tiles = d._tile_data()
labels = {t[0] for t in tiles}
if labels != {"CHAIN", "POSTURE", "CAPABILITIES", "ARTIFACTS"}: bad("hero tiles wrong")
caps_on = sum(1 for k, *_ in qt_spike.CAPS if k != "off")
if dict((t[0], t[1]) for t in tiles)["CAPABILITIES"] != str(caps_on): bad("capabilities count not derived")

# 3. dead tabs are filled: Registers tab has real content + search/decode when a capture exists
regs = qt_spike.load_registers(qt_spike.ROOT)
tabw = d.findChild(QTabWidget)
if tabw.count() != 7: bad("dashboard center should have 7 tabs (incl. Kill Chain, Shell)")
if regs and "Registers (" not in tabw.tabText(1): bad("registers tab should show a count")
if regs:
    if len(regs[0]) != 5: bad("load_registers should include the decoded fields (5-tuple)")
    total = len(d._regs)
    d._reg_search.setText("jtag")
    vis = sum(1 for r in range(d._reg_table.rowCount()) if not d._reg_table.isRowHidden(r))
    if not (0 < vis < total): bad("register search should narrow the visible rows")
    d._reg_search.setText(""); d._reg_sec.setChecked(True)
    secn = sum(1 for r in range(d._reg_table.rowCount()) if not d._reg_table.isRowHidden(r))
    if not (0 < secn <= total): bad("security-only filter should narrow to security registers")
    d._reg_sec.setChecked(False)
    ji = next((i for i, r in enumerate(d._regs) if r[1] == "JTAG_SEC"), None)
    if ji is not None:
        d._show_reg_fields(ji)
        if "JTAG_SEC" not in d._reg_detail.text() or "SSSS_DAP_SEC" not in d._reg_detail.text():
            bad("clicking a register should decode its bit-fields")

# 4. cross-page flow: dashboard navigate signal drives the shell
seen = []
w.dash.navigate.connect(lambda i: seen.append(i))
w.dash.navigate.emit(3)
if w.stack.currentIndex() != 3 or seen != [3]: bad("navigate signal should switch pages")

# 5. memory page has a working dump selector
if not hasattr(w, "dumpsel"): bad("memory page missing dump selector")
w._refresh_memory()   # must not crash with 0..N dumps

# 6. unlock panel renders the from-capture plan without crashing
up = w.stack.widget(1)
up.load()

# 7. status bar reflects detection (real string, not the old hardcoded 'FT2232H ...')
w.refresh_status()
if not w._st_conn.text(): bad("status bar not populated")

# 8. capability copy-path (placeholder cmd) must not execute — just clipboard/log
d._cap_action("Break & capture", "ok")   # has <funcVA> -> copy path
if d.runner.busy(): bad("copy-path capability must not launch a process")

# 9. chain page refresh is idempotent
w.chain.refresh(); w.chain.refresh()
# 9b. the Chain page shows the pre-flight go/no-go panel (jtagx.preflight)
from PySide6.QtWidgets import QLabel as _QL
_pf = [l for l in w.chain.findChildren(_QL) if "PRE-FLIGHT" in l.text()]
if not _pf: bad("Chain page should show the pre-flight verdict panel")
# 9c. first-contact troubleshooting search box (jtagx.firstcontact) — symptom -> ranked blocker + fix
if not hasattr(w.chain, "_tc_input"): bad("Chain page should have the first-contact search box")
w.chain._tc_input.setText("flashpro won't work")
w.chain._run_troubleshoot()
_tclabels = [l.text() for l in w.chain.findChildren(_QL)]
if not any("proprietary-adapter" in x for x in _tclabels):
    bad("troubleshoot search for 'flashpro' should surface the proprietary-adapter blocker")
if not any("FlashPro Express" in x or "ftdi_sio" in x for x in _tclabels):
    bad("troubleshoot result should show the concrete fix, not just the blocker id")
w.chain._tc_input.setText(""); w.chain._run_troubleshoot()   # restore (empty query clears results)

# 9d. CoreSight topology panel (jtagx.coresight parsed from captured dap-info text). The real ROOT's
# reports/ dir is mutable (whatever was last captured live), so only assert well-formedness there —
# the deterministic behavior is tested against an isolated synthetic capture below.
_real_comps = qt_spike.load_coresight_components(qt_spike.ROOT)
if not isinstance(_real_comps, list): bad("load_coresight_components should always return a list")
import tempfile as _tf, os as _os, json as _json
# deterministic empty case: a thin dap-info (matches the golden's "No ROM table present" shape)
_tmpempty = _tf.mkdtemp()
_os.makedirs(_os.path.join(_tmpempty, "reports"))
_thincap = {"coresight": {"ap_info": {"0": "AP # 0x0\nMEM-AP BASE 0xfeff0002\n\t\tNo ROM table present\n",
                                      "1": "JTAG-DP STICKY ERROR\n"}}}
with open(_os.path.join(_tmpempty, "reports", "raw-1.json"), "w") as _fh:
    _json.dump(_thincap, _fh)
if qt_spike.load_coresight_components(_tmpempty) != []:
    bad("a thin/no-ROM-table dap-info should parse to zero components")
_sh_mod = __import__("shutil"); _sh_mod.rmtree(_tmpempty, ignore_errors=True)
# deterministic rich case
_tmproot = _tf.mkdtemp()
_os.makedirs(_os.path.join(_tmproot, "reports"))
_richcap = {
    "coresight": {"ap_info": {"0":
        "AP # 0x0\nMEM-AP BASE 0xfe800000\n"
        "\t[0x000] Component base 0xfe810000  Cortex-A53 Debug  Part is 0xd03\n"
        "\t[0x001] Component base 0xfe820000  CoreSight CTI (Cross Trigger)\n"
    }}
}
with open(_os.path.join(_tmproot, "reports", "raw-99999.json"), "w") as _fh:
    _json.dump(_richcap, _fh)
_rich = qt_spike.load_coresight_components(_tmproot)
if len(_rich) != 2: bad(f"rich capture should parse 2 components, got {len(_rich)}")
if not any("Cortex-A53 Debug" in c.name for c in _rich): bad("should identify the Cortex-A53 Debug component")
import shutil as _sh; _sh.rmtree(_tmproot, ignore_errors=True)

# 10. deepened console: §-section parsing, warn-flagging, filters, save format
c = w.console            # the ONE shell-level interactive console (fed via console_bus)
c.clear()   # step 8's copy-path already logged a line; start clean
for k, t in [("i", "Info : JTAG tap 0x24738093"),
             ("d", "# 4. Security State (research focus)"), ("d", "- **JTAG_SEC**: `0x0`"),
             ("w", "warn: all gates enabled"), ("d", "# 9. Crypto / Keys")]:
    c.append(k, t)
if [n for n, _ in c._sections] != [4, 9]: bad(f"console should parse §4,§9; got {c._sections}")
if not c._sec_warn.get(0): bad("§4 (idx0) should be warn-flagged (a warn line streamed under it)")
c._set_kind("warn")
if sum(1 for kk, tt, ss in c._log if c._passes(kk, tt, ss)) != 1: bad("warn filter should show exactly 1 line")
c._set_kind("all"); c._toggle_section(0)
if any(ss != 0 for kk, tt, ss in c._log if c._passes(kk, tt, ss)): bad("§4 section filter leaked other sections")
c._toggle_section(0)   # unfilter
if len(c._log) != 5: bad("console log should retain all 5 streamed lines")
c.clear()
if c._log or c._sections: bad("console clear should reset log + sections")

# 11. unlock panel: refresh + capture-source note; reports page: count + refresh + generate button
up.load()    # from-capture
up.reload()  # must not crash
rp = w.reports
rp._populate()
if "file(s)" not in rp.count_lbl.text(): bad("reports page should show a file count")
if not hasattr(rp, "gen_btn"): bad("reports page should have a Generate button")

# 12. posture ring reflects real counts; hero POSTURE tile jumps to the posture tab
if d._ring._total <= 0: bad("posture ring should have a nonzero total")
if "hardened" not in d._ring_head.text(): bad("ring header should mention hardened count")
d._center_tabs.setCurrentIndex(2)
d._show_posture_tab()
if d._center_tabs.currentIndex() != 0: bad("POSTURE tile should switch to the posture tab")

# 13. hero tiles route: CHAIN->2, ARTIFACTS->3 via navigate
seen2 = []
d.navigate.connect(lambda i: seen2.append(i))
d.navigate.emit(2); d.navigate.emit(3)
if seen2 != [2, 3]: bad("hero tile navigation targets wrong")

# 14. keyboard shortcuts installed (Ctrl+1..6 / E / R)
from PySide6.QtGui import QShortcut
keys = {s.key().toString() for s in w.findChildren(QShortcut)}
for need in ("Ctrl+1", "Ctrl+5", "Ctrl+E", "Ctrl+R"):
    if need not in keys: bad(f"missing shortcut {need}")
for i in range(6):        # Ctrl+R dispatch must not crash on any page
    w._go(i); w._refresh_current()

# 15. Chain target tree: clicking a core copies its xsdb command
from PySide6.QtWidgets import QTreeWidget
from PySide6.QtCore import Qt as _Qt
core = None
for tw in w.chain.findChildren(QTreeWidget):
    stack = [tw.topLevelItem(i) for i in range(tw.topLevelItemCount())]
    while stack:
        it = stack.pop()
        if it.data(0, _Qt.UserRole):
            core = it; break
        stack += [it.child(i) for i in range(it.childCount())]
    if core: break
if core is None: bad("chain target tree has no selectable core rows")
w.chain._on_target_click(core, 0)
if "xsdb" not in QApplication.clipboard().text(): bad("core click should copy an xsdb command")

# 16. transport backend routing (P2/P3 wired into the Dashboard capability surface)
if not hasattr(w, "backend_sel"): bad("topbar should have a transport backend selector")
d.set_backend("openocd")
cmd, blk = d._resolve_cap_cmd("Dump DDR / OCM")
if blk or "openocd" not in cmd: bad("Dump DDR under openocd should be the openocd command")
d.set_backend("hw_server")
cmd, blk = d._resolve_cap_cmd("Dump DDR / OCM")
if blk or "xsdb" not in cmd: bad("Dump DDR under hw_server should be the xsdb command")
_, blk = d._resolve_cap_cmd("Break & capture")
if not blk: bad("OpenOCD-only cap under hw_server should be blocked with a reason")
d.set_backend("auto")
if d._effective_backend() not in ("openocd", "hw_server"): bad("auto backend should resolve concretely")

# 17. guided locked-board workflow: lever → verify → the lock is marked DEFEATED (via the mock).
# The live capture is an OPEN board, so render a register-gated plan directly to exercise the GUI flow.
from jtagx.unlock import build_plan
_locks = build_plan("zynqmp", {"jtag_open": False, "efuse_jtag_dis": False})
up._render({"soc": "zynqmp", "locks": _locks}, "register-gated (test)")
gcard = up._cards.get("JTAG / DAP debug gate")
if gcard is None: bad("register-gated plan should have a DAP lock card")
glever = next((s for s in gcard.lock["strategies"] if s.get("verify") == "access-check"), None)
if glever is None: bad("DAP lock should carry an access-check verify lever")
up._action(glever, gcard.lock)          # starts the two-phase guided flow via the mock openocd
import time as _t
_t0 = _t.time()
while (up.runner.busy() or up._wf is not None) and _t.time() - _t0 < 25:
    app.processEvents(); _t.sleep(0.03)
app.processEvents()
if gcard.status_key != "DEFEATED":
    bad(f"guided reopen→verify should mark the register-gated DAP DEFEATED (got {gcard.status_key})")

# 18. the ONE shell console: bus feed from any tab, tab-follow divider, interactive run
from console_bus import BUS as _BUS
w.console.clear()
_BUS.command.emit("Chain", "echo bus-cmd")
_BUS.line.emit("i", "bus-line-xyz")
app.processEvents()
if "Chain $ echo bus-cmd" not in w.console.text.toPlainText(): bad("console should show bus commands")
if "bus-line-xyz" not in w.console.text.toPlainText(): bad("console should show bus lines")
w._go(2)   # switch tab → a divider should appear
if "Chain" not in w.console.text.toPlainText(): bad("console should follow the active tab (divider)")
w.console.input.setText("echo interactive-xyz"); w.console._run_input()
_t0 = _t.time()
while w.console.runner.busy() and _t.time() - _t0 < 10:
    app.processEvents(); _t.sleep(0.03)
app.processEvents()
if "interactive-xyz" not in w.console.text.toPlainText(): bad("interactive console should run typed commands")
if not w.console._history: bad("interactive console should keep command history")

# 19. console command surface: backend-aware primitives + slash-commands + raw passthrough
w._console_set_backend("openocd")
exp, _ = w.console._interpret("mrd 0x100000 4")
if "mdw 0x100000 4" not in exp: bad("mrd under openocd should become an mdw command")
w._console_set_backend("hw_server")
exp, _ = w.console._interpret("mrd 0xffca0040 1")
if "xsdb" not in exp or "mrd 0xffca0040" not in exp: bad("mrd under hw_server should become an xsdb mrd")
w._console_set_backend("openocd")
exp, _ = w.console._interpret("/dump 0x100000 0x1000 dumps/x.bin")
if "dump_image dumps/x.bin 0x100000 4096" not in exp: bad("/dump should expand to a backend mem dump")
exp, _ = w.console._interpret("/verify")
if "jtag-access-check.tcl" not in exp: bad("/verify should re-read the access verdict")
if w.console._interpret("echo hi")[0] != "echo hi": bad("non-command input should pass through as raw shell")
if w.console._interpret("/usr/bin/foo -x")[0] != "/usr/bin/foo -x":
    bad("an absolute-path command must run as raw shell, not be eaten as a slash-command")
w.console.clear(); w.console._interpret("/help")
if "/enumerate" not in w.console.text.toPlainText(): bad("/help should list the commands")
# /backend via the console reaches the shell selector
w.console._interpret("/backend hw_server")
if w.backend_sel.currentData() != "hw_server": bad("/backend should drive the shell transport selector")

# 20. console tab-completion (slash + primitives)
w.console.input.setText("/enu"); w.console._complete()
if w.console.input.text().strip() != "/enumerate": bad("Tab should complete /enu → /enumerate")
w.console.input.setText("sc"); w.console._complete()
if w.console.input.text().strip() != "scan": bad("Tab should complete primitive 'sc' → 'scan'")
# path completion of a later token
w.console.cwd = qt_spike.ROOT
w.console.input.setText("cat openocd/lib/enum-hel"); w.console._complete()
if "enum-helpers.tcl" not in w.console.input.text(): bad("Tab should complete a file path argument")

# 21. memory hex view: byte/ASCII find + match highlight
hv = w.hexview
hv.model.set_data(b"\x00" * 32 + b"NEEDLE" + b"\xde\xad\xbe\xef")
hv.find.setText("'NEEDLE"); hv._find_next()
if "0x20" not in hv.file_lbl.text(): bad("hex-view ASCII find should locate the needle at 0x20")
if hv.model._hl != (32, 38): bad("hex-view find should highlight the matched byte range")
hv._find_pos = 0; hv.find.setText("de ad be ef"); hv._find_next()
if "0x26" not in hv.file_lbl.text(): bad("hex-view hex-byte find should locate the pattern at 0x26")

# 22. posture row → jump to that register's decode in the Registers tab
if regs:
    pr = next((r for r in range(d._ptable.rowCount())
               if d._ptable.item(r, 1) and any(x[1] == d._ptable.item(r, 1).text().strip() for x in d._regs)), None)
    if pr is not None:
        loc = d._ptable.item(pr, 1).text().strip()
        d._posture_to_register(pr, 1)
        if d._center_tabs.currentIndex() != 1 or d._reg_search.text() != loc:
            bad("clicking a posture row should jump to that register in the Registers tab")

# 23. register → console cross-link + ASCII-column highlight
if regs:
    ridx = next((i for i, r in enumerate(d._regs) if r[1] == "JTAG_SEC"), 0)
    addr = d._regs[ridx][2]
    d.run_in_console.emit(f"mrd {addr} 1")
    if w.console.input.text() != f"mrd {addr} 1":
        bad("sending a register mrd should populate the console input")
from PySide6.QtCore import Qt as _Qt2
hv.model.set_data(b"\x00" * 16 + b"MATCH"); hv.model.set_highlight(16, 5)
if hv.model.data(hv.model.index(1, 16), _Qt2.BackgroundRole) is None:
    bad("ASCII column should highlight on a matched row")
if hv.model.data(hv.model.index(0, 16), _Qt2.BackgroundRole) is not None:
    bad("ASCII column should NOT highlight an unmatched row")

# 21b. Attack Surface tab: real-posture misuse layer + probe → console
P = d._misuse_posture()
if "jtag_open" not in P: bad("attack-surface should derive jtag_open from the real posture")
d.refresh_attack_surface()
if not d._as_findings: bad("attack surface should surface misuse hypotheses on an open board")
probes = [pr for *_, pr in d._as_findings if pr]
if probes:
    d.run_in_console.emit(probes[0])
    if not w.console.input.text(): bad("a probe should populate the console input")

# 21c. Kill Chain tab: the attack-graph planner renders + follows the board posture
if not hasattr(d, "_kc_reach"): bad("dashboard should have a Kill Chain tab")
d.set_board_posture("zynqmp", {"jtag_open": True})
if "5/5" not in d._kc_reach.text(): bad(f"zynqmp OPEN kill-chain should reach 5/5 (got {d._kc_reach.text()})")
d.set_board_posture("igloo2", {"flashlock": True})
if "4/5" not in d._kc_reach.text(): bad(f"igloo2 kill-chain should reach 4/5 via readback (got {d._kc_reach.text()})")
# 21d. the Kill Chain tab lists the extraction avenues (jtagx.extraction) — incl. no-debug ROM loaders
d.set_board_posture("imx6", {"jtag_locked": True})
from PySide6.QtWidgets import QLabel as _QL2
_kclabels = [l.text() for l in d._kc_host.findChildren(_QL2)]
if not any("EXTRACTION AVENUES" in x for x in _kclabels): bad("Kill Chain should list extraction avenues")
if not any("SDP" in x for x in _kclabels): bad("imx6 extraction should show the SDP ROM-loader avenue")
d.set_board_posture("zynqmp", None)   # restore

# 21e. Shell tab (jtagx.jtagtoshell): goal chips switch paths, and the wedge warning is always visible
if not hasattr(d, "_sh_v"): bad("dashboard should have a Shell tab")
d.set_board_posture("zynqmp", {"jtag_open": True})   # zynqmp posture, but a53 state autodetects separately
d._set_shell_goal("shell")
_shlabels = [l.text() for l in d._sh_host.findChildren(_QL2)]
if not any("Live-patch" in x or "Cold-boot" in x for x in _shlabels):
    bad("Shell tab (goal=shell) should show the live-patch or cold-boot path")
d._set_shell_goal("secret")
_shlabels2 = [l.text() for l in d._sh_host.findChildren(_QL2)]
if not any("Catch the credential" in x for x in _shlabels2):
    bad("Shell tab (goal=secret) should show the catch-in-flight path")
d._set_shell_goal("shell")  # restore

# 24. chain-panel cores → backend-scoped console commands
d.set_backend("openocd")
d._core_cmd("a53-0", "halt")
if "halt" not in w.console.input.text() or "openocd" not in w.console.input.text():
    bad("core Halt under openocd should build an openocd halt command")
d.set_backend("hw_server")
d._core_cmd("r5-0", "halt")
if "xsdb" not in w.console.input.text() or "R5*#0" not in w.console.input.text():
    bad("core Halt under hw_server should target R5#0 via xsdb")

# 25. multi-board: the board selector retargets the Chain page + console soc/cfg + crumb
if w.board_sel.count() < 5: bad("board selector should list the profile registry")
if w.board["soc"] != "zynqmp": bad("default board should be zynqmp")
z7 = next((i for i in range(w.board_sel.count()) if w.board_sel.itemData(i) == "zynq7000"), None)
if z7 is not None:
    w.board_sel.setCurrentIndex(z7)
    if w.chain.soc != "zynq7000": bad("switching board should rebuild the Chain page for that soc")
    if w.console.soc != "zynq7000": bad("switching board should retarget the console soc")
    if "zynq7000" not in (w.console.cfg or ""): bad("switching board should retarget the console cfg")
    if "Zynq-7000" not in w._crumb.text(): bad("switching board should update the crumb")
    if "Zynq-7000" not in w.dash._hero_board.text(): bad("switching board should update the hero identity")
# board-aware Unlock panel: SmartFusion2 posture toggle → its lock model appears
sf2 = next((i for i in range(w.board_sel.count()) if w.board_sel.itemData(i) == "smartfusion2"), None)
if sf2 is not None:
    w.board_sel.setCurrentIndex(sf2)
    upx = w.stack.widget(1)
    if not any("debug" in b.text() for b in upx._posture_btns):
        bad("SmartFusion2 should offer an 'M3 debug locked' posture toggle")
    tog = next(b for b in upx._posture_btns if "debug" in b.text()); tog.setChecked(True)
    if not any("M3 debug lock" in k for k in upx._cards):
        bad("asserting SF2 debug-locked should surface the M3 debug lock card")
    # the Attack-Surface tab should FOLLOW the board + asserted posture (board-aware)
    if getattr(w.dash, "_as_soc", "zynqmp") != "smartfusion2":
        bad("Attack Surface should follow the active board (smartfusion2)")
    if not any(f[3] == "sf2-security-policy-flash" for f in w.dash._as_findings):
        bad("board-aware Attack Surface should surface the SF2 design-primitive hypothesis")
    # board-generic DASHBOARD: Posture/Registers tabs + hero tiles follow the board (not ZynqMP)
    if getattr(w.dash, "_board_soc", "") != "smartfusion2":
        bad("dashboard should track the active board soc")
    if w._dap_badge.text() == "● DAP OPEN":
        bad("non-ZynqMP DAP badge should read UNKNOWN, not OPEN")
    if getattr(w.reports, "_soc", "") != "smartfusion2":
        bad("Reports Generate should target the active board soc")
    if w.dash._center_tabs.tabText(1) != "▦  Registers":
        bad("non-ZynqMP Registers tab should be the honest generic view (no §-sweep count)")
    _tiles = dict((t[0], t[1]) for t in w.dash._tile_data())
    if _tiles["POSTURE"] != "?" or _tiles["CAPABILITIES"] == "0":
        bad("non-ZynqMP hero tiles should read POSTURE=? and a nonzero lock-mechanism count")
    # the security-model view is built from the unlock engine's lock model for this soc
    from jtagx.unlock import security_model as _sm
    if not _sm("smartfusion2"):
        bad("security_model should return the SF2 lock mechanisms for the generic Posture view")
    # switching BACK to the home board restores the real ZCU102 capture (register count returns)
    zb = next(i for i in range(w.board_sel.count()) if w.board_sel.itemData(i) == "zynqmp")
    w.board_sel.setCurrentIndex(zb); app.processEvents()
    if w.dash._board_soc != "zynqmp" or "Registers (" not in w.dash._center_tabs.tabText(1):
        bad("switching back to ZynqMP should restore the real §1–16 register capture")

# 26. THE Run Enumerate button, actually clicked, through mock-openocd.py (the $OPENOCD indirection
# every other live command already respects — this one used to hardcode a literal "openocd" argv,
# bypassing both the mock and the transport backend gate; regression-guard that fix here).
import glob as _glob, time as _t2
_before = set(_glob.glob(_os.path.join(qt_spike.ROOT, "reports", "raw-*.json")))
w.dash.set_backend("openocd")
w.console.clear()
w.dash.start_enumerate()
if not w.dash.runner.busy() and w.dash.runner.proc is None:
    bad("start_enumerate under the OpenOCD backend + $OPENOCD=mock should actually launch a process")
_t0 = _t2.time()
while w.dash.runner.busy() and _t2.time() - _t0 < 15:
    app.processEvents(); _t2.sleep(0.03)
app.processEvents()
_after = set(_glob.glob(_os.path.join(qt_spike.ROOT, "reports", "raw-*.json")))
_new = _after - _before
if not _new: bad("clicking Run Enumerate should produce a fresh reports/raw-*.json via the mock")
if w.dash._center_tabs.currentIndex() != 0:
    bad("a successful enumerate should land the operator on the decoded Posture tab (cross-page flow)")
if "Enumeration decoded" not in w.console.text.toPlainText():
    bad("a successful enumerate should announce the decode in the console")
for _f in _new:
    _os.remove(_f)   # don't leave test-generated captures in the real reports/ dir

# 26b. the SAME button, under the hw_server backend — must BLOCK, not silently try to run "openocd"
w.dash.set_backend("hw_server")
w.console.clear()
_before2 = set(_glob.glob(_os.path.join(qt_spike.ROOT, "reports", "raw-*.json")))
w.dash.start_enumerate()
if w.dash.runner.busy(): bad("Run Enumerate under hw_server must NOT launch a process")
if "OpenOCD backend" not in w.console.text.toPlainText():
    bad("Run Enumerate under hw_server should explain why it's blocked")
_after2 = set(_glob.glob(_os.path.join(qt_spike.ROOT, "reports", "raw-*.json")))
if _after2 != _before2: bad("a blocked enumerate must not produce any capture file")
w.dash.set_backend("openocd")   # restore

# 26c. board-generic Enumerate: a Cortex-M board (stm32f4, has cortexm-protect.tcl wired) runs through
# the SAME $OPENOCD mock indirection, and the REAL parsed measured posture (jtagx.cortexm_posture) lands
# in _cm_posture / the Posture tab / the console — not the ZynqMP JSON-capture path, and not just the
# static security-model fallback (closes the "Dashboard always shows the ZCU102 capture" gap).
stm32 = next((i for i in range(w.board_sel.count()) if w.board_sel.itemData(i) == "stm32f4"), None)
if stm32 is not None:
    w.board_sel.setCurrentIndex(stm32); app.processEvents()
    with open(_os.environ["JTAGX_MOCK_STATE"], "w") as _f:
        _f.write("locked")   # deterministic regardless of what earlier checks left the mock state as
    w.console.clear()
    w.dash.start_enumerate()
    _t0 = _t2.time()
    while w.dash.runner.busy() and _t2.time() - _t0 < 15:
        app.processEvents(); _t2.sleep(0.03)
    app.processEvents()
    cm = w.dash._cm_posture.get("stm32f4")
    if not cm:
        bad("board-generic Enumerate should populate _cm_posture for stm32f4 via the mock")
    elif cm["verdict"] != "LOCKED":
        bad(f"stm32f4 LOCKED-state mock should parse to verdict LOCKED, got {cm['verdict']}")
    if w.dash._center_tabs.currentIndex() != 0:
        bad("a successful board-generic posture measurement should land on the Posture tab")
    if "Posture measured" not in w.console.text.toPlainText():
        bad("a successful board-generic posture measurement should announce it in the console")
    if "MEASURED" not in w.dash._center_tabs.widget(0).findChild(qt_spike.QLabel).text():
        bad("the generic Posture tab should render a MEASURED section, not only the security-model fallback")
    # flip the mock to OPEN and re-run — proves the verdict is live-parsed, not cached from the first run
    with open(_os.environ["JTAGX_MOCK_STATE"], "w") as _f:
        _f.write("open")
    w.dash.start_enumerate()
    _t0 = _t2.time()
    while w.dash.runner.busy() and _t2.time() - _t0 < 15:
        app.processEvents(); _t2.sleep(0.03)
    app.processEvents()
    cm2 = w.dash._cm_posture.get("stm32f4")
    if not cm2 or cm2["verdict"] != "OPEN":
        bad(f"stm32f4 OPEN-state mock should re-parse to verdict OPEN, got {cm2['verdict'] if cm2 else None}")
    zb3 = next(i for i in range(w.board_sel.count()) if w.board_sel.itemData(i) == "zynqmp")
    w.board_sel.setCurrentIndex(zb3); app.processEvents()
    if w.dash._board_soc != "zynqmp":
        bad("switching back to ZynqMP after a Cortex-M posture run should restore the ZynqMP identity")

# 27. guided-path stepper (Enumerate -> Posture -> Extract -> Analyze): renders, tracks real state,
# and each step navigates. On the real (mutable) reports/+dumps/ dir this board has a capture, dumps,
# and reports, so all four should read done — assert the mechanism, not a specific board snapshot.
if not hasattr(d, "_step_btns") or len(d._step_btns) != 4:
    bad("dashboard should have a 4-step guided-path stepper")
steps, current = d._stepper_state()
if [s[0] for s in steps] != ["① Enumerate", "② Posture", "③ Extract", "④ Analyze"]:
    bad(f"stepper labels wrong: {[s[0] for s in steps]}")
if current > 4 or current < 0:
    bad(f"stepper current index out of range: {current}")
d._step_btns[1].click()   # "② Posture" should jump to the Posture tab (index 0)
if d._center_tabs.currentIndex() != 0: bad("clicking the Posture step should switch to the Posture tab")
d._step_btns[2].click()   # "③ Extract" should jump to the Kill Chain tab (index 4)
if d._center_tabs.currentIndex() != 4: bad("clicking the Extract step should switch to the Kill Chain tab")
seen3 = []
d.navigate.connect(lambda i: seen3.append(i))
d._step_btns[3].click()   # "④ Analyze" should navigate to the Reports PAGE (not a center tab)
if seen3 != [4]: bad("clicking the Analyze step should navigate to the Reports page")

# 28. side-panel auto-collapse on task-focused tabs, auto-expand on browse tabs, manual pin overrides
if not hasattr(d, "_chain_frame") or not hasattr(d, "_caps_frame"):
    bad("dashboard should track chain/caps frame handles for collapse")
d._center_tabs.setCurrentIndex(0)   # Posture — a browse tab
if d._chain_frame.isHidden() or d._caps_frame.isHidden():
    bad("side panels should be visible on a browse tab (Posture)")
d._center_tabs.setCurrentIndex(4)   # Kill Chain — a focused tab
if not d._chain_frame.isHidden() or not d._caps_frame.isHidden():
    bad("side panels should auto-collapse on a task-focused tab (Kill Chain)")
d._center_tabs.setCurrentIndex(6)   # Shell — also focused
if not d._chain_frame.isHidden() or not d._caps_frame.isHidden():
    bad("side panels should auto-collapse on Shell too")
d._center_tabs.setCurrentIndex(0)   # back to Posture — should re-expand
if d._chain_frame.isHidden() or d._caps_frame.isHidden():
    bad("side panels should auto-re-expand switching back to a browse tab")
# manual pin: explicitly hide the chain panel, then switching tabs must NOT override that choice
d._chain_toggle.setChecked(False); d._toggle_chain_panel()
if not d._chain_frame.isHidden(): bad("manual toggle should hide the chain panel")
d._center_tabs.setCurrentIndex(4)   # a focused tab — chain panel already hidden, caps still auto-collapses
if not d._chain_frame.isHidden(): bad("manually-pinned-hidden chain panel should stay hidden on any tab")
d._center_tabs.setCurrentIndex(0)   # back to a browse tab — pin should still win over auto-expand
if not d._chain_frame.isHidden():
    bad("a manual pin must survive a tab switch (auto-behavior should not override an explicit choice)")
d._chain_toggle.setChecked(True); d._toggle_chain_panel()   # restore
if d._chain_frame.isHidden(): bad("re-toggling should show the chain panel again")
d._chain_pinned = None   # release the pin so later checks see normal auto-behavior
# regression guard: the toggles must NOT be QTabWidget corner widgets (that ate tab-bar width and
# pushed tabs into scroll-arrow overflow) — they're a separate always-visible outer rail instead.
from PySide6.QtCore import Qt as _QtCorner
if d._center_tabs.cornerWidget(_QtCorner.TopLeftCorner) is not None:
    bad("side-panel toggle must not be a tab-bar corner widget (regresses to tab overflow)")
if d._center_tabs.cornerWidget(_QtCorner.TopRightCorner) is not None:
    bad("side-panel toggle must not be a tab-bar corner widget (regresses to tab overflow)")

# 29. extraction -> Memory feedback loop: a console-run command finishing with MORE dumps than the
# Kill-Chain-tab's baseline surfaces a banner with a working "Open in Memory" link; revisiting the
# tab (refresh_killchain) resets the baseline and clears it.
d._center_tabs.setCurrentIndex(4)   # (re)build the Kill Chain tab, sets a fresh baseline
if not hasattr(d, "_kc_dump_banner") or not hasattr(d, "_kc_dump_baseline"):
    bad("Kill Chain tab should track a dump baseline + banner")
if not d._kc_dump_banner.isHidden(): bad("dump banner should start hidden")
_orig_count_dumps = qt_spike.count_dumps
qt_spike.count_dumps = lambda: d._kc_dump_baseline + 2
try:
    d._on_run_done(0)   # simulate BUS.run_done firing after an extraction avenue's command finished
    if d._kc_dump_banner.isHidden(): bad("2 new dumps should show the Kill-Chain banner")
    if "2 new dump" not in d._kc_dump_msg.text(): bad(f"banner text wrong: {d._kc_dump_msg.text()}")
    seen4 = []
    d.navigate.connect(lambda i: seen4.append(i))
    from PySide6.QtWidgets import QPushButton as _QPB
    openbtn = next(b for b in d._kc_dump_banner.findChildren(_QPB) if "Memory" in b.text())
    openbtn.click()
    if seen4 != [3]: bad("the banner's Open-in-Memory button should navigate to the Memory page")
finally:
    qt_spike.count_dumps = _orig_count_dumps
d.refresh_killchain()
if not d._kc_dump_banner.isHidden(): bad("refresh_killchain should clear a stale banner and reset the baseline")
# a console command finishing with NO new dumps must not show a stale/false banner
d._on_run_done(0)
if not d._kc_dump_banner.isHidden(): bad("no new dumps should NOT show the banner")

w.dash.stop()
print("  gui end-to-end OK (5 pages, hero real, tabs filled, nav flow, memory selector, unlock plans)")
PY

echo "PASS: gui-smoketest (offscreen end-to-end)"
