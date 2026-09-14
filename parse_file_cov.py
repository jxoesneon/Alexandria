import sys, re

target = sys.argv[1]
with open('coverage/lcov.info') as f:
    content = f.read()

for rec in content.split('end_of_record'):
    if f"SF:{target}" in rec:
        for line in rec.splitlines():
            if line.startswith('DA:'):
                parts = line[3:].split(',')
                line_no, hits = int(parts[0]), int(parts[1])
                if hits == 0:
                    print(f"Uncovered line: {line_no}")
