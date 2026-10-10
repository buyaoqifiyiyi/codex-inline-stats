# Isolated Python startup with an explicit, application-owned module directory.
import runpy, sys
from pathlib import Path
folder = Path(__file__).resolve().parent
sys.path.insert(0, str(folder))
runpy.run_path(str(folder/'reader.py'), run_name='__main__')
