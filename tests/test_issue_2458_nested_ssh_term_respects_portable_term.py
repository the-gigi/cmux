#!/usr/bin/env python3
"""
Regression: cmux's bundled Ghostty zsh integration must preserve a user-selected
portable TERM across SSH hops.

When the active local TERM is xterm-256color, the SSH wrapper should keep that
TERM for remote sessions and skip the xterm-ghostty terminfo bootstrap. This
avoids deeper nested hops inheriting xterm-ghostty on hosts that do not also
run Ghostty shell integration.
"""

from __future__ import annotations

import os
import pty
import select
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

PROMPT_MARKER = b"cmux-ready> "


def _write_executable(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")
    path.chmod(0o755)


def _write_prompting_zshrc(path: Path, extra_content: str = "") -> None:
    path.write_text(
        (
            """
setopt prompt_percent
PROMPT='cmux-ready> '
RPROMPT=''
"""
            + extra_content
        ).lstrip(),
        encoding="utf-8",
    )


def _run_case(
    *,
    root: Path,
    wrapper_dir: Path,
    zsh_path: str,
    features: str,
    term: str,
    expect_term: str,
    expect_infocmp: bool,
    zshrc_extra_content: str = "",
) -> tuple[bool, str]:
    base = Path(tempfile.mkdtemp(prefix="cmux_issue_2458_"))
    try:
        home = base / "home"
        orig = base / "orig-zdotdir"
        fakebin = base / "fakebin"
        term_out = base / "term.txt"
        infocmp_out = base / "infocmp.txt"

        home.mkdir(parents=True, exist_ok=True)
        orig.mkdir(parents=True, exist_ok=True)
        fakebin.mkdir(parents=True, exist_ok=True)

        for filename in (".zshenv", ".zprofile"):
            (orig / filename).write_text("", encoding="utf-8")
        _write_prompting_zshrc(orig / ".zshrc", extra_content=zshrc_extra_content)

        _write_executable(
            fakebin / "ssh",
            """#!/bin/sh
if [ "$1" = "-G" ]; then
  printf 'user nested\\n'
  printf 'hostname nested.example\\n'
  exit 0
fi
printf '%s\\n' "${TERM:-}" > "$CMUX_TEST_TERM_OUT"
printf '%s\\n' "$*" > "$CMUX_TEST_SSH_ARGS_OUT"
exit 0
""",
        )
        _write_executable(
            fakebin / "infocmp",
            """#!/bin/sh
printf 'called\\n' >> "$CMUX_TEST_INFOCMP_OUT"
exit "${CMUX_TEST_INFOCMP_STATUS:-1}"
""",
        )

        env = dict(os.environ)
        env["HOME"] = str(home)
        env["TERM"] = term
        env["PATH"] = f"{fakebin}:{env.get('PATH', '')}"
        env["ZDOTDIR"] = str(wrapper_dir)
        env["GHOSTTY_ZSH_ZDOTDIR"] = str(orig)
        env["GHOSTTY_RESOURCES_DIR"] = str(root / "ghostty" / "src")
        env["CMUX_SHELL_INTEGRATION_DIR"] = str(wrapper_dir)
        env["CMUX_LOAD_GHOSTTY_ZSH_INTEGRATION"] = "1"
        env["CMUX_SHELL_INTEGRATION"] = "0"
        env["GHOSTTY_SHELL_FEATURES"] = features
        env["CMUX_TEST_TERM_OUT"] = str(term_out)
        env["CMUX_TEST_SSH_ARGS_OUT"] = str(base / "ssh-args.txt")
        env["CMUX_TEST_INFOCMP_OUT"] = str(infocmp_out)
        env["CMUX_TEST_INFOCMP_STATUS"] = "1"
        env.pop("GHOSTTY_BIN_DIR", None)
        env.pop("TERMINFO", None)

        # Ghostty installs the live ssh() wrapper during deferred init on the
        # first prompt, so this regression test must drive a prompted PTY shell.
        master, slave = pty.openpty()
        proc = subprocess.Popen(
            [zsh_path, "-d", "-i"],
            cwd=str(root),
            stdin=slave,
            stdout=slave,
            stderr=slave,
            env=env,
            close_fds=True,
        )
        os.close(slave)

        output = bytearray()
        saw_prompt = False
        ssh_sent = False
        exit_sent = False
        timed_out = False
        try:
            deadline = time.time() + 8
            while time.time() < deadline:
                if proc.poll() is not None:
                    break

                readable, _, _ = select.select([master], [], [], 0.2)
                if master in readable:
                    try:
                        chunk = os.read(master, 4096)
                    except OSError:
                        break
                    if not chunk:
                        break
                    output.extend(chunk)

                prompt_count = output.count(PROMPT_MARKER)
                if prompt_count >= 1:
                    saw_prompt = True

                if saw_prompt and not ssh_sent:
                    os.write(master, b"ssh nested.example\n")
                    ssh_sent = True
                    continue

                if ssh_sent and not exit_sent and term_out.exists() and prompt_count >= 2:
                    os.write(master, b"exit\n")
                    exit_sent = True
                    continue
            else:
                timed_out = True
        finally:
            try:
                if proc.poll() is None:
                    if not exit_sent:
                        try:
                            os.write(master, b"exit\n")
                        except OSError:
                            pass
                    try:
                        proc.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        proc.kill()
                        proc.wait(timeout=5)
            finally:
                os.close(master)

        combined = output.decode("utf-8", errors="replace").strip()
        if timed_out:
            return False, f"interactive zsh session timed out: {combined}"
        if proc.returncode != 0:
            return False, f"interactive zsh exited non-zero rc={proc.returncode}: {combined}"
        if not saw_prompt:
            return False, f"did not observe first interactive prompt: {combined}"
        if not ssh_sent:
            return False, f"did not invoke ssh after first interactive prompt: {combined}"

        if not term_out.exists():
            return False, f"fake ssh did not record TERM: {combined}"

        recorded_term = term_out.read_text(encoding="utf-8").strip()
        if recorded_term != expect_term:
            return False, f"expected remote TERM={expect_term!r}, got {recorded_term!r}"

        infocmp_called = infocmp_out.exists()
        if infocmp_called != expect_infocmp:
            return False, f"expected infocmp_called={expect_infocmp}, got {infocmp_called}"

        return True, ""
    finally:
        shutil.rmtree(base, ignore_errors=True)


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    wrapper_dir = root / "Resources" / "shell-integration"
    if not (wrapper_dir / ".zshenv").exists():
        print(f"SKIP: missing wrapper .zshenv at {wrapper_dir}")
        return 0

    zsh_path = shutil.which("zsh")
    if zsh_path is None:
        print("SKIP: zsh not installed")
        return 0

    ok, detail = _run_case(
        root=root,
        wrapper_dir=wrapper_dir,
        zsh_path=zsh_path,
        features="ssh-env,ssh-terminfo",
        term="xterm-256color",
        expect_term="xterm-256color",
        expect_infocmp=False,
    )
    if not ok:
        print(f"FAIL: portable TERM case failed: {detail}")
        return 1

    ok, detail = _run_case(
        root=root,
        wrapper_dir=wrapper_dir,
        zsh_path=zsh_path,
        features="ssh-env",
        term="xterm-ghostty",
        expect_term="xterm-256color",
        expect_infocmp=False,
    )
    if not ok:
        print(f"FAIL: ssh-env-only fallback case failed: {detail}")
        return 1

    ok, detail = _run_case(
        root=root,
        wrapper_dir=wrapper_dir,
        zsh_path=zsh_path,
        features="ssh-env,ssh-terminfo",
        term="tmux-256color",
        expect_term="xterm-256color",
        expect_infocmp=False,
    )
    if not ok:
        print(f"FAIL: tmux/custom TERM normalization case failed: {detail}")
        return 1

    ok, detail = _run_case(
        root=root,
        wrapper_dir=wrapper_dir,
        zsh_path=zsh_path,
        features="ssh-env,ssh-terminfo",
        term="xterm-ghostty",
        expect_term="xterm-256color",
        expect_infocmp=True,
    )
    if not ok:
        print(f"FAIL: xterm-ghostty fallback case failed: {detail}")
        return 1

    ok, detail = _run_case(
        root=root,
        wrapper_dir=wrapper_dir,
        zsh_path=zsh_path,
        features="ssh-env,ssh-terminfo",
        term="xterm-ghostty",
        expect_term="xterm-ghostty",
        expect_infocmp=False,
        zshrc_extra_content="""
export GHOSTTY_SHELL_FEATURES='title,cursor'
""",
    )
    if not ok:
        print(f"FAIL: user opt-out case failed: {detail}")
        return 1

    print(
        "PASS: Ghostty zsh SSH wrapper preserves portable TERM, falls back from xterm-ghostty, "
        "and respects interactive-shell opt-outs"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
