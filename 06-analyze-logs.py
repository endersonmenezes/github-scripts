##
# Author: Enderson Menezes
# Created: 2024-03-08
# Description: This script converts the JSONL file to CSV
# Usage: python 06-analyze-logs.py
##

import pandas as pd

file_name = 'logs.jsonl'

df = pd.read_json(file_name, lines=True)
df.to_csv(file_name.replace('.jsonl', '.csv'), index=False)

