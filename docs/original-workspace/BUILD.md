# Native client 0.1.12

Run `python3 outputs/iprint-native/source/build.py` in the original workspace.
Requires the Apple command-line developer tools and the existing ARM64 Ghostscript build.
The app uses Foundation, AppKit, PDFKit and CommonCrypto from macOS. No Python runtime,
Windows EXE/DLL, Wine, Intel filter or Rosetta is used by the app.
Minimum deployment is macOS 15, matching the existing Ghostscript binary.

Ghostscript corresponding source: `../Source Materials/ghostscript-10.0.0.tar.gz`.
Official release: https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/tag/gs1000
Full modified files in `macos-sdk-fixes/`: zlib/zutil.h and libpng/pngpriv.h.
They add `!defined(__APPLE__)` to classic Mac OS-only TARGET_OS_MAC branches.
Configure and compile the unpacked tree after replacing those two files:

```
./configure --prefix=/iprint-bundled --without-x --disable-cups --disable-gtk \
  --disable-fontconfig --without-tesseract --without-libidn
make -j4 CFLAGS_STANDARD='-O2 -DNDEBUG -mmacosx-version-min=13.0' \
  XCFLAGS='-Wno-error=declaration-after-statement' XLDFLAGS='-mmacosx-version-min=15.0'
```

App sources are here and inside Contents/Resources/Source. Source materials are
supplied beside the app so the installed app can stay small. Keep them with any
redistributed copy. Ad hoc signing is not Developer ID signing or notarization.

Protocol evidence and synthetic oracle vectors are in the sibling research report.
`--self-test`, `--fixtures` and `--test-network` modes exercise synthetic inputs;
the network test command only accepts 127.0.0.1 and has no real credential arguments.

Regression checks:

```
python3 outputs/iprint-native/source/tests/test_protocol.py
python3 outputs/iprint-native/source/tests/test_profile_protocol.py
xcrun clang -fobjc-arc -fblocks -fno-modules -framework Foundation -arch arm64 \
  -I outputs/iprint-native/source outputs/iprint-native/source/NativeCore.m \
  outputs/iprint-native/source/tests/registration_core_tests.m -o /tmp/registration_core_tests
/tmp/registration_core_tests
```

`--preview-profile` opens the read-only member information sheet with synthetic data and forces all connections
to loopback port 1. It never uses the school hostname. It is for UI validation only.

0.1.6 UI inspection:

- `--preview-dashboard` and `--preview-dashboard-dark`: forced loopback port 1.
- `--preview-send-test <port>`: forced 127.0.0.1, synthetic NativeTest credential
  prefill only; requires manually clicking Login and Send against a local peer.
- UI test previews must never use actual school credentials or actual account
  creation. `--preview-registration` substitutes synthetic terms.

Registration protocol regression: `python3 outputs/iprint-native/source/tests/test_registration_protocol.py`.

0.1.12 print options checks (offline, synthetic):

```
xcrun clang -fobjc-arc -fblocks -fno-modules -framework Foundation -arch arm64 \
  -I outputs/iprint-native/source outputs/iprint-native/source/NativeCore.m \
  outputs/iprint-native/source/tests/print_options_tests.m -o /tmp/print_options_tests
python3 outputs/iprint-native/source/tests/test_print_options.py \
  /tmp/print_options_tests /tmp/iprint-option-check
```

`print_flow_harness.m` compiles instead of `main.m`, alongside `NativeCore.m`
and the usual Cocoa/PDFKit/UniformTypeIdentifiers frameworks. Place that test
executable in a disposable app bundle with the normal resources. It runs the
production prepareDocument/doSend methods with forced loopback and synthetic
credentials only; it creates no windows and never contacts the school server.
Arguments: local peer port, synthetic three-page PDF. The peer must implement
two synthetic authentication requests and one upload for long-edge duplex,
2 copies, 3 logical pages and 6 printed page images.
