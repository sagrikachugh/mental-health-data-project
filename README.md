# Victorian regional mental-health service utilisation

[View the analytical briefing](https://sagrikachugh.github.io/mental-health-data-project/)

## Purpose

This portfolio case study addresses the business question:

> **How has mental-health service utilisation changed across regional Victorian PHNs, and which patterns warrant further operational review?**

It provides a concise, descriptive briefing on community mental-health contacts, emergency department presentations and hospitalisations across Gippsland, Murray and Western Victoria. The briefing page contains the findings, figures, operational questions and interpretation.

## Repository contents

- `analysis.R` — cleans and validates the source exports, calculates trends and percentage changes, and recreates all outputs.
- `R/briefing_helpers.R` — validates briefing inputs and derives dashboard metrics, tables and data-driven narrative.
- `index.qmd` — Quarto source for the management-style analytical briefing.
- `docs/` — rendered GitHub Pages briefing.
- `data/raw/` — original AIHW dashboard exports.
- `data/victorian_phn_rates.csv` — validated analysis dataset.
- `figures/` — four publication-quality figures in PNG and PDF.
- `results/` — briefing tables, validation checks and session information.

## Technology

The analytical workflow uses **R only**, with `dplyr`, `tidyr`, `readr`, `ggplot2` and `scales`. **Quarto** combines the R outputs with the briefing narrative, and **SCSS** controls the page styling. Quarto generates the published HTML, CSS and JavaScript assets; no custom Python or JavaScript analysis code is used.

## Reproduce

Requirements: R 4.1+, the packages listed above, and Quarto 1.10+.

```bash
Rscript analysis.R
quarto render
```

A successful analysis run writes six passing checks to `results/validation_checks.csv`. `quarto render` rebuilds the site in `docs/`.

## Data

Source: [AIHW Regional profiles of mental health service activity](https://www.aihw.gov.au/mental-health/monitoring/regional-profiles), dashboard exports retrieved 27 September 2026.

The project uses published all-age crude rates per 10,000 population for three regional Victorian PHNs from 2018–19 to 2023–24. Original exports are retained so the full workflow can be rerun without downloading the data again.

## Interpretation

This is descriptive service-utilisation analysis. It does not assess causation, service quality, unmet need or outcomes. See the analytical briefing for the complete findings, operational implications and limitations.
