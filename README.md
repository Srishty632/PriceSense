# PriceSense
### A SQL-Driven Pricing Intelligence Framework
**E-Cell IIT Guwahati | Summer Projects 2026**

---

## What this is
A pricing intelligence module for a D2C nutrition brand launching 
high-protein snacks. Built entirely in SQL on 50,150 real transactions 
across 5 datasets.

## The 5 findings
1. **The $20 Wall** — demand drops 65% the moment a product crosses $20
2. **Persona labels don't predict price** — income bracket is the real signal
3. **Keto earns +$7.71 above market** — high-protein earns only +$1.50
4. **Tier 2 cities outperform metros** — $127.77 vs $121.11 revenue per order
5. **Gym and fasting buyers pay more** — intent-driven occasions = lower price sensitivity

## Files
| File | Purpose |
|---|---|
| `sql/PriceSense_01_DataCleaning.sql` | Data cleaning as reusable SQL VIEWs |
| `sql/PriceSense_02_Phase1_Sensitivity.sql` | Price bucketing and demand cliff detection |
| `sql/PriceSense_03_Phase2_Contextual.sql` | Claims, geography, occasion analysis |
| `sql/PriceSense_04_KeyFindings.sql` | 5 pre-interpreted findings for the deck |
| `deck/PriceSense_Deck.pptx` | 9-slide strategy presentation |

## Notebook
Full analysis with markdown documentation:
[Kaggle Notebook](paste your kaggle notebook URL here)

## Dataset
50,150 transactions · 5,000 buyer profiles · 150 products · 
47,581 geography records · 720 competitor price observations
