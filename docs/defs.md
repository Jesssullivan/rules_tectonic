<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Public Bazel API for rules_tectonic.

Usage:
    load("@rules_tectonic//tectonic:defs.bzl", "tectonic_pdf")

    tectonic_pdf(
        name = "my_paper",
        src = "paper.tex",
        deps = ["abstract.tex", "intro.tex"],
        data = ["figures/plot.pdf", "refs.bib"],
    )

Produces `my_paper.pdf` under bazel-bin/.

<a id="tectonic_pdf"></a>

## tectonic_pdf

<pre>
load("@rules_tectonic//tectonic:defs.bzl", "tectonic_pdf")

tectonic_pdf(<a href="#tectonic_pdf-name">name</a>, <a href="#tectonic_pdf-deps">deps</a>, <a href="#tectonic_pdf-src">src</a>, <a href="#tectonic_pdf-data">data</a>, <a href="#tectonic_pdf-bundle">bundle</a>, <a href="#tectonic_pdf-extra_args">extra_args</a>, <a href="#tectonic_pdf-format">format</a>, <a href="#tectonic_pdf-only_cached">only_cached</a>, <a href="#tectonic_pdf-reruns">reruns</a>, <a href="#tectonic_pdf-synctex">synctex</a>,
             <a href="#tectonic_pdf-untrusted">untrusted</a>)
</pre>

Compile a LaTeX source into a PDF using tectonic.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="tectonic_pdf-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="tectonic_pdf-deps"></a>deps |  Additional TeX sources (chapters, packages) the main source includes.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="tectonic_pdf-src"></a>src |  The main .tex source.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="tectonic_pdf-data"></a>data |  Non-TeX inputs the source references (images, fonts, bib files, etc.).   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="tectonic_pdf-bundle"></a>bundle |  Optional pinned Tectonic bundle file to use instead of the default network bundle.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="tectonic_pdf-extra_args"></a>extra_args |  Additional arguments passed to `tectonic -X compile`.   | List of strings | optional |  `[]`  |
| <a id="tectonic_pdf-format"></a>format |  Tectonic format name or path passed with `--format`.   | String | optional |  `"latex"`  |
| <a id="tectonic_pdf-only_cached"></a>only_cached |  Pass `--only-cached` so Tectonic uses only locally cached bundle resources.   | Boolean | optional |  `False`  |
| <a id="tectonic_pdf-reruns"></a>reruns |  Pass `--reruns` when non-negative. The default -1 leaves Tectonic's default rerun behavior unchanged.   | Integer | optional |  `-1`  |
| <a id="tectonic_pdf-synctex"></a>synctex |  Generate SyncTeX data and expose it via the `synctex` output group.   | Boolean | optional |  `False`  |
| <a id="tectonic_pdf-untrusted"></a>untrusted |  Pass `--untrusted` to disable known-insecure TeX features for untrusted inputs.   | Boolean | optional |  `False`  |


