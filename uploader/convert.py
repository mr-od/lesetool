import pandas as pd

df = pd.read_csv("./data/battery_degradation.csv")

# Convert DD/MM/YYYY H:MM to standard format
df['timestamp'] = pd.to_datetime(df['timestamp'], format="%d/%m/%Y %H:%M")

# Save to new CSV
df.to_csv("battery_degradation_clean.csv", index=False)