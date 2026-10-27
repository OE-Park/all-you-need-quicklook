# Source and script preview formats

The installed app declares 252 suffixes in 61 source type groups. macOS System Settings controls whether the Quick Look extension is enabled. App settings only change formatting. Declared eligibility does not force macOS to choose this provider over another installed app.

The bundled highlight.js common build is extended with 30 official, version-matched 11.12.0 grammars. `plaintext` entries are deliberately readable text without guessed syntax. The version, download URLs, and SHA-256 hashes are in `Shared/Resources/js/highlight.PROVENANCE.json`; BSD-3-Clause terms are in `highlight.LICENSE.txt`.

| Highlight language | Declared suffixes |
| --- | --- |
| apache | `.apache`, `.htaccess` |
| armasm | `.asm`, `.s` |
| bash | `.bash`, `.bash_profile`, `.bashrc`, `.command`, `.env`, `.ksh`, `.profile`, `.sh`, `.zprofile`, `.zsh`, `.zshrc` |
| c | `.c`, `.h` |
| clojure | `.clj`, `.cljc`, `.cljs`, `.edn` |
| cmake | `.cmake` |
| cpp | `.c++`, `.cc`, `.cpp`, `.cxx`, `.h++`, `.hh`, `.hpp`, `.hxx`, `.ino`, `.ipp`, `.tpp` |
| csharp | `.cs`, `.csx` |
| css | `.css` |
| dart | `.dart` |
| diff | `.diff`, `.patch` |
| dockerfile | `.containerfile`, `.dockerfile` |
| dos | `.bat`, `.cmd` |
| elixir | `.ex`, `.exs` |
| erlang | `.erl`, `.hrl` |
| fortran | `.f`, `.f03`, `.f08`, `.f90`, `.f95`, `.for` |
| fsharp | `.fs`, `.fsi`, `.fsscript`, `.fsx` |
| go | `.go` |
| gradle | `.gradle` |
| graphql | `.gql`, `.graphql` |
| groovy | `.groovy`, `.gsh`, `.gvy`, `.gy` |
| haskell | `.hs`, `.lhs` |
| ini | `.automount`, `.cfg`, `.cnf`, `.conf`, `.desktop`, `.editorconfig`, `.ini`, `.mount`, `.path`, `.prefs`, `.properties`, `.reg`, `.service`, `.socket`, `.target`, `.timer`, `.toml` |
| java | `.java` |
| javascript | `.cjs`, `.es6`, `.js`, `.jsm`, `.jsx`, `.mjs` |
| json | `.json`, `.json5`, `.jsonc`, `.jsonl`, `.ndjson` |
| julia | `.jl` |
| kotlin | `.kt`, `.kts` |
| latex | `.cls`, `.dtx`, `.ltx`, `.sty`, `.tex` |
| less | `.less` |
| lisp | `.cl`, `.lisp`, `.lsp` |
| lua | `.lua` |
| makefile | `.makefile`, `.mk` |
| matlab | `.matlab` |
| nginx | `.nginx` |
| nim | `.nim`, `.nims` |
| nix | `.nix` |
| objectivec | `.m`, `.mm` |
| ocaml | `.ml`, `.mli` |
| perl | `.pl`, `.pm` |
| php | `.php`, `.php3`, `.php4`, `.php5`, `.phps`, `.phtml` |
| plaintext | `.abap`, `.ada`, `.adb`, `.ads`, `.ahk`, `.asmdef`, `.asmref`, `.au3`, `.awk`, `.cbl`, `.cob`, `.cr`, `.cu`, `.cuh`, `.d`, `.e`, `.eex`, `.elm`, `.fish`, `.frag`, `.gd`, `.geom`, `.glsl`, `.hcl`, `.heex`, `.hppin`, `.inc`, `.leex`, `.metal`, `.move`, `.pas`, `.pde`, `.pp`, `.prg`, `.purs`, `.rkt`, `.sed`, `.sol`, `.tcl`, `.tf`, `.tfvars`, `.tk`, `.vala`, `.vapi`, `.vbe`, `.vbs`, `.vert`, `.wgsl`, `.zig`, `.zon` |
| powershell | `.ps1`, `.psd1`, `.psm1`, `.psrc`, `.pssc` |
| prolog | `.pro`, `.prolog` |
| protobuf | `.proto` |
| python | `.pxd`, `.pxi`, `.py`, `.pyi`, `.pyw`, `.pyx` |
| r | `.r` |
| ruby | `.gemfile`, `.gemspec`, `.podspec`, `.rake`, `.rb`, `.ru` |
| rust | `.rs` |
| scala | `.sc`, `.scala` |
| scheme | `.scm`, `.sld`, `.ss` |
| scss | `.sass`, `.scss` |
| sql | `.ddl`, `.dml`, `.sql` |
| swift | `.swift` |
| typescript | `.cts`, `.mts`, `.tsx` |
| vbnet | `.vb` |
| verilog | `.sv`, `.svh`, `.v`, `.vh` |
| vhdl | `.vhd`, `.vhdl` |
| wasm | `.wat` |
| xml | `.astro`, `.atom`, `.axaml`, `.csproj`, `.fsproj`, `.htm`, `.html`, `.plist`, `.pom`, `.props`, `.ps1xml`, `.rdf`, `.resx`, `.rss`, `.svelte`, `.svg`, `.targets`, `.vbproj`, `.vue`, `.wsdl`, `.xaml`, `.xhtml`, `.xlf`, `.xliff`, `.xml`, `.xsd`, `.xsl`, `.xslt` |
| yaml | `.yaml`, `.yml` |

## Limits and activation

- Enable/disable only in System Settings → General → Login Items & Extensions → Quick Look → AllYouNeedQuickLook. The app opens this page but does not change the activation state.
- `.ts` is deliberately not newly registered: macOS also uses it for MPEG transport streams. TypeScript source still resolves a highlight grammar when delivered to this renderer, but Finder routing for `.ts` is not promised. `.tsx`, `.mts`, `.cts` have source declarations.
- `.wasm` is binary and not a text-preview claim; `.wat` is text.
- Existing installed software may own conflicting suffixes, including `.bat` and `.exs`. The app does not relabel those existing non-text types or override their handlers. Verify the actual Finder provider.
- Extensionless build files and dotfiles are not automatically covered by extension declarations. For example, a filename literally `Dockerfile` is distinct from `sample.dockerfile`.
- BOM-marked UTF-8, UTF-16LE/BE and UTF-32LE/BE are decoded before the legacy Latin-1 fallback. Scripts are displayed, never executed.

Reference: [Apple file type declarations](https://developer.apple.com/documentation/uniformtypeidentifiers/defining-file-and-data-types-for-your-app), [official highlight.js CDN distribution](https://github.com/highlightjs/highlight.js/blob/main/README.CDN.md).
