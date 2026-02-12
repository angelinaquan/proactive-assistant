# Exclude test_e2e.py from automatic pytest collection.
# It requires a running server and should be run manually:
#   python3 test_e2e.py
collect_ignore = ["test_e2e.py"]
