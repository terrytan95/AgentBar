# Source Han Sans Bundle-Size Options

## Question

How can AgentBar reduce the release ZIP size without replacing Source Han Sans
with a different typeface?

## Recommendation

Replace the three static, full-glyph-set SC OTFs with Adobe's official
`SourceHanSansSC-VF.otf`.

This is the only high-impact option that preserves the complete 65,535-glyph
Pan-CJK set and the Source Han Sans design. Adobe describes its language-specific
variable fonts as the most compact configuration that still contains the
complete glyph set and all seven weights. The tradeoff is an integration change:
the registered family becomes `Source Han Sans SC VF`, so AgentBar must register
one file and update the cascade family name. The font design and coverage do not
change. See Adobe's [Source Han Sans readme][adobe-readme] and [release files][adobe-release].

Measured with the exact Adobe 2.005R binaries:

| Configuration | Raw font bytes | Deflated font bytes | Raw reduction |
| --- | ---: | ---: | ---: |
| Current SC Regular + Medium + Bold OTFs | 50,039,588 | 41,843,413 | baseline |
| Full SC variable OTF, all seven weights | 31,749,144 | 19,244,877 | 36.6% |
| Official CN subset, three static OTFs | 25,405,088 | 22,213,196 | 49.2% |
| Official CN subset variable OTF, all seven weights | 15,636,088 | 10,801,773 | 68.8% |
| Official CN subset variable WOFF2 | 7,995,716 | 7,997,132 | 84.0% |

The deflated figures are the approximate contribution of the font files to the
release ZIP. The current three repository files have the same Git blob hashes
as Adobe's 2.005R release files, so this is a like-for-like comparison, not a
version difference. To remove unit and archive-overhead ambiguity, the actual
v2.2.13 app was also repacked with `/usr/bin/ditto` after replacing only these
font files:

| Configuration | Measured AgentBar ZIP |
| --- | ---: |
| Current three SC OTFs | 44.75 MiB |
| Full SC variable OTF | 23.34 MiB |
| Official CN subset, three static OTFs | 26.03 MiB |
| Official CN subset variable OTF | 15.23 MiB |

## Options and tradeoffs

### 1. Full SC variable OTF: recommended

Adobe's full SC variable OTF stores all seven named weights in one 31.75 MB file.
The three current static fonts total 50.04 MB. More importantly for the shipped
ZIP, the variable file deflates to 19.24 MB versus 41.84 MB for the three static
files.

Advantages:

- Keeps all 65,535 glyphs and the complete current Unicode coverage.
- Keeps Source Han Sans and supplies Regular, Medium, Bold, and the intermediate
  Semibold value through the continuous `wght` axis.
- Uses an official, unmodified Adobe binary, avoiding derivative-font naming and
  licensing concerns.
- Registers successfully with CoreText and exposes seven named descriptors in a
  local macOS 27 test. AgentBar's minimum deployment target is macOS 14.

Required validation:

- Update the cascade family from `Source Han Sans SC` to
  `Source Han Sans SC VF` and register the single file.
- Visually compare Chinese text at AgentBar's small UI sizes for Regular,
  Medium, Semibold, and Bold.
- Verify SwiftUI's weight trait selects the expected variable instances through
  the cascade descriptor.

Adobe explicitly says its language-specific variable fonts contain all seven
weights and the complete glyph set. OpenType CFF2 represents multiple variants
with blend data, which explains why a single variable file can be smaller than
three duplicated static CFF fonts. See the [Adobe configuration description][adobe-readme]
and the [OpenType CFF2 specification][cff2-spec].

### 2. Official CN region subset: smaller, but narrower coverage

Adobe's CN subset is still Source Han Sans, but it drops glyphs unnecessary for
the Simplified Chinese region and uses the registered family name
`Source Han Sans CN` (or `Source Han Sans CN VF`). Adobe calls region-specific
subsets the recommended smallest-footprint option when only one region is
needed.

The CN subset has 31,072 glyphs instead of 65,535. Adobe documents its coverage
as all GB 18030-2022 Implementation Level 2 hanzi, the remaining URO and
Extension A glyphs in Level 3, and all 8,105 characters in the Table of General
Standard Chinese Characters. It is therefore much safer than building a subset
only from AgentBar's current source strings. It does not preserve the complete
Japanese, Korean, Traditional Chinese, or rare-extension glyph set; missing
characters will cascade to another font and can look inconsistent.

Two official variants are useful:

- Three static CN OTFs: a measured 26.03 MiB AgentBar ZIP. This is the smaller
  code change and keeps explicit Regular, Medium, and Bold files.
- One CN variable OTF: a measured 15.23 MiB AgentBar ZIP. This gives the best
  supported native-font footprint, but combines both the region-coverage and
  variable-font integration changes.

See Adobe's [region subset files][adobe-cn-subset] and the glyph-set table in the
[official readme][adobe-readme].

### 3. Remove hinting: modest gain, custom derivative

fontTools supports `--no-hinting`, which removes CFF glyph hints and related
font-wide data. Its documentation says this can sometimes reduce a font by up to
30% and is suitable for high-resolution displays. A local all-glyph experiment
on the current Regular OTF reduced:

- Raw OTF: 16,529,832 to 13,579,820 bytes (17.8%).
- Deflated OTF: 13,737,127 to 11,061,587 bytes (19.5%).

On Adobe's official CN Regular subset, the same experiment reduced the deflated
font by 18.0%. This is materially less valuable than switching to an official
variable font, and it needs visual QA at AgentBar's 9-13 pt text sizes because
hints can affect small-size rasterization. See the [fontTools subset and hinting
documentation][fonttools-subset].

This also creates a modified font. Adobe's OFL declares `Source` a Reserved Font
Name and says a modified version cannot use a reserved name without permission.
Accordingly, a custom no-hint or custom-glyph subset should be renamed and ship
with the license; retaining the exact current family name is not a clean option.
See Adobe's [Source Han Sans license][adobe-license].

### 4. Custom glyph subsetting: largest theoretical gain, highest product risk

`fonttools subset` can select characters from text or Unicode ranges and keeps
layout closure by default, including glyphs reached through retained OpenType
features. It can therefore make a very small font if given only AgentBar's
current Chinese UI strings. That corpus is not the real runtime corpus: account
names, project names, model labels, errors, and future localizations can contain
arbitrary characters. Missing characters would silently switch to a system
fallback.

If a custom subset is ever considered, it should use a reviewed Unicode-range
policy, retain layout closure and required `locl`/vertical features, include a
missing-glyph regression corpus, and rename the derivative font under the OFL.
Adobe's official CN subset is the safer coverage boundary.

### 5. Re-subroutinizing CFF: not a meaningful primary lever

The current Regular font's CFF table is 15.55 MB of its 16.53 MB total, and the
Adobe release binaries already use CFF subroutines. fontTools keeps
subroutinization by default and only removes unused subroutines. Its
`--desubroutinize` option is chiefly worth testing for very small subsets or
WOFF/WOFF2 output, not full native OTFs.

Adobe's AFDKO guide says subroutinization usually yields only a few percent for
Japanese and Chinese CID fonts because their paths have fewer repeating
elements. Re-running a CFF subroutinizer is therefore unlikely to approach the
savings from the official variable configuration. See the [AFDKO MakeOTF
guide][afdko-subr] and [fontTools CFF subset options][fonttools-subset].

### 6. OTC: larger for this use case

The Regular, Medium, and Bold static OTC files total 57,955,216 raw bytes,
15.8% more than the current three SC OTFs. Each collection includes several
regional font instances, which AgentBar does not need. Adobe also cautions that
OpenType Collections are not supported everywhere. OTC is useful for sharing
data across several language instances, not for one SC fallback family.

### 7. WOFF2: do not ship as a native app font

The official CN variable WOFF2 is only 8.00 MB, but WOFF2 is a web-font container.
The W3C specification identifies browsers using it with HTML/CSS. Apple exposes
`CTFontManagerIsSupportedFont` as the supported-format gate and does not promise
WOFF2 registration compatibility across AgentBar's macOS range.

On the current macOS 27 machine, CoreText could parse and register Adobe's WOFF2
and enumerate seven descriptors, but `CTFontManagerIsSupportedFont` returned
`false`. That contradictory result is not a compatibility contract and is not
safe for a macOS 14+ release. See the [WOFF2 specification][woff2-spec] and
[Apple's CoreText support check][coretext-supported].

## Decision

Use the full SC variable OTF first. It approximately halves the current release
ZIP while preserving Source Han Sans and complete glyph coverage. If reducing
the ZIP below roughly 20-25 MB is more important than Pan-CJK coverage, evaluate
the official CN subset variable OTF next. Do not lead with custom hint removal,
custom subsetting, CFF re-subroutinization, OTC, or WOFF2.

## Reproduction notes

- Raw sizes came from Adobe's GitHub `release` branch Contents API and local
  `stat` checks.
- Deflated sizes were measured with `/usr/bin/zip -9` on each font file. ZIP
  directory overhead is negligible but means these are payload estimates, not
  byte-exact predictions for the final app archive.
- Full AgentBar ZIP sizes were measured by replacing only the font payload in
  the unpacked v2.2.13 app and repacking it with `/usr/bin/ditto`.
- Glyph counts, Unicode counts, font names, and table sizes were inspected with
  fontTools 4.63.0.
- CoreText checks used `CTFontManagerRegisterFontsForURL`,
  `CTFontManagerCreateFontDescriptorsFromURL`, and
  `CTFontManagerIsSupportedFont` in an isolated process.

[adobe-readme]: https://github.com/adobe-fonts/source-han-sans/blob/release/SourceHanSansReadMe.pdf
[adobe-release]: https://github.com/adobe-fonts/source-han-sans/releases/tag/2.005R
[adobe-cn-subset]: https://github.com/adobe-fonts/source-han-sans/tree/release/SubsetOTF/CN
[adobe-license]: https://github.com/adobe-fonts/source-han-sans/blob/master/LICENSE.txt
[cff2-spec]: https://learn.microsoft.com/en-us/typography/opentype/spec/cff2
[fonttools-subset]: https://fonttools.readthedocs.io/en/latest/subset/
[afdko-subr]: https://adobe-type-tools.github.io/afdko/MakeOTFUserGuide.html
[woff2-spec]: https://www.w3.org/TR/WOFF2/
[coretext-supported]: https://developer.apple.com/documentation/coretext/ctfontmanagerissupportedfont(_:)
