# CLI command conformance

The ten Core-owned sequences exercise the production dispatcher for analog and modeled stimulation: channels 1-6, single and multiple WSS devices, P/PD models, and PW/PA calibration. Named aliases and numbered channels are both used. Core owns fixtures, expected wire values and stream evaluation. No physical transport is selected.

`./.github/scripts/Invoke-CliCommandConformance.ps1` runs the complete matrix and rejects missing, duplicate, skipped or failed cases. Candidate preflight invokes it against the selected proposed package. Ordinary CI retains its current coverage until canonical dependency adoption; enabling the new command matrix there is a follow-up. The model-only reload remains a direct controller call because the CLI has no model-only command; parameter reload uses the production command.
