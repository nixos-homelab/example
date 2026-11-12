# Prepended to every test script of a prebuilt VM
import os

# QEMU's user network advertises site-local fec0::/64, which k3s doesn't take as a node IP. A global prefix makes the
# dual-stack cluster come up like on the real network. The machines' start scripts read it when they start
os.environ.setdefault("QEMU_NET_OPTS", "ipv6-prefix=2001:db8:1::,ipv6-prefixlen=64")


def boot_prebuilt(machine):
    """Boots a fresh prebuilt VM through its first boot: lanzaboote prepares the Secure Boot keys and reboots,
    systemd-boot enrolls them and reboots again"""
    machine.start(allow_reboot=True)
    machine.wait_for_console_text("Custom Secure Boot keys successfully enrolled")
    machine.wait_for_qmp_event(lambda event: event["event"] == "RESET")
    # Drop what the first boot's backdoor said, or the driver takes its greeting for the new boot's
    machine.shell.setblocking(False)
    try:
        while machine.shell.recv(4096):
            pass
    except BlockingIOError:
        pass
    machine.shell.setblocking(True)
    machine.connected = False
    machine.wait_for_unit("multi-user.target")
