# PLOS ONE figure audit and export report

## Figure contract

- Backend: R only for plotting, export, preview generation, and visual QA.
- Target: PLOS ONE submission with restrained Nature-style visual discipline.
- Palette: neutral greys, one signal blue, one muted red mortality contrast, and one restrained teal Supplementary accent.
- Font: Arial family with compact journal-scale text.
- Export bundle: editable PDF and SVG, 600 dpi TIFF, R-generated PNG preview, and clean CSV source data.
- SVG exports use svglite and retain editable text nodes.

## Evidence hierarchy

1. Figure 1 is the hero thyroid-association figure: it shows the approximately linear UACR-TT4 association and clinical thresholds.
2. Figure 2 is the main mortality figure: it separates the stable UACR signal from the more modest TT4 signal across sensitivity analyses.
3. Figure S1 is secondary and descriptive: joint mortality groups do not support a monotonic combined-risk claim.
4. Figure S2 is Supplementary exploratory genetic evidence only and is not part of the main causal argument.

## Review-risk controls

- No new models or exploratory analyses were added during figure polishing.
- Source-data CSV files were generated for every polished figure.
- Joint-group and genetic figures were explicitly retained as Supplementary outputs.
- The mortality figure uses colour and shape, so interpretation does not depend on colour alone.
- RCS clinical thresholds are directly labelled at 30 and 300 mg/g.
- Final visual review should still be performed in the journal upload preview.

## Submission outputs

- `outputs/figures/submission/Figure1_RCS_TT4.pdf`
- `outputs/figures/submission/Figure2_mortality_forest.pdf`
- `outputs/figures/submission/FigureS1_joint_mortality.pdf`
- `outputs/figures/submission/FigureS2_exploratory_MR_forest.pdf`
- `outputs/tables/final_figure_list.csv`
