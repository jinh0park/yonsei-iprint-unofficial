# Native protocol notes — experimental implementation

Evidence comes from the original `TASCLNT.exe` (SHA256
26b8299433b1b5985b1c5f7c75ec76706ec7250318db293c0fdd6c07da13cb71).
The original binary is not included in this native app.

Original configuration decodes to `yonsei.svr.i-print.co.kr:30013` and Encrypt Type 6.
This is the same endpoint as the original installer; the client makes no request
until the user chooses Login or Send. No automatic retry, credential logging,
keychain entry, remote diagnostics or background telemetry is implemented.

## Authentication

Reconstructed from 0xcb6cd0 (GETUSER UI request construction), 0xcc27b8
(USERAUTH before printing) and 0xcb1f6c (password conversion).

1. TCP write `USERAUTH:COMMAND\r\n`.
2. Read line and compare uppercase with `USERAUTH:OK`.
3. Send the fixed packed 471-byte record.
4. Read line and compare uppercase with `AUTHUSERPROC:OK`.
5. Read exactly 471 bytes. Decode ID with response salt and compare it with the
   requested account. Extract display name and two balance integers.

Packed record fields used in this implementation:

| Offset | Type | Meaning |
|---|---|---|
| 0x000 | int32 x2 | initialized to zero, semantics not yet established |
| 0x008 | Pascal ShortString[50] | transformed ID |
| 0x03b | Pascal ShortString[56] | transformed password |
| 0x074 | Pascal ShortString[20] | response display name |
| 0x192 | int32 little endian | support credit |
| 0x196 | int32 little endian | deposited credit |
| 0x1d1 | Pascal ShortString[5] | time salt |

Other original record fields are zero on request and are not used in the native UI.
They include card/PIN/contact-related values that the native client does not retain.

ID transformation (0xcb25f0): ASCII bytes, initial uint16 key = int(salt)+0x2b67;
for each byte, ciphertext = plaintext XOR (key >> 8), then
key = uint16((key+ciphertext)*0x6009+0xd425). Return uppercase hexadecimal text.
Salt follows original FormatDateTime('HNNSS') truncated to ShortString[5].

Type 6 password: SHA1 of ASCII password bytes -> hexadecimal -> **lowercase** ->
Base64 ASCII. The lowercase step is 0x424ecc called by 0xcb1f6c. It must not be
confused with 0x424e7c (UpperCase) used for protocol replies.
The first milestone accepts ASCII IDs/passwords only to avoid silently changing
legacy code-page behavior. ID bytes <=25 because hexadecimal must fit in 50 bytes.

## Upload

Original code: 0xcc1d9c. New connection after USERAUTH succeeds:

- `TASA_V300\r\n004` + decimal length + `#$A`
- fixed 1057-byte packed print record
- read 4 ASCII bytes; require `0000`
- write original EXE version `1.0.0.0\r\n`
- write document in chunks <=32768 bytes, require `0000` after each chunk
- read final 4 bytes; native implementation requires `0000` before success

Important original behavior: the decimal header is the size produced by the
serializer 0x81d784, **but the following data is the raw fixed-size packed record**
(0xcc1f51). Do not replace it with the variable-length serialized bytes.
The original serializer also writes overlapping 4-byte fields from 16-bit option
slots. Its size is reproduced and verified against the original function.

Used print record fields: filename 0x000 ShortString[255]; uint64 byte size 0x100;
title 0x108 ShortString[255]; paper 0x208 ShortString[10]; printed pages int16 0x213;
driver 0x215 ShortString[50]; PDL 0x248 ShortString[20]; PrintKind 0x25d
ShortString[10]; color UTF16 char 0x268 ('M'); doc pages int32 0x26a;
N-ups/copies int16 at 0x26e/0x270; duplex char 0x272 ('S'); release char
0x274 ('R'); ID 0x276 ShortString[50]; host 0x2a9 ShortString[255]; IPv4
0x3a9 ShortString[50]; original station 0x3dc ShortString[50]; source char
0x419 ('C'); salt 0x41b ShortString[5]. Remaining bytes are initialized to zero.

Header values, packet layouts and success replies have offline evidence. This
alone does not prove production interoperability, billing or printer behavior.

## Native document wrapper

The Intel Samsung filter is replaced by fixed A4/mono/simplex/1-copy PJL output.
A synthetic PS fixture matches the original filter byte-for-byte after normalizing
service date and OS-version comment. The PostScript body is unchanged. The bundled
ARM64 Ghostscript performs the same ps2write/NoOutputFonts/CompressPages conversion
as the working Wine bridge. Conversion checks PDF page count against DSC counts.

## Validation and limits

- Original SHA1 x86 code executed offline on synthetic inputs (7 vectors).
- Original ID-transform x86 code executed offline (9 vectors).
- Original complete Type6 dispatch executed using a synthetic managed-string and
  hash-stream adapter backed by a separate execution of the original SHA1 routine.
- Original login-button request construction executed with synthetic UI/time
  adapters: all 471 bytes match native fixture after fixing lowercase processing.
- Original metadata serializer yields exactly 231 bytes for native synthetic fixture.
- Original PrintToServer executed with in-memory TCP/file adapters: all 71,086
  request bytes match the native expected stream for a synthetic 70,000-byte document.
- Local TCP peer covers fragmentation, mixed-case replies, bad credentials,
  malformed/truncated records, wrong identity, rejected chunks and missing final ACK.
- UI local one-page PDF conversion verified on this Mac.
- Apple Silicon-only Mach-O dependencies verified; no Wine/Rosetta/Windows binary.

User confirmed actual school login and balance display using version 0.1.2 on 2026-10-17.
User also confirmed server submission and physical printing of the synthetic
one-page PDF through the native app on 2026-10-17. This validates the initial
A4/monochrome/simplex/1-copy path; other document types/options remain unverified.
The initial 0.1.0 and 0.1.1 human login attempts did not pass; this was not counted
as a completed native implementation. Version 0.1.2 fixes lowercase conversion
and case-insensitive reply matching, and includes a bounded status-code diagnostic.

## 0.1.3: member information editing

The original form TfrmMultiFunc has `cxTabSheetUserModify` (사용자수정) and
`BtnUserModiClick` at 0xcb6648. The shared transport dispatch calls 0xcbaff0:

1. `USERMODI:COMMAND\r\n`, expect `MODIUSER:OK` (case-insensitive).
2. Send the fixed 471-byte user record.
3. Expect `MODIUSERPROC:OK` (case-insensitive); no response record follows.

Read-only profile load uses the existing 0xcba808 GETUSER path:
`GETUSER:COMMAND\r\n` -> `GETUSER:OK`, send 471 bytes -> `GETUSERPROC:OK`,
then read a 471-byte profile record. Native UI authenticates with USERAUTH before
this lookup and again immediately before saving. A fresh lookup preserves any
unchanged name/contact/email values and existing card/PIN bytes. Only the three
visible fields can be edited. The current, authenticated password hash is sent;
there is no password-change control. Credit/reserved fields are zero on update,
matching the original modification routine. No changes are sent until Save.

Names/contact/email use lossless CP949 encoding. Name limit is 20 encoded bytes;
phone limit is 13 characters; email limit is 50 encoded bytes. Unrepresentable
characters are rejected before any update request. No silent '?' replacement or
truncation is used. Successful save is followed by GETUSER read-back. An uncertain
save is not retried automatically and the editor requires reloading.

Synthetic validation: original Modify-button request construction, with ASCII
fields, matches all 471 native bytes. Korean CP949 bytes, length/error cases and
PIN preservation are tested separately. Local TCP tests cover read-only access,
saving, read-back mismatch, negative replies and interrupted save responses.
Actual school profile modification is a separate user-driven test.

## Colour capability finding

The original generic client protocol contains a Colour field and a colour-specific
GETPAPERCOST request, so the broader i-Print system can distinguish colour jobs.
The actual installer supplied for this task targets Samsung M4370/5370:

- Windows Driver/ssu5mc.xml: `ColorMode VALUE="FALSE"`, `PRINTERTYPE="MonoPrinter"`.
- Mac Samsung-M4370-5370.ppd: `*ColorDevice: False`.

This device/driver path is monochrome. Native 0.1.3 therefore retains the tested
'M' job metadata and MONO wrapper; it does not label colour data as a mono driver
or add a nonfunctional colour switch. A separate supported colour printer/driver
would require its own capability, wrapper and server compatibility validation.

## 0.1.4: acknowledge-versus-persistence handling

A user screenshot and a subsequent manual reopening on 2026-10-17 showed the
name still as literal question marks after an acknowledged 0.1.3 modification.
This is **not** counted as successful profile modification. Cause is unresolved.
The installer-bundled registration form's Article 9 says the real name and ID
cannot be changed by the member. This is evidence of a possible server-side name
restriction, not proof of current server behavior. The old edit form alone did
not establish that all fields are actually mutable. The separate registration
EXE also contains the same USERMODI handshake and 471-byte transport.

0.1.4 preserves the original request protocol. It identifies unconfirmed fields,
distinguishes unchanged from different returned values, compares canonically
equivalent Unicode text, and presents a visible alert instead of only a generic
status. It warns that the server may restrict name changes. It never substitutes
the requested name into the account display without server confirmation. No
extra write or automatic retry is introduced. A synthetic peer reproduces the
ACK-but-no-update case. This improves reporting; it does not claim to repair
server-side name changes or fix the still-unresolved live persistence issue.

## 0.1.5: native registration

The standalone installer UserJoin/iprint_join.exe constructs a registration user
record in 0xc9144c. In addition to authentication fields and CP949 name/contact:
PIN ShortString[50] at 0x89 and card ID ShortString[50] at 0xbc both contain the
same transformed ID as 0x08; card password ShortString[60] at 0xef is Type6(ID).
Credit and reserved fields are zero. Salt is generated once for the transaction.

The original executes these commands on the same TCP connection with exactly the
same fixed 471-byte record each time:

1. USERDUP:COMMAND -> USERDUP:OK; write record -> IDUSE:OK.
2. USERINS:COMMAND -> ADDUSER:OK; write record -> ADDUSERINS:OK.

All lines use CRLF and responses are case-insensitive. Native registration sends
no request until the user fills the form, checks consent, and clicks the final
button. Duplicate/negative ID checks stop before USERINS. After the second record
may have been sent, an interrupted/negative final reply is treated as uncertain,
not retried automatically, and resubmission in that editor is disabled. Positive
registration acknowledgement is followed by read-only USERAUTH on a fresh
connection to verify login and name. Neither real nor test credentials are logged.
The supplied installer terms/privacy memo (512 source lines) is shown verbatim in
a read-only scroll view with consent initially unchecked. Its source is identified
as the installer, without claiming it is the current website's terms.

IDs are 5-20 ASCII letters/digits/period/underscore/hyphen; passwords 5-20 ASCII
characters with no control characters and an exact confirmation. Name is normalized
to NFC and losslessly CP949-encoded, maximum 20 bytes. Native UI requires a real
phone number (9-13 digits) and a nonempty email (up to 50 encoded bytes); it does
not copy the original's invented fallback phone/email values when left blank.
No original account is deleted or modified by registration.

Offline evidence: standalone original construction executed with synthetic UI/ACP
adapters; the ID and Type6 adapters execute the already verified original TASCLNT
routines. All 471 bytes match, including six CP949 Korean name bytes and the
additional card fields. This is not a live school registration test. 27
registration core checks and seven local TCP cases pass, including duplicate,
interrupted final reply and incorrect name read-back. 27 profile core checks,
eight profile TCP cases and 12 original authentication/upload cases also pass.
The signup UI was exercised using a forced-loopback preview with synthetic terms
and data: consent gating and rejection of an unrepresentable name were verified.
Actual account creation and final agreement are left to the user.

## 0.1.6: refreshed UI and one-action send

AppKit views are reorganized into account, document, send and status cards, with
matching registration/profile sheets and dynamic light/dark colors. The existing
NativeCore source remains byte-identical to 0.1.5.

The main flow is now PDF selection followed by one Send action. That handler
prepares the PDF using the existing prepareDocument implementation when needed,
then uses the original USERAUTH and upload sequence. No separate manual conversion
button is shown. A busy guard prevents concurrent sends. An acknowledged final
upload marks the selected file as submitted and disables Send; explicitly
selecting a PDF again resets that state. The existing uncertain-upload warning
and no-automatic-retry policy remain. Prepared data can be reused for an explicit
retry; choosing another PDF invalidates it. No physical release command is added.

App and Edit menus provide the standard quit and text editing keyboard actions.
Forced-loopback preview modes allow UI inspection and an end-to-end synthetic
GUI send using a local peer, without school traffic or actual account data.
Original physical printing was confirmed in 0.1.2, and live registration/login/
Korean name display in 0.1.5. UI/local peer validation does not constitute a new
physical-print confirmation.

## 0.1.7: read-only member information

The account button and sheet are now labelled 회원 정보 확인. ID, name, phone and
email are non-editable selectable text; the sheet has only a Close action.
The Save handler, editor state, public update API, USERMODI runtime transport and
synthetic mutation CLI route are removed. Profile access performs USERAUTH followed
by GETUSER only. A private record builder is retained solely for registration;
its wire fields are unchanged. Historical protocol analysis above describes the
original Windows client and older app versions, not available 0.1.7 actions.

## 0.1.8: compact document-to-print flow

Removed the custom logo/title/campus header, retaining the native window title.
A decorative downward arrow links the document and print cards. The window is
shorter; authentication, registration, read-only profile access, conversion and
send handlers are unchanged from 0.1.7.

## 0.1.9: PDF first-page thumbnail

The file card renders a bounded first-page thumbnail with the already-linked
system PDFKit framework, asynchronously and without a disk cache or network
request. Each selection resets the placeholder; a generation token ignores stale
results after another selection. Locked or unreadable PDFs retain the placeholder.
The conversion, transmission and account protocol handlers are unchanged.

## 0.1.10: binding and copy count

UI: simplex, long-edge duplex or short-edge duplex; 1–99 collated document copies.
Defaults remain simplex and one copy. Changes discard the prepared job. Busy and
completed jobs lock options; a new explicit PDF selection permits a new job.
The GUI snapshots valid options before conversion, rejects invalid/zero/fractional
copy counts and limits pages × copies to the original signed 16-bit field.

Original import 0xcbed4c initializes duplex to 'S' at 0xcbed8b. The POSTSCRIPT
branch 0xcbeedb–0xcbef87 does not parse or replace that character before it is
copied into record +0x272 at 0xcbf98d. We retain this observed metadata convention;
no speculative 'D' or other server option byte is introduced. The printer obeys
PostScript /Duplex and /Tumble generated from the official Samsung PPD's mappings
(lines 555–560 of Samsung-M4370-5370.ppd). The production printer/server may still
override the job and must be checked by physical printing.

The original import writes document pages to +0x26a, copies to +0x270 and
pages × copies to +0x213 (0xcbf752–0xcbf770). IPPrintRecordWithCopies follows this
layout; the old single-copy function remains a byte-identical compatibility path.
No PDF pages are duplicated in conversion and no copy multiplier is added in PJL.
Ghostscript PSDocOptions emits exactly one /NumCopies /Collate /Duplex /Tumble
setpagedevice setup. This is a distiller parameter, set through -c setdistillerparams
after output parameters and before -f input, not through a userdict -s variable.
The BeginNonPPDFeature NumCopies comment is also recognized by the original
PostScript copy parser at 0x84baf4.

Validation: 42 core checks; 9 actual PostScript interpreter cases (3 bindings ×
1/2/99 copies, three logical pages); original x86 serializer length comparison.
Interpreter instrumentation verifies the requested device setup and persistent
NumCopies on each page; it does not emulate physical duplex mechanics or billing.
No new school traffic or physical printing is included in these local checks.

References: bundled Ghostscript 10.0.0 doc/src/VectorDevices.rst (PSDocOptions),
https://ghostscript.readthedocs.io/en/latest/VectorDevices.html and Samsung's manual
https://printersetup.ext.hp.com/ts/manual/Samsung%20M4370%205370%20Series/English/manual/BABBEJIG.htm

Production-path loopback check: print_flow_harness exercises numeric validation,
stepper change, stale job invalidation, then the unmodified production conversion
and send methods (long-edge duplex, two copies, three logical pages). The peer
observed one upload, six printed page images in metadata, copies=2 and the single
matching PostScript setup; normal success removed the temporary converted job.
The GUI option row, increment control and long-edge selection were also inspected
in a forced-loopback preview. Existing auth/upload (12), signup (7) and read-only
profile (2) cases pass; four default wire/wrapper fixtures remain byte-identical.

## 0.1.11: one authentication button

The primary account action displays 로그인 while signed out and 로그아웃 while
signed in, dispatching to the existing login/logout handlers according to state.
It remains disabled while work is in progress. The separate logout control is
removed and the read-only member information button spans the bottom of the card.
Authentication transport, registration and print options/conversion/upload are
unchanged.

## 0.1.12: remove implementation detail from document card

Removed the conversion/compression explanation under the print options. All
functional handlers, layout coordinates and print settings are unchanged.

## 0.1.13: server-side waiting documents

Original evidence: GetSvrWaitJobList 0xcc2e80, WaitJobDel 0xcc33a0,
WaitJobList 0xcc3f2c, and the original deletion confirmation handler 0xcd304c.
Three synthetic 57-byte requests are byte-identical to execution of the original
x86 request-construction code, including padding, transformed ID and salt.

Query on a separate connection: GETWAITJOBLIST:COMMAND + CRLF ->
GETWAITJOBLIST:OK, then 57 packed bytes: ShortString[50] transformed ID at 0,
ShortString[5] salt at 51. The reply is one LF-terminated CP949 line. Original
ExtractStrings separates records with semicolons, preserving quoted separators;
fields use '&': numeric job ID, registration date, document name, paper, pages,
unit cost, driver, optional source and color. Native parsing is bounded to 1 MiB
and 2,000 rows, validates identifiers/numbers, and rejects ambiguous malformed
records rather than making deletion available. Titles containing unescaped '&'
or malformed quoting may therefore prevent loading; no guessed IDs are used.

Deletion: WAITJOBDEL:COMMAND + CRLF -> WAITJOBDEL:OK, then the decimal job ID
and CRLF. The original does NOT read a completion acknowledgement. Native deletion
is limited to a selected server-returned entry, requires explicit confirmation,
reauthenticates and re-queries the own-account list, and checks the entire selected
entry is unchanged before sending its ID. It then reauthenticates and queries
again; only absence from that fresh list is reported as confirmed. Absence does
not prove whether a simultaneous physical release or the delete caused removal.
Uncertain results never trigger another delete request automatically.

The AppKit queue sheet shows document title, registration time, paper and pages,
with manual refresh, one-document deletion and close controls. Queue contents are
not written to disk and are discarded on closing the sheet. No original PDF is
removed. Already released/printing jobs cannot be assumed cancellable.

Validation: 20 synthetic loopback queue cases, 21 existing authentication/upload/
registration/profile cases, 3 original x86 request comparisons, and 8 local UI
checks. No school network requests, real credentials, live job deletion or physical
printing were performed for this version. School queue interoperability remains
unverified until the user tests it through the app.

## 0.1.14: explicit unofficial application name

Finder bundle name, CFBundleName/CFBundleDisplayName, the main window title and
application menu items now include '(비공식)'. The application identifier and
authentication, conversion, upload and queue protocol handlers are unchanged.
