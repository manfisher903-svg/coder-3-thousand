"""Detect the language of scanned text and translate findings to English.

Privacy first: translation is done ENTIRELY OFFLINE using the optional
`argostranslate` engine (plus a downloaded language model). Email content —
which can contain SSNs, passwords, etc. — is NEVER sent to an online service.

- Language detection uses `langdetect` (small, offline) when available.
- Translation uses `argostranslate` only if it's installed AND a model for the
  source language is present. Otherwise findings are just labelled with the
  detected language (no translation), and the app stays fully offline/light.

Enable offline translation (optional):
    pip install argostranslate
    python -m scanner.translate --install es fr de        # the languages you want
"""

from __future__ import annotations

from typing import Optional, Tuple

_LANG_NAMES = {
    "en": "English", "es": "Spanish", "fr": "French", "de": "German",
    "it": "Italian", "pt": "Portuguese", "nl": "Dutch", "ru": "Russian",
    "zh": "Chinese", "zh-cn": "Chinese", "zh-tw": "Chinese", "ja": "Japanese",
    "ko": "Korean", "ar": "Arabic", "hi": "Hindi", "tr": "Turkish",
    "pl": "Polish", "vi": "Vietnamese", "th": "Thai", "he": "Hebrew",
    "sv": "Swedish", "uk": "Ukrainian", "el": "Greek", "ro": "Romanian",
    "id": "Indonesian", "fa": "Persian", "cs": "Czech", "da": "Danish",
    "fi": "Finnish", "no": "Norwegian", "hu": "Hungarian", "bg": "Bulgarian",
    "tl": "Tagalog", "ca": "Catalan",
}


def language_name(code: str) -> str:
    code = (code or "en").lower()
    return _LANG_NAMES.get(code, code.upper())


def detect_language(text: str) -> Tuple[str, str]:
    """Return (code, human-readable name). Defaults to English when unsure."""
    t = (text or "").strip()
    if len(t) < 12:
        return ("en", "English")
    try:
        from langdetect import detect, DetectorFactory  # type: ignore
        DetectorFactory.seed = 0
        code = (detect(t) or "en").lower()
    except Exception:
        return ("en", "English")
    return (code, language_name(code))


def _argos_code(src: str) -> str:
    src = (src or "").lower()
    if src.startswith("zh"):
        return "zh"
    return src[:2]


def translate_to_english(text: str, src: Optional[str] = None) -> Optional[str]:
    """Offline-translate `text` to English, or None if not possible/needed."""
    t = (text or "").strip()
    if not t:
        return None
    if src is None:
        src, _ = detect_language(t)
    if (src or "en").startswith("en"):
        return None
    try:
        import argostranslate.translate as _at  # type: ignore
    except Exception:
        return None
    try:
        out = _at.translate(t, _argos_code(src), "en")
    except Exception:
        return None
    if out and out.strip() and out.strip() != t:
        return out.strip()
    return None


def _install_models(codes) -> int:
    """Download offline translation models for the given language codes."""
    import argostranslate.package as pkg  # type: ignore
    pkg.update_package_index()
    available = pkg.get_available_packages()
    installed = 0
    for code in codes:
        c = _argos_code(code)
        match = next((p for p in available
                      if p.from_code == c and p.to_code == "en"), None)
        if match:
            print(f"  downloading {c} -> en ...")
            pkg.install_from_path(match.download())
            installed += 1
        else:
            print(f"  (no {c} -> en model available)")
    return installed


def main(argv=None) -> int:
    import sys
    argv = argv if argv is not None else sys.argv[1:]
    if argv and argv[0] == "--install":
        codes = argv[1:] or ["es", "fr", "de"]
        try:
            n = _install_models(codes)
        except Exception as exc:  # noqa: BLE001
            print(f"[!] Could not install models: {exc}")
            print("    Make sure argostranslate is installed: pip install argostranslate")
            return 1
        print(f"[+] Installed {n} offline translation model(s).")
        return 0
    print("Usage: python -m scanner.translate --install es fr de")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
