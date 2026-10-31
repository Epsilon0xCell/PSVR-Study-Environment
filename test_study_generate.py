"""Tests for study-generate.sh.

The help, argument, and missing file paths need no media at all. The
encode test does run for real: it builds two one second test clips
with ffmpeg's lavfi source and checks that the script produces a
1920x1080 output from them. If ffmpeg is not installed the encode
test skips itself instead of failing.
"""

import pathlib
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).with_name("study-generate.sh")


def run(args, cwd):
    return subprocess.run(
        ["bash", str(SCRIPT), *args], capture_output=True, text=True, cwd=cwd
    )


class ArgumentTests(unittest.TestCase):
    def test_bash_syntax(self):
        out = subprocess.run(["bash", "-n", str(SCRIPT)], capture_output=True, text=True)
        self.assertEqual(out.returncode, 0, out.stderr)

    def test_help_exits_0_without_ffmpeg_work(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = run(["--help"], tmp)
        self.assertEqual(out.returncode, 0)
        self.assertIn("Usage:", out.stdout)

    def test_missing_inputs_exit_1_and_name_the_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = run([], tmp)
        self.assertEqual(out.returncode, 1)
        self.assertIn("vr.mp4 not found", out.stdout + out.stderr)

    def test_too_many_arguments_exit_1(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = run(["a", "b", "c", "d"], tmp)
        self.assertEqual(out.returncode, 1)


@unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "ffmpeg not installed")
class EncodeTests(unittest.TestCase):
    def make_clip(self, folder, name, size):
        subprocess.run(
            [
                "ffmpeg", "-y", "-v", "error",
                "-f", "lavfi", "-i", f"testsrc=duration=1:size={size}:rate=30",
                "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
                "-shortest", str(pathlib.Path(folder) / name),
            ],
            check=True,
            capture_output=True,
        )

    def test_real_encode_produces_1920x1080_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.make_clip(tmp, "vr.mp4", "640x360")
            self.make_clip(tmp, "non360.mp4", "320x180")
            out = run([], tmp)
            self.assertEqual(out.returncode, 0, out.stderr[-2000:])
            output = pathlib.Path(tmp) / "output.mp4"
            self.assertTrue(output.exists())
            probe = subprocess.run(
                [
                    "ffprobe", "-v", "error", "-select_streams", "v:0",
                    "-show_entries", "stream=width,height",
                    "-of", "csv=p=0", str(output),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(probe.stdout.strip(), "1920,1080")

    def test_output_naming_an_input_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.make_clip(tmp, "vr.mp4", "640x360")
            self.make_clip(tmp, "non360.mp4", "320x180")
            out = run(["vr.mp4", "non360.mp4", "vr.mp4"], tmp)
            self.assertEqual(out.returncode, 1)
            self.assertIn("also an input file", out.stdout + out.stderr)


if __name__ == "__main__":
    unittest.main()
