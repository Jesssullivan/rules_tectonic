"""Public Bazel API for rules_tectonic.

Usage:
    load("@rules_tectonic//tectonic:defs.bzl", "tectonic_pdf")

    tectonic_pdf(
        name = "my_paper",
        src = "paper.tex",
        deps = ["abstract.tex", "intro.tex"],
        data = ["figures/plot.pdf", "refs.bib"],
    )

Produces `my_paper.pdf` under bazel-bin/.
"""

load("//tectonic/private:tectonic_pdf.bzl", _tectonic_pdf = "tectonic_pdf")

tectonic_pdf = _tectonic_pdf
