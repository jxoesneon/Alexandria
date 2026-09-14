import re

with open('coverage/lcov.info', 'r') as f:
    content = f.read()

records = content.split('end_of_record')
files = []
total_found = 0
total_hit = 0

for rec in records:
    rec = rec.strip()
    if not rec:
        continue
    sf_match = re.search(r'SF:(.*)', rec)
    if not sf_match:
        continue
    file_path = sf_match.group(1)
    if 'lib/data/database.g.dart' in file_path:
        continue
    lf_match = re.search(r'LF:(\d+)', rec)
    lh_match = re.search(r'LH:(\d+)', rec)
    if lf_match and lh_match:
        lf = int(lf_match.group(1))
        lh = int(lh_match.group(1))
        pct = (lh / lf * 100) if lf > 0 else 100.0
        files.append((file_path, lh, lf, pct))
        total_found += lf
        total_hit += lh

files.sort(key=lambda x: x[3])
for f, lh, lf, pct in files[:20]:
    print(f"{pct:6.2f}% ({lh:4d}/{lf:4d}) - {f}")

print("-" * 50)
print(f"Total Non-Generated: {total_hit}/{total_found} = {total_hit/total_found*100:.2f}%")
