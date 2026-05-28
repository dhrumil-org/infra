# Architecture diagrams

This directory holds the architecture diagram source and rendered exports
referenced in `../HIPAA-COMPLIANCE.docx` §3.

## Files to keep here

| File | Purpose |
|---|---|
| `architecture.eraser` | Source from eraser.io (re-editable) |
| `architecture.png` | Rendered PNG (2x or 4x scale, transparent bg) — embed in the Word doc |
| `architecture.svg` | Vector version — for re-rendering at any resolution |

## Workflow

1. Open `../ERASER-AI-PROMPT.md`, copy the prompt block
2. Paste into https://www.eraser.io/ai/aws-diagram-generator → Generate
3. Tweak in the eraser editor as needed
4. Download all three files and save them here with the names above
5. In `../HIPAA-COMPLIANCE.docx`, replace the placeholder box at the
   top of §3 with the PNG (Insert → Picture → choose `architecture.png`)
6. Commit the source + exports so the diagram is regenerable

## When the architecture changes

1. Edit the prompt in `../ERASER-AI-PROMPT.md` OR open
   `architecture.eraser` directly in eraser.io and edit
2. Re-export the PNG/SVG
3. Replace the image in the docx (right-click → Change Picture)
4. Commit all three files together
