"""Add the research executable only to a disposable, pinned FluidAudio clone."""
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(sys.argv[1]).resolve()
revision = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
assert revision == "5c19d5e12320e22bbfb7a1877b089d2665a69add", revision
package = root / "Package.swift"
source = package.read_text()
target = '.executableTarget(name: "RomaASRBenchmark", dependencies: ["FluidAudio"], path: "RomaASRBenchmark"),'
assert 'name: "RomaASRBenchmark"' not in source, "Already installed"
anchor = '\n    targets: [\n'
assert source.count(anchor) == 1
package.write_text(source.replace(anchor, anchor + '        ' + target + '\n', 1))
(root / "RomaASRBenchmark").mkdir()
shutil.copyfile(Path(__file__).with_name("Probe.swift"), root / "RomaASRBenchmark/Probe.swift")
