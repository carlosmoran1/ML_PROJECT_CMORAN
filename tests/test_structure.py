from pathlib import Path

def test_main_directories_exist():
    required = [
        "data/raw",
        "data/interim",
        "data/processed",
        "notebooks",
        "src/data",
        "src/features",
        "src/models",
        "tests",
    ]
    for rel in required:
        assert Path(rel).exists(), f"Falta la carpeta: {rel}"
