"""Root conftest — makes custom_components importable from the repo root."""

import sys
from pathlib import Path

# custom_components/ lives at the repo root, one level above homeassistant/.
sys.path.insert(0, str(Path(__file__).parent.parent))
