PROMPT: Create a script that compares all files in the @dist folder with their corresponding files in the @.bob/ folder. Identify and list all files that differ between these two directories. Generate a comprehensive report showing which files in @dist have not been updated to match the changes made in @.bob/, including details about the differences (file size, modification date, content hash, or line-by-line differences as appropriate). Provide recommendations for updating the @dist folder to synchronize it with @.bob/. Output the results in a clear, structured format that makes it easy to identify which files need to be updated.
DATE: Mon Nov 23 21:18 CET 2026

## Deliverables
- scripts/compare_bob_dist.sh (read-only; writes report to reports/, exit 1 if out of sync)
- .env.example (optional settings); .gitignore gets .env and reports/

## Result (16 files compared: 6 identical, 9 modified, 1 missing in dist, 0 extra)
Out of date in dist/.bob:
- custom_modes.yaml (+26/-14)
- mcp.json (dist lacks local bob-marketplace entry; MANUAL REVIEW, holds a local token, do not copy)
- skills/qse-remediation/SKILL.md (+34/-17)
- skills/qse-remediation/references/pr_template.md (MISSING)
- skills/qse/1_workflow.md, 2_best_practices.md, 6_qcm_integration.md, SKILL.md (GCM -> QCM renames)
Out of date in dist/ root:
- README.md (+1 line: GitHub repo link)
- bob-qse-remediation-1.0.0.zip (49759 vs 47478 bytes; rebuild after syncing)
Identical: remediation_patterns.md, remediation_tool.py, 3_command_construction.md, 4_language_detection.md, 5_examples.md, requirements.txt

## Sync commands
cp -p .bob/custom_modes.yaml dist/.bob/custom_modes.yaml
cp -p .bob/skills/qse-remediation/SKILL.md dist/.bob/skills/qse-remediation/SKILL.md
cp -p .bob/skills/qse-remediation/references/pr_template.md dist/.bob/skills/qse-remediation/references/pr_template.md
cp -p .bob/skills/qse/{1_workflow,2_best_practices,6_qcm_integration,SKILL}.md dist/.bob/skills/qse/   (per-file)
cp -p README.md dist/README.md
Then rebuild the zip, review mcp.json manually, re-run the script (expect exit 0).
