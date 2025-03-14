# -*- coding: utf-8 -*-
"""
GitHub Logs Analysis Tool

Author: Enderson Menezes
Created: 2024-03-08

Description:
    This script converts a JSONL file to CSV format for easier analysis
    of GitHub logs. It uses pandas to read the JSON Lines file and
    export it to a CSV with the same base filename.

Usage: python 06-analyze-logs.py
"""

import pandas as pd

file_name = 'logs.jsonl'

print(f"Converting {file_name} to CSV format...")
df = pd.read_json(file_name, lines=True)
output_file = file_name.replace('.jsonl', '.csv')
df.to_csv(output_file, index=False)
print(f"Conversion complete. Output saved to {output_file}")

