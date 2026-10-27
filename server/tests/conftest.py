import os
import tempfile

os.environ['BT_DB_PATH'] = ':memory:'
os.environ['BT_MEMORY_DIR'] = tempfile.mkdtemp()
os.environ['BT_VOICE'] = '0'
os.environ['BT_DEVUI'] = '0'
os.environ['BT_DEVELOPER_MODE'] = '0'
os.environ['BT_LLM_PROVIDER'] = 'ollama'
