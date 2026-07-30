"""Isolated WeasyPrint renderer — runs as a throwaway child process.

WHY THIS RUNS OUT OF PROCESS
----------------------------
Rendering used to abort the whole ai-service with 0xC0000374
(STATUS_HEAP_CORRUPTION), taking every in-flight consultation with it. Doing it
in a child means the blast radius is one process: the parent sees a non-zero
exit code and reports "report generation unavailable" instead of vanishing.
The isolation is kept even though the crash itself is now fixed, because a
native abort can never be caught in-process.

WHY IT USED TO CRASH  (root cause, fixed below)
-----------------------------------------------
weasyprint/text/ffi.py hardcodes a DLL search directory when
WEASYPRINT_DLL_DIRECTORIES is unset:

    dll_directories = os.getenv('WEASYPRINT_DLL_DIRECTORIES',
        'C:\\msys64\\mingw64\\bin;C:\\Program Files\\GTK3-Runtime Win64\\bin')

...and calls os.add_dll_directory() on each. Directories registered that way
outrank PATH when Windows resolves a DLL's dependencies. On this machine the
Pango stack lives in msys2's UCRT64 root, so the result was a split load:

    libpango / libgobject / libfontconfig   -> C:\\msys64\\ucrt64\\bin   (ucrtbase.dll)
    libglib / libharfbuzz / libfreetype     -> C:\\msys64\\mingw64\\bin  (msvcrt.dll)

UCRT64 and MINGW64 binaries link against *different C runtimes*, so they have
different heaps. One library malloc'd a GLib object and another free'd it on
the wrong heap — textbook heap corruption, which is why the exit code varied
between 0xC0000374 and 0xC0000005 and why it appeared to strike at random.
Nothing in msys2 had actually been updated; heap corruption is simply
non-deterministic, so the same latent mix looked fine for a while.

The fix is to pin every native library to a single msys2 root, via both
WEASYPRINT_DLL_DIRECTORIES (dependency resolution) and PATH (explicit dlopen).

Protocol: a JSON object on stdin -> {"html": str, "base_url": str, "out_path": str}
Exit 0 on success, non-zero with a message on stderr otherwise.
Run with --selfcheck to verify the native stack without rendering a report.
"""

import ctypes
import json
import os
import sys

# Every library WeasyPrint pulls in for text layout. All of these must come
# from the same root or the process is living on borrowed time.
_CORE_DLLS = (
    "libpango-1.0-0.dll",
    "libpangoft2-1.0-0.dll",
    "libgobject-2.0-0.dll",
    "libglib-2.0-0.dll",
    "libgmodule-2.0-0.dll",
    "libharfbuzz-0.dll",
    "libfontconfig-1.dll",
    "libfreetype-6.dll",
)

# A root only counts if it can satisfy the whole stack; a partial match is what
# caused the split load in the first place.
_REQUIRED_FOR_ROOT = _CORE_DLLS

_CANDIDATE_ROOTS = (
    r"C:\msys64\ucrt64\bin",
    r"C:\msys64\mingw64\bin",
    r"C:\Program Files\GTK3-Runtime Win64\bin",
)


def pin_native_stack() -> str | None:
    """Force the GLib/Pango stack to load from one msys2/GTK root.

    Returns the chosen directory, or None on a non-Windows platform or when no
    complete root exists. An operator-supplied WEASYPRINT_DLL_DIRECTORIES is
    respected and left alone.
    """
    if os.name != "nt":
        return None

    chosen = os.environ.get("WEASYPRINT_DLL_DIRECTORIES")
    if not chosen:
        for root in _CANDIDATE_ROOTS:
            if all(os.path.exists(os.path.join(root, dll)) for dll in _REQUIRED_FOR_ROOT):
                chosen = root
                break
    if not chosen or not os.path.isdir(chosen):
        return None

    # Both channels must agree: add_dll_directory decides where dependencies
    # come from, PATH decides where WeasyPrint's own dlopen-by-name lands.
    # Setting only one of them is what produced the mixed load.
    os.environ["WEASYPRINT_DLL_DIRECTORIES"] = chosen
    path = os.environ.get("PATH", "")
    if chosen.lower() not in path.lower().split(os.pathsep):
        os.environ["PATH"] = chosen + os.pathsep + path
    return chosen


def _module_path(name: str):
    k32 = ctypes.windll.kernel32
    k32.GetModuleHandleW.restype = ctypes.c_void_p
    k32.GetModuleHandleW.argtypes = [ctypes.c_wchar_p]
    handle = k32.GetModuleHandleW(name)
    if not handle:
        return None
    k32.GetModuleFileNameW.restype = ctypes.c_uint32
    k32.GetModuleFileNameW.argtypes = [ctypes.c_void_p, ctypes.c_wchar_p, ctypes.c_uint32]
    buf = ctypes.create_unicode_buffer(4096)
    k32.GetModuleFileNameW(handle, buf, len(buf))
    return buf.value


def inspect_native_stack() -> dict:
    """Where did each native library actually come from?

    Turns a future silent heap corruption into a explicit, diagnosable error:
    if these ever span more than one directory again, the mix is reported by
    name instead of crashing at a random later allocation.
    """
    if os.name != "nt":
        return {"platform": "non-windows", "mixed": False, "modules": {}}

    modules = {}
    for dll in _CORE_DLLS:
        path = _module_path(dll)
        if path:
            modules[dll] = path

    roots = {os.path.dirname(p).lower() for p in modules.values()}
    return {
        "modules": modules,
        "roots": sorted(roots),
        "mixed": len(roots) > 1,
        "pinned_to": os.environ.get("WEASYPRINT_DLL_DIRECTORIES"),
    }


def _describe(info: dict) -> str:
    lines = [f"native libraries span {len(info['roots'])} directories: {info['roots']}"]
    for dll, path in sorted(info["modules"].items()):
        lines.append(f"    {dll:26} {path}")
    lines.append(
        "  UCRT64 and MINGW64 builds use different C runtimes and therefore "
        "different heaps; mixing them corrupts memory. Set "
        "WEASYPRINT_DLL_DIRECTORIES to a single root containing the whole stack."
    )
    return "\n".join(lines)


def main() -> int:
    selfcheck = "--selfcheck" in sys.argv

    pinned = pin_native_stack()

    if not selfcheck:
        try:
            payload = json.load(sys.stdin)
        except Exception as exc:  # noqa: BLE001
            print(f"bad payload: {exc}", file=sys.stderr)
            return 2

    try:
        # Imported here, not at module scope, so the parent never loads the
        # native libraries into its own address space.
        from weasyprint import HTML
    except Exception as exc:  # noqa: BLE001
        print(f"weasyprint import failed: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 4

    info = inspect_native_stack()
    if info.get("mixed"):
        # Refuse rather than corrupt the heap and die somewhere unrelated.
        print("MIXED NATIVE RUNTIME: " + _describe(info), file=sys.stderr)
        return 5

    if selfcheck:
        print(json.dumps({"pinned_to": pinned, **info}, indent=2))
        return 0

    try:
        HTML(string=payload["html"], base_url=payload["base_url"]).write_pdf(
            payload["out_path"]
        )
    except Exception as exc:  # noqa: BLE001
        print(f"{type(exc).__name__}: {exc}", file=sys.stderr)
        return 3

    return 0


if __name__ == "__main__":
    sys.exit(main())
