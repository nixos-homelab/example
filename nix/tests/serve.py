# Test script for `vm-test start`: boots the machines, keeps them running and runs each script vm-test exec writes to the in FIFO
# in the test script's namespace, then reports ok or fail on the out FIFO. Exits on `raise SystemExit`.
import os
import traceback

state_dir = os.environ["VM_TEST_DIR"]
# Only the host's own VM is prebuilt; other nodes of its test start on first use
boot_prebuilt(next(machine for machine in machines if machine.name == os.environ["VM_TEST_HOST"]))
with open(f"{state_dir}/out", "w") as out:
    out.write("ok")
while True:
    with open(f"{state_dir}/in") as script_file:
        script = script_file.read()
    status = "ok"
    try:
        exec(script, globals())
    except Exception:
        traceback.print_exc()
        status = "fail"
    with open(f"{state_dir}/out", "w") as out:
        out.write(status)
